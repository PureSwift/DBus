//
//  Type.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 2/25/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

/// DBus Type
public enum DBusType: String {
    
    /// Type code marking an 8-bit unsigned integer.
    case Byte               = "y"
    
    /// Type code marking a boolean.
    case Boolean            = "b"
    
    /// Type code marking a 16-bit signed integer
    case Int16              = "n"
    
    /// Type code marking a 16-bit unsigned integer. 
    case UInt16             = "q"
    
    case Int32              = "i"
    
    case UInt32             = "u"
    
    case Int64              = "x"
    
    case UInt64             = "t"
    
    case Double             = "d"
    
    case String             = "s"
    
    case ObjectPath         = "o"
    
    case Signature          = "g"
    
    case FileDescriptor     = "h"
    
    case Array              = "a"
    
    case Variant            = "v"
    
    case Struct             = "r"
    
    case DictionaryEntry    = "e"
}

internal extension DBusType {
    
    var integerValue: CInt {
        
        let firstCharacter = self.rawValue.utf8.first!
        
        return CInt(firstCharacter)
    }
}