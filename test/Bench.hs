{-# LANGUAGE BangPatterns #-}
-- | This module contains the benchmark test to compare the time
-- performance of the Naive, Native Haskell and CBLAS implementations of
-- the BLAS subroutines
module Main( main ) where

import qualified Data.Vector.Storable as V
import Test.QuickCheck.Gen
import Criterion.Main
import Control.DeepSeq
-- | This package
import Numerical.BLAS.Single
-- | This test suite
import Gen
import qualified Foreign as F

main :: IO ()
main = do
    -- GENERATE RANDOM DATA ON WHICH TO EVALUATE THE BENCHMARKS
    sx<- generate $ genNVector (genFloat genEveryday) nmax
    sy<- generate $ genNVector (genFloat genEveryday) nmax
    dx<- generate $ genNVector (genDouble genEveryday) nmax
    --dy<- generate $ genNVector (genDouble genEveryday) nmax
    sa<- generate $ genFloat genEveryday
    sb<- generate $ genFloat genEveryday
    sc<- generate $ genFloat genEveryday
    sd<- generate $ genFloat genEveryday
    da<- generate $ genDouble genEveryday
    db<- generate $ genDouble genEveryday
    -- DEFINE THE WRAPPER FUNCTIONS USED TO APPLY THE RANDOM VALUES
    let dotHelper  f x y !n !inc = f n x inc y inc
        normHelper f x !n !inc = f n x inc
        scalHelper f !a x !n !inc = f n a (trim n x inc) inc
        axpyHelper f !a x y !n !inc = f n a (trim n x inc) inc (trim n y inc) inc
        copyHelper f x y !n !inc = f n (trim n x inc) inc (trim n y inc) inc
        rotHelper f !a !b x y !n !inc = f n (trim n x inc) inc (trim n y inc) inc a b
        rotmHelper f !z x y !n !inc = f z n x inc y inc
        trim n x inc = V.unsafeTake (1+(n-1)*inc) x
        flags = srotmg sa sb sc sd
    -- RUN THE BENCHMARKS
    defaultMain [  bgroup "level-1" [
        vectorbench "sdot"   (dotHelper sdot sx sy)
                             (dotHelper F.sdot_unsafe sx sy)
                             (dotHelper F.sdot sx sy),
        vectorbench "sasum"  (normHelper sasum sx)
                             (normHelper F.sasum_unsafe sx)
                             (normHelper F.sasum sx),
        vectorbench "snrm2"  (normHelper snrm2 sx)
                             (normHelper F.snrm2_unsafe sx)
                             (normHelper F.snrm2 sx),
        vectorbench "isamax" (normHelper isamax sx)
                             (normHelper F.isamax_unsafe sx)
                             (normHelper F.isamax sx),
        vectorbench "dasum"  (normHelper dasum dx)
                             (normHelper F.dasum_unsafe dx)
                             (normHelper F.dasum dx),
        vectorbench "dnrm2"  (normHelper dnrm2 dx)
                             (normHelper F.dnrm2_unsafe dx)
                             (normHelper F.dnrm2 dx),
        vectorbench "idamax" (normHelper idamax dx)
                             (normHelper F.idamax_unsafe dx)
                             (normHelper F.idamax dx),
        vectorbench "sdsdot" (axpyHelper sdsdot sa sx sy)
                             (axpyHelper F.sdsdot_unsafe sa sx sy)
                             (axpyHelper F.sdsdot sa sx sy),
        vectorbench "saxpy"  (axpyHelper saxpy sa sx sy)
                             (axpyHelper F.saxpy_unsafe sa sx sy)
                             (axpyHelper F.saxpy sa sx sy),
        scalarbench2 "srotg" srotg F.srotg_unsafe F.srotg sa sb,
        scalarbench2 "drotg" drotg F.drotg_unsafe F.drotg da db,
        scalarbench4 "srotmg" srotmg F.srotmg_unsafe F.srotmg sa sb sc sd,
        vectorbench "sscal"  (scalHelper sscal sa sx)
                             (scalHelper F.sscal_unsafe sa sx)
                             (scalHelper F.sscal sa sx),
        vectorbench "scopy"  (copyHelper scopy sx sy)
                             (copyHelper F.scopy_unsafe sx sy)
                             (copyHelper F.scopy sx sy),
        vectorbench "sswap"  (copyHelper sswap sx sy)
                             (copyHelper F.sswap_unsafe sx sy)
                             (copyHelper F.sswap sx sy),
        vectorbench "srot"   (rotHelper srot sa sb sx sy)
                             (rotHelper F.srot_unsafe sa sb sx sy)
                             (rotHelper F.srot sa sb sx sy),
        vectorbench "srotm"  (rotmHelper srotm flags sx sy)
                             (rotmHelper F.srotm_unsafe flags sx sy)
                             (rotmHelper F.srotm flags sx sy)
        ]]
    where nmax = 32767

-- | benchmarks for blas functions
vectorbench :: (NFData a)
    => String                 -- the name of the test group
    -> ( Int -> Int -> a )    -- the pure version of the function
    -> ( Int -> Int -> IO a)  -- the unsafe foreign version of the function
    -> ( Int -> Int -> IO a)  -- the safe foreign version of the function
    -> Benchmark
vectorbench testname func unsafe safe = bgroup testname
  [ bgroup "stream"   [ benchPure func c | c <-cs]
  , bgroup "unsafe"   [ benchIO unsafe n inc | (n,inc)<-cs]
  , bgroup "safe"     [ benchIO safe n inc  | (n,inc)<-cs]
  ]
  where
  lengths = let zs = [1..9]++map (*10) zs in takeWhile (<32767) zs
  cs = [ (n,inc) | inc<-[1,10,100],n<-lengths,(n-1)*inc<32767]
  benchPure f c@(!n,!inc) = bench (showTestCase n inc) $ nf (uncurry f) c
  benchIO f !n !inc = bench (showTestCase n inc) $ nfIO $ f n inc
  showTestCase n inc = testname++"("++show n++","++show inc++")"

-- | benchmarks for blas functions that take two scalar arguments
scalarbench2 :: (NFData b)
    => String                 -- the name of the test group
    -> ( a -> a -> b )    -- the pure version of the function
    -> ( a -> a -> IO b)  -- the unsafe foreign version of the function
    -> ( a -> a -> IO b)  -- the safe foreign version of the function
    -> a
    -> a
    -> Benchmark
scalarbench2 testname func unsafe safe sa sb = bgroup testname
  [ bench "pure" $ nf (uncurry func) (sa,sb)
  , bench "unsafe" $ nfIO $ unsafe sa sb
  , bench "safe"   $ nfIO $ safe sa sb
  ]

-- | benchmarks for blas functions that take four scalar arguments
scalarbench4 :: (NFData b)
    => String                 -- the name of the test group
    -> ( a -> a -> a -> a -> b )    -- the pure version of the function
    -> ( a -> a -> a -> a -> IO b)  -- the unsafe foreign version of the function
    -> ( a -> a -> a -> a -> IO b)  -- the safe foreign version of the function
    -> a -> a -> a -> a
    -> Benchmark
scalarbench4 testname func unsafe safe sa sb sc sd = bgroup testname
  [ bench "pure" $ nf (\(a,b,c,d) -> func a b c d) (sa,sb,sc,sd)
  , bench "unsafe" $ nfIO $ unsafe sa sb sc sd
  , bench "safe"   $ nfIO $ safe sa sb sc sd
  ]
