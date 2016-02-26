//
//  Error.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 2/25/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import CDBus

/// DBus type representing an exception.
public struct DBusError: ErrorType {
    
    /// Error name field
    public var name: String
    
    /// Error message field
    public var message: String
}

internal extension DBusError {
    
    typealias InternalPointer = UnsafeMutablePointer<CDBus.DBusError>
    
    /// Creates a DBusError from its C pointer and frees the pointer.
    init(internalPointer: DBusError.InternalPointer, freePointer: Bool = true) {
        
        assert(internalPointer != nil, "Nil error pointer")
        
        defer { if freePointer { dbus_error_free(internalPointer) } }
        
        self.name = String.fromCString(internalPointer.memory.name)!
                
        self.message = String.fromCString(internalPointer.memory.message)!
    }
}
