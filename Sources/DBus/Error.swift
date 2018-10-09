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
    
    public init(name: String, message: String) {
        
        self.name = name
        self.message = message
    }
}

// MARK: - Internal

/// Internal class for working with the C DBus error API
internal final class DBusErrorInternal {
    
    typealias InternalPointer = UnsafeMutablePointer<CDBus.DBusError>
    
    // MARK: - Internal Properties
    
    let internalPointer: InternalPointer
    
    // MARK: - Initialization
    
    deinit {
        
        dbus_error_free(internalPointer)
    }
    
    /// Creates New DBus Error instance.
    init() {
        
        let internalPointer = InternalPointer()
        
        dbus_error_init(internalPointer)
        
        self.internalPointer = internalPointer
        
        assert(self.internalPointer != nil, "Could not create error. Out of memory?")
    }
    
    // MARK: - Properties
    
    /// Checks whether an error occurred (the error is set).
    ///
    /// -Returns: `true` if the error is empty or `false` if the error is set.
    var isEmpty: Bool {
        
        return !dbus_error_is_set(internalPointer).boolValue
    }
    
    // MARK: - DBusError Conversion
    
    func toError() -> DBusError? {
        
        guard isEmpty == false else { return nil }
        
        let name = String.fromCString(internalPointer.memory.name)!
        
        let message = String.fromCString(internalPointer.memory.message)!
        
        return DBusError(name: name, message: message)
    }
}
