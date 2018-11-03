//
//  MessageArgument.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 2/26/16.
//  Copyright © 2016 Pure All rights reserved.
//

import CDBus

/// DBus Message argument value.
public enum DBusMessageArgument: Equatable {
    
    case byte(UInt8)
    case boolean(Bool)
    case int16(Int16)
    case uint16(UInt16)
    case int32(Int32)
    case uint32(UInt32)
    case int64(Int64)
    case uint64(UInt64)
    case double(Double)
    case fileDescriptor(CInt)
    
    case string(String)
    case objectPath(DBusObjectPath)
    case signature(DBusSignature)
    
    case array(Array)
    case variant
    
    //case `struct`
    //case dictionaryEntry
}

public extension DBusMessageArgument {
    
    public struct Array: Equatable {
        
        
    }
}
