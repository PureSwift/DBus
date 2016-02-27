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
    
    case Byte(UInt8)
    case Boolean(Bool)
    case Int16(Swift.Int16)
    case UInt16(Swift.UInt16)
    case Int32(Swift.Int32)
    case UInt32(Swift.UInt32)
    case Int64(Swift.Int64)
    case UInt64(Swift.UInt64)
    case Double(Swift.Double)
    case String(Swift.String)
    case ObjectPath(Swift.String)
    case Signature(Swift.String)
    case FileDescriptor(CInt)
    
    case Array([DBusMessageArgument])
    case Variant(DBusMessageArgument)
    //case Struct()
    case DictionaryEntry
}