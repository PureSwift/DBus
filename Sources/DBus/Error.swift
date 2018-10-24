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
    public let name: DBusError.Name
    
    /// Error message field
    public let message: String
}

// MARK: - Internal

internal extension DBusError {
    
    /// Internal class for working with the C DBus error API
    internal final class Reference {
        
        // MARK: - Internal Properties
        
        internal var internalValue: CDBus.DBusError
        
        // MARK: - Initialization
        
        deinit {
            
            dbus_error_free(&internalValue)
        }
        
        /// Creates New DBus Error instance.
        init() {
            
            var internalValue = CDBus.DBusError()
            dbus_error_init(&internalValue)
            self.internalValue = internalValue
        }
        
        // MARK: - Properties
        
        /// Checks whether an error occurred (the error is set).
        ///
        /// - Returns: `true` if the error is empty or `false` if the error is set.
        var isEmpty: Bool {
            
            return Bool(dbus_error_is_set(&internalValue)) == false
        }
        
        var name: String {
            
            return String(cString: internalValue.name)
        }
        
        var message: String {
            
            return String(cString: internalValue.message)
        }
    }
}

internal extension DBusError {
    
    init?(_ reference: DBusError.Reference) {
        
        guard reference.isEmpty == false
            else { return nil }
        
        guard let name = DBusError.Name(rawValue: reference.name)
            else { fatalError("Invalid error \(reference.name)") }
        
        self.init(name: name,
                  message: reference.message)
    }
}

// MARK: Error Name

public extension DBusError {
    
    public struct Name {
        
        public let rawValue: String
        
        /// Cached parsed interface
        internal let interface: DBusInterface
        
        public init?(rawValue: String) {
            
            guard let interface = DBusInterface(rawValue: rawValue)
                else { return nil }
            
            self.rawValue = rawValue
            self.interface = interface
        }
        
        public init(_ interface: DBusInterface) {
            
            self.interface = interface
            self.rawValue = interface.rawValue
        }
    }
}

public extension DBusInterface {
    
    init(_ error: DBusError.Name) {
        
        self = error.interface
    }
}

public extension DBusError.Name {
    
    /// A generic error; "something went wrong" - see the error message for more.
    public static let failed = DBusError.Name(rawValue: "org.freedesktop.DBus.Error.Failed")!
    
    /// Existing file and the operation you're using does not silently overwrite.
    public static let fileExists = DBusError.Name(rawValue: "org.freedesktop.DBus.Error.FileExists")!
    
    /// Missing file.
    public static let fileNotFound = DBusError.Name(rawValue: "org.freedesktop.DBus.Error.FileNotFound")!
    
    /// Invalid arguments
    public static let invalidArguments = DBusError.Name(rawValue: "org.freedesktop.DBus.Error.InvalidArgs")!
    
    /// Invalid signature
    public static let invalidSignature = DBusError.Name(rawValue: "org.freedesktop.DBus.Error.InvalidSignature")!
}

extension DBusError.Name: Equatable {
    
    public static func == (lhs: DBusError.Name, rhs: DBusError.Name) -> Bool {
        
        return lhs.rawValue == rhs.rawValue
    }
}

extension DBusError.Name: Hashable {
    
    public var hashValue: Int {
        
        return rawValue.hashValue
    }
}

extension DBusError.Name: CustomStringConvertible {
    
    public var description: String {
        
        return rawValue
    }
}
