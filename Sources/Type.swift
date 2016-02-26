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
    case Byte =     "y"
    
    /// Type code marking a boolean.
    case Boolean =  "b"
    
    /// Type code marking a 16-bit signed integer
    case Int16 =    "n"
    
    /// Type code marking a 16-bit unsigned integer. 
    case UInt16 =   "q"
    
    // TODO: Add all types
    
}

internal extension DBusType {
    
    var integerValue: CInt {
        
        let firstCharacter = self.rawValue.utf8.first!
        
        return CInt(firstCharacter)
    }
}