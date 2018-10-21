//
//  MessageArgument.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 2/26/16.
//  Copyright © 2016 Pure All rights reserved.
//

import CDBus

/// DBus Message argument value.
public indirect enum DBusMessageArgument {
    
    case byte(UInt8)
    case boolean(Bool)
    case int16(Int16)
    case uint16(UInt16)
    case int32(Int32)
    case uint32(UInt32)
    case int64(Int64)
    case uint64(UInt64)
    case double(Double)
    case string(String)
    case objectPath(String)
    case signature(String)
    case fileDescriptor(CInt)
    
    case array([DBusMessageArgument])
    case variant(DBusMessageArgument)
    
    //case Struct()
    case dictionaryEntry
}
