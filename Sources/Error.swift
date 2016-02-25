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
    
    init(internalPointer: DBusError.InternalPointer) {
        
        assert(internalPointer != nil, "Nil error pointer")
        
        
    }
}
