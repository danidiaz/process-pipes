
-- |
--
-----------------------------------------------------------------------------


module System.Process.Streaming.Tutorial ( 
    -- * Introduction
    -- $introduction
  
    -- * stdin and stderr to different files
    -- $stdinstderr
    
    -- * Missing executable
    -- $missingexec

    -- * Combining stdout and stderr
    -- $combinelines

    -- * Running parsers in parallel 
    -- $forkProd
    
    -- * Aborting an execution
    -- $fastExit

    -- * Feeding stdin, collecting stdout
    -- $cat

    -- * Ghci
    -- $ghci
    ) where

{- $introduction 
These examples require the @OverloadedStrings@ extension. 

Some preliminary imports: 

> module Main where
> 
> import Data.Bifunctor
> import Data.Either
> import Data.Monoid
> import Data.Text.Lazy as L
> import Data.Text.Lazy.Builder as L
> import qualified Data.Attoparsec.Text as A
> import Control.Applicative
> import Control.Monad
> import Control.Monad.Writer.Strict
> import Control.Concurrent (threadDelay)
> import Pipes
> import Pipes.ByteString
> import qualified Pipes.Prelude as P
> import qualified Pipes.Parse as P
> import qualified Pipes.Attoparsec as P
> import qualified Pipes.Text as T
> import qualified Pipes.Text.Encoding as T
> import qualified Pipes.Text.IO as T
> import qualified Pipes.Safe as S
> import qualified Pipes.Safe.Prelude as S
> import System.IO
> import System.Process
> import System.Process.Streaming

-}


{- $stdinstderr
 
Using 'separate' to consume @stdout@ and @stderr@ concurrently, and functions
from @pipes-safe@ to write the files.

> example1 :: IO (Either String ((),()))
> example1 = exitCode show $
>     execute program show $ separate 
>         (consume "stdout.log")
>         (consume "stderr.log")
>     where
>     consume file = surely . safely . useConsumer $
>         S.withFile file WriteMode toHandle
>     program = shell "{ echo ooo ; echo eee 1>&2 ; }"
-}


{- $missingexec
 
Missing executables and other 'IOException's are converted to an error type @e@
and returned in the 'Left' of an 'Either':

> example2 :: IO (Either String ((),()))
> example2 = exitCode show $ 
>     execute (proc "fsdfsdf" []) show $ separate 
>         nop
>         nop 

Returns:

>>> Left "fsdfsdf: createProcess: runInteractiveProcess: exec: does not exist (No such file or directory)"

-}


{- $combinelines
 
Here we use 'combineLines' to process 'stdout' and 'stderr' together.

Notice that they are consumed together as 'Text'. We have to specify a decoding
function for each stream, and a 'LeftoverPolicy' as well.

We also add a prefix to the lines coming from @stderr@.

> example3 :: IO (Either String ())
> example3 = exitCode show $ 
>    execute program show $ combineLines
>        (linePolicy T.decodeIso8859_1 id policy)
>        (linePolicy T.decodeIso8859_1 annotate policy)
>        (surely . safely . useConsumer $ 
>            S.withFile "combined.txt" WriteMode T.toHandle)
>     where
>     policy = failOnLeftovers $ \_ _->"badbytes"
>     annotate x = P.yield "errprefix: " *> x
>     program = shell "{ echo ooo ; echo eee 1>&2 ; echo ppp ;  echo ffff 1>&2 ;}"

-}


{- $forkProd

Plugging parsers from @pipes-parse@ into 'separate' or 'combineLines' is easy
because running 'evalStateT' on a parser returns a function that consumes a
'Producer'.

In this example we define two Attoparsec Text parsers and we convert them to
Pipes parsers using function 'parse' from package @pipes-attoparsec@. 

Stdout is decoded to Text and parsed by the two parsers in parallel using the
auxiliary 'forkProd' function. The results are aggregated in a tuple.

Stderr is ignored using the 'nop' function.

> parseChars :: Char -> A.Parser [Char] 
> parseChars c = fmap mconcat $ 
>     many (A.notChar c) *> A.many1 (some (A.char c) <* many (A.notChar c))
> 
> parser1 = parseChars 'o'
> parser2 = parseChars 'a'
> 
> example4 ::IO (Either String (([Char], [Char]),()))
> example4 = exitCode show $ 
>     execute program show $ separate
>         (encoding T.decodeIso8859_1 (failOnLeftovers $ \_ _->"badbytes") $  
>             forkProd (P.evalStateT $ adapt parser1)
>                      (P.evalStateT $ adapt parser2))
>         nop 
>     where
>     adapt p = bimap (const "parse error") id <$> P.parse p
>     program = shell "{ echo ooaaoo ; echo aaooaoa; }"

Returns:

>>> Right (("ooooooo","aaaaaa"),())

-}


{- $fastExit

If any function consuming a standard stream returns with an error value @e@,
the external program is terminated and the computation returns immediately with
@e@.

> example5 ::IO (Either String ((),()))
> example5 = exitCode show $  
>     execute (shell "sleep 10s") show $ separate
>             (\_ -> return $ Left "fast return!")
>             nop

Returns:

>>> Left "fast return!"

If we change the stdout consuming function to 'nop', 'example5' waits 10
seconds. 
-}


{- $cat

In this example we invoke the @cat@ command, feeding its input stream with a
'ByteString'.

We decode stdout to Text and collect the whole output using a fold from
'Pipes.Prelude'. 

Plugging folds from "Pipes.Prelude" into 'separate' or 'combineLines' is easy
because the folds return functions that consumes 'Producer's. The folds form
the @foldl@ package could also be useful. 

Notice that @stdin@ is written concurrently with the reading of @stdout@. It is
not the case that @sdtin@ is written first and then @stdout@ is read. 

> example6 = exitCode show $  
>     execute3 (shell "cat") show  
>         (surely . useProducer $ yield "aaaaaa\naaaaa")
>         (separate 
>             (encoding T.decodeIso8859_1 ignoreLeftovers . surely $ foldy)  
>             nop
>         )
>     where foldy :: Producer T.Text IO () -> IO L.Text 
>           foldy = P.fold (<>) mempty L.toLazyText . (>->P.map L.fromText)

Returns:

>>> Right ((),("aaaaaa\naaaaa",()))

-}

{- $gchi

Sometimes it's useful to launch external programs during a ghci session, like
this:

>>> a <- async $ execute (proc "xeyes" []) show $ separate nop nop

Cancelling the async causes the termination of the external program:

>>> cancel a

Waiting for the async returns the result:

>>> wait a

-}