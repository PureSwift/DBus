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
    public var name: DBusError.Name
    
    /// Error message field
    public var message: String
    
    public init(name: DBusError.Name,
                message: String) {
        
        self.name = name
        self.message = message
    }
}

public extension DBusError {
    
    public struct Name: RawRepresentable {
        
        public let rawValue: String
        
        public init(rawValue: String) {
            
            self.rawValue = rawValue
        }
    }
}

public extension DBusError.Name {
    
    /// A generic error; "something went wrong" - see the error message for more.
    public static let failed: DBusError.Name = "org.freedesktop.DBus.Error.Failed"
    
    /// Existing file and the operation you're using does not silently overwrite.
    public static let fileExists: DBusError.Name = "org.freedesktop.DBus.Error.FileExists"
    
    /// Missing file.
    public static let fileNotFound: DBusError.Name = "org.freedesktop.DBus.Error.FileNotFound"
}

extension DBusError.Name: ExpressibleByStringLiteral {
    
    public init(stringLiteral value: String) {
        
        self.init(rawValue: value)
    }
}

extension DBusError.Name: CustomStringConvertible {
    
    public var description: String {
        
        return rawValue
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
        
        self.init(name: DBusError.Name(rawValue: reference.name),
                  message: reference.message)
    }
}
