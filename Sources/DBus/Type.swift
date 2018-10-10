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
    case byte               = "y"
    
    /// Type code marking a boolean.
    case boolean            = "b"
    
    /// Type code marking a 16-bit signed integer
    case int16              = "n"
    
    /// Type code marking a 16-bit unsigned integer. 
    case uint16             = "q"
    
    case int32              = "i"
    
    case uint32             = "u"
    
    case int64              = "x"
    
    case uint64             = "t"
    
    case double             = "d"
    
    case string             = "s"
    
    case objectPath         = "o"
    
    case signature          = "g"
    
    case fileDescriptor     = "h"
    
    case array              = "a"
    
    case variant            = "v"
    
    case `struct`           = "r"
    
    case dictionaryEntry    = "e"
}

internal extension DBusType {
    
    var integerValue: CInt {
        
        let firstCharacter = self.rawValue.utf8.first!
        
        return CInt(firstCharacter)
    }
}
