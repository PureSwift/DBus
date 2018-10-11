//
//  MessageArgument.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 2/26/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import CDBus

/// DBus Message argument value.
public indirect enum DBusMessageArgument {
    
    case byte(UInt8)
    case boolean(Bool)
    case int16(Swift.Int16)
    case uint16(Swift.UInt16)
    case int32(Swift.Int32)
    case uint32(Swift.UInt32)
    case int64(Swift.Int64)
    case uint64(Swift.UInt64)
    case double(Swift.Double)
    case string(Swift.String)
    case objectPath(Swift.String)
    case signature(Swift.String)
    case fileDescriptor(CInt)
    
    case array([DBusMessageArgument])
    case variant(DBusMessageArgument)
    //case Struct()
    case dictionaryEntry
}
