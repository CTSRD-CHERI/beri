--
-- Copyright (c) 2012 SRI International
-- All rights reserved.
--
-- This software was developed by SRI International and the University of
-- Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
-- ("CTSRD"), as part of the DARPA CRASH research programme.
--
-- @BERI_LICENSE_HEADER_START@
--
-- Licensed to BERI Open Systems C.I.C. (BERI) under one or more contributor
-- license agreements.  See the NOTICE file distributed with this work for
-- additional information regarding copyright ownership.  BERI licenses this
-- file to you under the BERI Hardware-Software License, Version 1.0 (the
-- "License"); you may not use this file except in compliance with the
-- License.  You may obtain a copy of the License at:
--
--   http://www.beri-open-systems.org/legal/license-1-0.txt
--
-- Unless required by applicable law or agreed to in writing, Work distributed
-- under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
-- CONDITIONS OF ANY KIND, either express or implied.  See the License for the
-- specific language governing permissions and limitations under the License.
--
-- @BERI_LICENSE_HEADER_END@
--

module CheriCTL where

import System.Process
import System.Exit
import Data.Map as M
import Data.Char
import Control.Monad.State.Strict
import Control.Monad.Identity
import Control.Monad.Trans.Error
import Numeric(showHex)
import System.Posix.Unistd

--import Data.Maybe

import Text.Parsec as P
import Text.Parsec.Token as PT
import Text.Parsec.Language
-- import Text.ParserCombinators.Parsec
-- import Text.ParserCombinators.Parsec.Expr
-- import qualified Text.ParserCombinators.Parsec.Token as P

-- import Text.ParserCombinators.Parsec.Prim

type Addr = Integer

type Parser a = ParsecT Char () Identity a 

pstyle = haskellStyle{
              identStart  = letter   <|> oneOf "_-'"
            , identLetter = alphaNum <|> oneOf "_-'$"}
pparse = PT.makeTokenParser pstyle

number bitsToDigit base baseDigit = do
  digits <- many baseDigit
  let n = Prelude.foldl (\x d -> base*x + toInteger (digitToInt d)) 0 digits
  seq n $ return (bitsToDigit * length digits, n)      

pRegValue = do
  num <- PT.brackets pparse $ PT.integer pparse
  str <- many1 (noneOf ":")
  string ": " 
  string "0"  
  (l,b) <- (string "b" >> number 1 2  (oneOf "01")) <|>
           (string "x" >> number 4 16 hexDigit    )
  string "\n"
  return (num, (str, b))    

----------------------------------------------------------------------------------------  
  
type TestIO a = ErrorT String IO a

runTestIO :: TestIO a -> IO (Either String a)
runTestIO tmx = runErrorT tmx


----------------------------------------------------------------------------------------  

breakpoint :: Addr -> TestIO ()
breakpoint a = do
  (ec,s1,s2) <- lift $ readProcessWithExitCode "./cherictl" ["breakpoint", "-a", showHex a ""] ""
  when (ec /= ExitSuccess) (throwError $ "BreakPoint Fail" ++ show s1)

-- console
  
c0regs :: TestIO (M.Map Integer (String, Integer))
c0regs = do 
  (ec,s1,s2) <- lift $ readProcessWithExitCode "./cherictl" ["c0regs"] ""  
  let pC0RegValues = do
        string $ "======   CP0 Registers   ======\n" 
        -- ++ "cherictl: CPU paused at " number 4 16 hexDigit >> string "\n"
        many1 pRegValue
      parseC0Regs ::  String -> M.Map Integer (String, Integer)
      parseC0Regs s = case (runIdentity $ runPT (pC0RegValues) () "c0Regs" s) of
                        (Left err) -> error $ "can't parse c0regs:\n" ++ show err ++ "\n" ++ s
                        (Right rv) -> M.fromList rv
  if (ec == ExitSuccess) then return (parseC0Regs s1) else (throwError $ "c0Regs misParse: " ++ show (s1, s2))

lbu :: Addr -> TestIO Integer
lbu a = do
  (ec,s1,s2) <- lift $ readProcessWithExitCode "./cherictl" ["lbu", "-a", showHex a ""] ""  
  let pLBU = do 
        string "Attempting to lbu from 0x" >> many hexDigit >> string "\n"
        many hexDigit >> string " = " >> string "0x"
        (l, b) <- number 4 16 hexDigit  
        return b
  case (ec == ExitSuccess, runIdentity $ runPT (pLBU) () "LBU" s1) of
    (True, Right rv) -> return rv
    (True, Left err) -> throwError $ "can't parse LBU:\n" ++ show err ++ "\n" ++ s1
    (_             ) -> throwError $ "can't parse LBU:\n" ++ s1

ld :: Addr -> TestIO Integer
ld a = do
  (ec,s1,s2) <- lift $ readProcessWithExitCode "./cherictl" ["ld", "-a", showHex a ""] ""  
  let pLD = do 
        string "Attempting to ld from 0x" >> many hexDigit >> string "\n"
        many hexDigit >> string " = " >> string "0x"
        (l, b) <- number 4 16 hexDigit  
        return b
  case (ec == ExitSuccess, runIdentity $ runPT (pLD) () "LD" s1) of
    (True, Right rv) -> return rv
    (True, Left err) -> throwError $ "can't parse LD:\n" ++ show err ++ "\n" ++ s1
    (_             ) -> throwError $ "can't parse LD:\n" ++ s1  
  
pause :: TestIO () -- XXX where is it paused?
pause = do
  (ec,s1,s2) <- lift $ readProcessWithExitCode "./cherictl" ["pause"] ""    
  when (ec /= ExitSuccess) (throwError $ "Pause Failed: " ++ s1)
    
pc :: TestIO Integer
pc = do
  (ec,s1,s2) <- lift $ readProcessWithExitCode "./cherictl" ["pc"] ""    
  let pPC = do 
        string "DEBUG MIPS PC 0x"
        (l, b) <- number 4 16 hexDigit
        return b
  case (ec == ExitSuccess, runIdentity $ runPT (pPC) () "PC" s1) of
    (True, Right rv) -> return $ rv 
    (True, Left err) -> throwError $ "can't parse PC:\n" ++ show err ++ "\n" ++ s1
    (_             ) -> throwError $ "can't parse PC:\n" ++ s1

regs :: TestIO (M.Map Integer Integer)
regs = do 
  (ec,s1,s2) <- lift $ readProcessWithExitCode "./cherictl" ["regs"] ""  
  let pRegValues = do
        string $ "======   RegFile   ======\n"
        many1 (noneOf "\n") >> string "\n"      
        many1 pReg
      pReg = do
        string "DEBUG MIPS REG "
        n <- PT.integer pparse
        many (oneOf " ") >> string "0x"
        (l,b) <- number 4 16 hexDigit
        string "\n"
        return (n,b)
      parseRegs ::  String -> TestIO (M.Map Integer Integer)
      parseRegs s = case (runIdentity $ runPT (pRegValues) () "regs" s) of
                        (Left err) -> throwError ("can't parse regs:\n" ++ show err ++ "\n" ++ s)
                        (Right rv) -> return $ M.fromList rv
  if ec == ExitSuccess then parseRegs s1 else throwError ("Regs Error: " ++ show s1)

c2regs :: TestIO (M.Map Integer Integer)
c2regs = do 
  (ec,s1,s2) <- lift $ readProcessWithExitCode "./cherictl" ["regs"] ""  
  let pRegValues = do
        string $ "======   RegFile   ======\n"
        many1 (noneOf "\n") >> string "\n"      
        many1 pReg
      pReg = do
        string "DEBUG MIPS REG "
        n <- PT.integer pparse
        many (oneOf " ") >> string "0x"
        (l,b) <- number 4 16 hexDigit
        string "\n"
        return (n,b)
      parseRegs ::  String -> TestIO (M.Map Integer Integer)
      parseRegs s = case (runIdentity $ runPT (pRegValues) () "regs" s) of
                        (Left err) -> throwError $ "can't parse regs:\n" ++ show err ++ "\n" ++ s
                        (Right rv) -> return $  M.fromList rv
  if ec == ExitSuccess then (parseRegs s1) else throwError ("C0Regs Error: " ++ show s1)

  
resume :: TestIO ()
resume = do
  (ec,s1,s2) <- lift $ readProcessWithExitCode "./cherictl" ["resume"] ""    
  when (ec /= ExitSuccess) (throwError $ "Resume Error" ++ show (s1, s2))
    
sb :: Addr -> Int -> TestIO ()
sb a v = do
  (ec,s1,s2) <- lift $ readProcessWithExitCode "./cherictl" ["sb", "-a", showHex a "", "-v", showHex v ""] ""    
  when (ec /= ExitSuccess) (throwError $ "SB Error: " ++ show (s1, s2))  

sd :: Addr -> Int -> TestIO ()
sd a v = do  
  (ec,s1,s2) <- lift $ readProcessWithExitCode "./cherictl" ["sd", "-a", showHex a "", "-v", showHex v ""] ""    
  when (ec /= ExitSuccess) (throwError $ "SD Error: " ++ show (s1, s2))    

setpc :: Addr -> TestIO ()
setpc a = do
  (ec,s1,s2) <- lift $ readProcessWithExitCode "./cherictl" ["setpc", "-a", showHex (a-4) ""] ""    
  when (ec /= ExitSuccess) (throwError $ "SetPC Error: " ++ show (s1, s2))      


setreg :: Int -> Integer -> TestIO ()
setreg rn v = do
  (ec,s1,s2) <- lift $ readProcessWithExitCode "./cherictl" ["setreg", "-r", showHex rn "", "-v", showHex v ""] ""    
  when (ec /= ExitSuccess) (throwError $ "SetReg Error: " ++ show (s1, s2))  

step :: TestIO ()
step = do
  (ec,s1,s2) <- lift $ readProcessWithExitCode "./cherictl" ["step"] ""    
  when (ec /= ExitSuccess) (throwError $ "Step Error: " ++ show (s1, s2))  

unpipeline :: TestIO ()
unpipeline = do
  (ec,s1,s2) <- lift $ readProcessWithExitCode "./cherictl" ["unpipeline"] ""    
  when (ec /= ExitSuccess) (throwError $ "Unpipeline Error: " ++ show (s1, s2))    

loadhex :: Addr -> String -> TestIO ()
loadhex pc filename = do
  (ec,s1,s2) <- lift $ readProcessWithExitCode "./cherictl" ["loadhex", "-a", showHex pc "", "-f", filename] ""      
  when (ec /= ExitSuccess) (throwError $ "loadhex Error: " ++ show (s1, s2))    

runCompareTest :: String -> TestIO Bool
runCompareTest filename = do
  pause
  loadhex 0x9000000040000000 filename
  resume
  lift $ sleep 5 -- XXX random wait time  
  pause
  regsA   <- regs
  c0regsA <- c0regs  
  pause
  loadhex 0x9000000040000000 filename
  resume
  pause
  regsB   <- regs
  c0regsB <- c0regs
  -- check equivalences
  let mismatchedRegs   =  regsA   \\   regsB
      mismatchedC0Regs =  c0regsA \\ c0regsB
  when (mismatchedRegs /= M.empty) $
     lift $ putStrLn ( "Registers don't match between pipelined and unpipelined cases -- \n" 
                ++ "  pipelined: " ++ (show regsA) ++ "\n"
                ++ "unpipelined: " ++ (show regsB) ++ "\n")
  when (mismatchedC0Regs /= M.empty) $
     lift $ putStrLn ( "C0Registers don't match between pipelined and unpipelined cases -- \n"
                ++ "  pipelined: " ++ (show c0regsA) ++ "\n"
                ++ "unpipelined: " ++ (show c0regsB) ++ "\n")
  return $ (mismatchedRegs == M.empty) && (mismatchedC0Regs == M.empty)

runOnNewSim :: TestIO a -> IO (Either String a)
runOnNewSim query = do
  (hin, hout, herr, hCheri) <- runInteractiveProcess "./sim" [] Nothing Nothing
  a <- runTestIO query
  terminateProcess hCheri
  return a
