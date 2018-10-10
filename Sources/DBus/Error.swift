//
//  Error.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 2/25/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import CDBus

/// DBus type representing an exception.
public struct DBusError: Error {
    
    /// Error name field
    public var name: String
    
    /// Error message field
    public var message: String
    
    public init(name: String,
                message: String) {
        
        self.name = name
        self.message = message
    }
}

// MARK: - Internal

internal extension DBusError {
    
    /// Internal class for working with the C DBus error API
    internal final class Reference {
        
        typealias InternalPointer = UnsafeMutablePointer<CDBus.DBusError>
        
        // MARK: - Internal Properties
        
        let internalPointer: InternalPointer
        
        // MARK: - Initialization
        
        deinit {
            
            dbus_error_free(internalPointer)
        }
        
        /// Creates New DBus Error instance.
        init() {
            
            let internalPointer: InternalPointer! = nil
            dbus_error_init(internalPointer)
            
            self.internalPointer = internalPointer
        }
        
        // MARK: - Properties
        
        /// Checks whether an error occurred (the error is set).
        ///
        /// - Returns: `true` if the error is empty or `false` if the error is set.
        var isEmpty: Bool {
            
            return Bool(dbus_error_is_set(internalPointer))
        }
        
        var name: String {
            
            return String(cString: internalPointer.pointee.name)
        }
        
        var message: String {
            
            return String(cString: internalPointer.pointee.message)
        }
    }
}

internal extension DBusError {
    
    init?(_ reference: DBusError.Reference) {
        
        guard reference.isEmpty == false
            else { return nil }
        
        self.init(name: reference.name, message: reference.message)
    }
}
