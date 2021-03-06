--
-- SPDX-License-Identifier: BSD-2-Clause
--
-- Copyright (c) 2019 Peter Rugg
-- Copyright (c) 2020 Alexandre Joannou
-- All rights reserved.
--
-- This software was developed by SRI International and the University of
-- Cambridge Computer Laboratory (Department of Computer Science and
-- Technology) under DARPA contract HR0011-18-C-0016 ("ECATS"), as part of the
-- DARPA SSITH research programme.
--
-- Redistribution and use in source and binary forms, with or without
-- modification, are permitted provided that the following conditions
-- are met:
-- 1. Redistributions of source code must retain the above copyright
--    notice, this list of conditions and the following disclaimer.
-- 2. Redistributions in binary form must reproduce the above copyright
--    notice, this list of conditions and the following disclaimer in the
--    documentation and/or other materials provided with the distribution.
--
-- THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
-- ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
-- IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
-- ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
-- FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
-- DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
-- OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
-- HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
-- LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
-- OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
-- SUCH DAMAGE.
--

module QuickCheckVEngine.Templates.Utils.CHERI (
  randomCCall
, legalCapLoad
, legalCapStore
, switchEncodingMode
, cspecialRWChain
, tagCacheTest
, genCHERIinspection
, genCHERIarithmetic
, genCHERImisc
, genCHERIcontrol
) where

import Test.QuickCheck
import RISCV
import InstrCodec
import QuickCheckVEngine.Template
import QuickCheckVEngine.Templates.Utils.General

randomCCall :: Integer -> Integer -> Integer -> Integer -> Template
randomCCall pccReg idcReg typeReg tmpReg =
     Distribution [ (1, instSeq [ encode addi 0xffd 0 tmpReg
                                , encode candperm tmpReg pccReg pccReg ])
                  , (9, Empty) ] -- clear X perm?
  <> Distribution [ (9, instSeq [ encode addi 0xffd 0 tmpReg
                                , encode candperm tmpReg idcReg idcReg ])
                  , (1, Empty) ]
  <> Distribution [ (1, instSeq [ encode addi 0xeff 0 tmpReg
                                , encode candperm tmpReg pccReg pccReg ])
                  , (9, Empty) ] -- clear CCall perm?
  <> Distribution [ (1, instSeq [ encode addi 0xeff 0 tmpReg
                                , encode candperm tmpReg idcReg idcReg ])
                  , (9, Empty) ]
  <> Distribution [ (9, Single $ encode cseal typeReg pccReg pccReg)
                  , (1, Empty) ] -- seal?
  <> Distribution [ (9, Single $ encode cseal typeReg idcReg idcReg)
                  , (1, Empty) ]
  <> instSeq [ encode ccall idcReg pccReg
             , encode cmove 31 1 ]

legalCapLoad :: Integer -> Integer -> Template
legalCapLoad addrReg targetReg = Random $ do
  tmpReg <- src
  return $ instSeq [ encode andi 0xff addrReg addrReg
                   , encode lui 0x40004 tmpReg
                   , encode slli 1 tmpReg tmpReg
                   , encode add addrReg tmpReg addrReg
                   , encode cload 0x17 addrReg targetReg ]

legalCapStore :: Integer -> Template
legalCapStore addrReg = Random $ do
  tmpReg  <- src
  dataReg <- dest
  return $ instSeq [ encode andi 0xff addrReg addrReg
                   , encode lui 0x40004 tmpReg
                   , encode slli 1 tmpReg tmpReg
                   , encode add addrReg tmpReg addrReg
                   , encode cstore dataReg addrReg 0x4 ]

switchEncodingMode :: Template
switchEncodingMode = Random $ do
  tmpReg1 <- src
  tmpReg2 <- src
  mode    <- elements [0, 1]
  return $ instSeq [ encode cspecialrw 0 0 tmpReg1
                   , encode addi mode 0 tmpReg2
                   , encode csetflags tmpReg2 tmpReg1 tmpReg1
                   , encode cspecialrw 28 tmpReg1 0 --Also write trap vector so we stay in cap mode
                   , encode cjalr tmpReg1 0 ]

cspecialRWChain :: Template
cspecialRWChain = Random $ do
  tmpReg1 <- src
  tmpReg2 <- src
  tmpReg3 <- src
  tmpReg4 <- src
  tmpReg5 <- src
  tmpReg6 <- src
  return $ instSeq [ encode cspecialrw 30 tmpReg1 tmpReg2
                   , encode cjalr      tmpReg2 0
                   , encode cspecialrw 30 tmpReg3 tmpReg4
                   , encode cspecialrw 30 tmpReg5 tmpReg6 ]

tagCacheTest :: Template
tagCacheTest = Random $ do
  addrReg   <- src
  targetReg <- dest
  return $     legalCapStore addrReg
            <> legalCapLoad addrReg targetReg
            <> Single (encode cgettag targetReg targetReg)

genCHERIinspection :: Template
genCHERIinspection = Random $ do
  srcAddr  <- src
  srcData  <- src
  dest     <- dest
  imm      <- bits 12
  longImm  <- bits 20
  fenceOp1 <- bits 3
  fenceOp2 <- bits 3
  csrAddr  <- frequency [ (1, return 0xbc0), (1, return 0x342), (1, bits 12) ]
  return $ Distribution [ (1, uniformTemplate $ rv32_xcheri_inspection srcAddr dest)
                        , (1, uniformTemplate $ rv32_i srcAddr srcData dest imm longImm fenceOp1 fenceOp2) ] -- TODO add csr

genCHERIarithmetic :: Template
genCHERIarithmetic = Random $ do
  srcAddr  <- src
  srcData  <- src
  dest     <- dest
  imm      <- bits 12
  longImm  <- bits 20
  fenceOp1 <- bits 3
  fenceOp2 <- bits 3
  csrAddr  <- frequency [ (1, return 0xbc0), (1, return 0x342), (1, bits 12) ]
  return $ Distribution [ (1, uniformTemplate $ rv32_xcheri_arithmetic srcAddr srcData imm dest)
                        , (1, uniformTemplate $ rv32_i srcAddr srcData dest imm longImm fenceOp1 fenceOp2) ] -- TODO add csr

genCHERImisc :: Template
genCHERImisc = Random $ do
  srcAddr  <- src
  srcData  <- src
  dest     <- dest
  imm      <- bits 12
  longImm  <- bits 20
  fenceOp1 <- bits 3
  fenceOp2 <- bits 3
  srcScr   <- elements [0, 1, 28, 29, 30, 31]
  csrAddr  <- frequency [ (1, return 0xbc0), (1, return 0x342), (1, bits 12) ]
  return $ Distribution [ (1, uniformTemplate $ rv32_xcheri_misc srcAddr srcData srcScr imm dest)
                        , (1, uniformTemplate $ rv32_i srcAddr srcData dest imm longImm fenceOp1 fenceOp2) ] -- TODO add csr

genCHERIcontrol :: Template
genCHERIcontrol = Random $ do
  srcAddr  <- src
  srcData  <- src
  dest     <- dest
  imm      <- bits 12
  longImm  <- bits 20
  fenceOp1 <- bits 3
  fenceOp2 <- bits 3
  csrAddr  <- frequency [ (1, return 0xbc0), (1, return 0x342), (1, bits 12) ]
  return $ Distribution [ (1, uniformTemplate $ rv32_xcheri_control srcAddr srcData dest)
                        , (1, uniformTemplate $ rv32_i srcAddr srcData dest imm longImm fenceOp1 fenceOp2) ] -- TODO add csr
