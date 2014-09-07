{-# LANGUAGE OverloadedStrings #-}

module Main where 

import Test.Tasty
import Test.Tasty.HUnit

import Data.Bifunctor
import Data.Monoid
import Data.ByteString.Lazy as BL
import Data.Text.Lazy as TL
import qualified Data.Attoparsec.Text as A
import Control.Applicative
import Control.Monad
import Control.Lens (view)
import Control.Concurrent.Async
import Pipes
import qualified Pipes.ByteString as B
import qualified Pipes.Prelude as P
import qualified Pipes.Parse as P
import qualified Pipes.Attoparsec as P
import qualified Pipes.Text as T
import qualified Pipes.Text.Encoding as T
import qualified Pipes.Text.IO as T
import qualified Pipes.Group as G
import qualified Pipes.Safe as S
import qualified Pipes.Safe.Prelude as S
import System.IO
import System.IO.Error
import System.Exit
import System.Process.Streaming

main = defaultMain tests

tests :: TestTree
tests = testGroup "Tests" 
            [ testCollectStdoutStderrAsByteString
            , testFeedStdinCollectStdoutAsText  
            , testBasicPipeline
            ]

-------------------------------------------------------------------------------
testCollectStdoutStderrAsByteString :: TestTree
testCollectStdoutStderrAsByteString = testCase "collectStdoutStderrAsByteString" $ do
    r <- collectStdoutStderrAsByteString
    case r of
        (ExitSuccess,("ooo\nppp\n","eee\nffff\n")) -> return ()
        _ -> assertFailure "oops"

collectStdoutStderrAsByteString :: IO (ExitCode,(BL.ByteString,BL.ByteString))
collectStdoutStderrAsByteString = execute
    (pipeoe (fromFold B.toLazyM) (fromFold B.toLazyM))
    (shell "{ echo ooo ; echo eee 1>&2 ; echo ppp ;  echo ffff 1>&2 ; }")


-------------------------------------------------------------------------------
testFeedStdinCollectStdoutAsText  :: TestTree
testFeedStdinCollectStdoutAsText = testCase "feedStdinCollectStdoutAsText" $ do
    r <- feedStdinCollectStdoutAsText
    case r of
        (ExitSuccess,((),"aaaaaa\naaaaa")) -> return ()
        _ -> assertFailure "oops"

feedStdinCollectStdoutAsText :: IO (ExitCode, ((), Text))
feedStdinCollectStdoutAsText = execute
    (pipeio (fromProducer $ yield "aaaaaa\naaaaa")
            (encoded T.decodeIso8859_1 (pure id) $ fromFold T.toLazyM))
    (shell "cat")

-------------------------------------------------------------------------------
testBasicPipeline :: TestTree
testBasicPipeline = testCase "basicPipeline" $ do
    r <- basicPipeline 
    case r of 
        Right ((),"aaaccc\n") -> return ()                   
        _ -> assertFailure "oops"

basicPipeline :: IO (Either String ((),BL.ByteString))
basicPipeline =  executePipelineFallibly (pipeio (fromProducer $ yield "aaabbb\naaaccc\nxxxccc") (fromFold B.toLazyM)) pip
  where 
    pip = verySimplePipeline T.decodeUtf8 (shell "grep aaa") [] (shell "grep ccc")

-------------------------------------------------------------------------------





