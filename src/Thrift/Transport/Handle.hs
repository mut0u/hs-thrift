{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
--
-- Licensed to the Apache Software Foundation (ASF) under one
-- or more contributor license agreements. See the NOTICE file
-- distributed with this work for additional information
-- regarding copyright ownership. The ASF licenses this file
-- to you under the Apache License, Version 2.0 (the
-- "License"); you may not use this file except in compliance
-- with the License. You may obtain a copy of the License at
--
--   http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing,
-- software distributed under the License is distributed on an
-- "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
-- KIND, either express or implied. See the License for the
-- specific language governing permissions and limitations
-- under the License.
--

module Thrift.Transport.Handle
    ( module Thrift.Transport
    , HandleSource(..)
    ) where

import Control.Exception ( catch, throw )
import Data.ByteString.Internal (c2w)
import Data.Functor

import Network.Socket

import System.IO
import System.IO.Error ( isEOFError )

import Thrift.Transport

import qualified Data.ByteString.Lazy as LBS
import Data.Monoid

instance Transport Handle where
    tIsOpen = hIsOpen
    tClose = hClose
    tRead h n = read `Control.Exception.catch` handleEOF mempty
      where
        read = do
          hLookAhead h
          LBS.hGetNonBlocking h n
    tReadAll _ 0 = return mempty
    tReadAll h n = LBS.hGet h n `Control.Exception.catch` throwTransportExn
    tPeek h = (Just . c2w <$> hLookAhead h) `Control.Exception.catch` handleEOF Nothing
    tWrite = LBS.hPut
    tFlush = hFlush


-- | Type class for all types that can open a Handle. This class is used to
-- replace tOpen in the Transport type class.
class HandleSource s where
    hOpen :: s -> IO Handle

instance HandleSource FilePath where
    hOpen s = openFile s ReadWriteMode

instance HandleSource (HostName, PortNumber) where
  hOpen (hostName, port) = do
    let hints = defaultHints { addrFlags = [AI_NUMERICHOST, AI_NUMERICSERV], addrSocketType = Stream }
    addr:_ <- getAddrInfo (Just hints) (Just hostName) (Just $ show port)
    sock <- socket (addrFamily addr) (addrSocketType addr) (addrProtocol addr)
    socketToHandle sock ReadWriteMode

throwTransportExn :: IOError -> IO a
throwTransportExn e = if isEOFError e
    then throw $ TransportExn "Cannot read. Remote side has closed." TE_UNKNOWN
    else throw $ TransportExn "Handle tReadAll: Could not read" TE_UNKNOWN

handleEOF :: a -> IOError -> IO a
handleEOF a e = if isEOFError e
    then return a
    else throw $ TransportExn "Handle: Could not read" TE_UNKNOWN
