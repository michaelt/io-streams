{-# LANGUAGE OverloadedStrings #-}

module System.IO.Streams.Tests.File (tests) where

------------------------------------------------------------------------------
import           Control.Exception
import           Control.Monad                  hiding (mapM)
import           Data.ByteString.Char8          (ByteString)
import qualified Data.ByteString.Char8          as S
import qualified Data.ByteString.Lazy.Char8     as L
import           Data.List
import           Prelude                        hiding (mapM, read)
import           System.Directory
import           System.FilePath
import           System.IO
import           System.IO.Streams              hiding (intersperse, mapM_)
import           Test.Framework
import           Test.Framework.Providers.HUnit
import           Test.HUnit                     hiding (Test)
------------------------------------------------------------------------------
import           System.IO.Streams.Tests.Common

tests :: [Test]
tests = [ testFiles
        , testBigFiles
        ]


------------------------------------------------------------------------------
copyingListOutputStream :: IO (OutputStream ByteString, IO [ByteString])
copyingListOutputStream = do
    (os, grab) <- listOutputStream
    os' <- contramap S.copy os >>= lockingOutputStream
    return (os', grab)


------------------------------------------------------------------------------
testFiles :: Test
testFiles = testCase "file/files" $ do
    createDirectoryIfMissing False "tmp"
    sequence_ [tst1, tst2, tst3, tst4, tst5] `finally` cleanup

  where
    fn x = ("tmp" </> "data") ++ show (x :: Int)

    cleanup = eatException $ do
                  mapM_ (eatException . removeFile . fn) [1, 2, 3, 4, 5]
                  removeDirectory "tmp"

    tst mode n = do
        withFileAsOutputExt (fn n) mode (BlockBuffering $ Just 2048) $ \os -> do
            let l = "" : (intersperse " " ["the", "quick", "brown", "fox"])
            fromList l >>= connectTo os

        l <- liftM S.concat $ withFileAsInput (fn n) toList
        assertEqual "testFiles" "the quick brown fox" l

    tst1 = tst WriteMode 1
    tst2 = tst AppendMode 2
    tst3 = tst ReadWriteMode 3
    tst4 = expectExceptionH (tst ReadMode 4)
    tst5 = do
        withFileAsOutput (fn 5) $ \os -> do
            let l = "" : (intersperse " " ["the", "quick", "brown", "fox"])
            fromList l >>= connectTo os

        l <- liftM S.concat $ withFileAsInput (fn 5) toList
        assertEqual "testFiles" "the quick brown fox" l


------------------------------------------------------------------------------
testBigFiles :: Test
testBigFiles = testCase "file/bigFiles" $ do
    createDirectoryIfMissing False "tmp2"
    tst `finally` eatException (removeFile fn >> removeDirectory "tmp2")

  where
    fn = "tmp2" </> "data"

    testSz = 20 * 1024 * 1024

    tst = do
        let l = L.take testSz $ L.cycle $
                L.fromChunks (intersperse " " ["the", "quick", "brown", "fox"])

        withFileAsOutputExt fn WriteMode NoBuffering $ \os -> do
            fromList [S.concat $ L.toChunks l] >>= connectTo os

        l1 <- liftM L.fromChunks $ withFileAsInput fn toList
        assertBool "testFiles2" (l1 == l)

        l2 <- liftM L.fromChunks $ withFileAsInputStartingAt 5 fn toList
        assertBool "testFiles3" (l2 == (L.drop 5 l))

        (os, grab) <- copyingListOutputStream
        unsafeWithFileAsInputStartingAt 0 fn (connectTo os)

        l3 <- liftM L.fromChunks grab
        assertBool "testFiles4" (l3 == l)
