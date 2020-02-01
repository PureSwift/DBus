//
//  Error.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 2/25/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import Foundation
import CDBus

/// DBus type representing an exception.
public struct DBusError: Error, Equatable, Hashable {
    
    /// Error name field
    public let name: DBusError.Name
    
    /// Error message field
    public let message: String
    
    internal init(name: DBusError.Name, message: String) {
        
        self.name = name
        self.message = message
    }
}

// MARK: - Internal Reference

internal extension DBusError {
    
    /// Internal class for working with the C DBus error API
    final class Reference {
        
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
        
        func hasName(_ name: String) -> Bool {
            
            return Bool(dbus_error_has_name(&internalValue, name))
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

// MARK: CustomNSError

extension DBusError: CustomNSError {
    
    public enum UserInfoKey: String {
        
        /// DBus error name
        case name
    }
    
    /// The domain of the error.
    public static let errorDomain = "org.freedesktop.DBus.Error"
    
    /// The error code within the given domain.
    public var errorCode: Int {
        
        return hashValue
    }
    
    /// The user-info dictionary.
    public var errorUserInfo: [String: Any] {
        
        return [
            UserInfoKey.name.rawValue: self.name.rawValue,
            NSLocalizedDescriptionKey: self.message
        ]
    }
}

// MARK: Error Name

public extension DBusError {
    
    struct Name: Equatable, Hashable {
        
        public let rawValue: String
        
        public init?(rawValue: String) {
            
            // validate from C, no parsing
            do { try DBusInterface.validate(rawValue) }
            catch { return nil }
            
            self.rawValue = rawValue
        }
    }
}

public extension DBusError.Name {
    
    init(_ interface: DBusInterface) {
        
        // should be valid
        self.rawValue = interface.rawValue
    }
}

public extension DBusInterface {
    
    init(_ error: DBusError.Name) {
        
        self.init(rawValue: error.rawValue)!
    }
}

public extension DBusError.Name {
    
    /// A generic error; "something went wrong" - see the error message for more.
    ///
    /// `org.freedesktop.DBus.Error.Failed`
    static let failed = DBusError.Name(rawValue: DBUS_ERROR_FAILED)!
    
    /// No Memory
    ///
    /// `org.freedesktop.DBus.Error.NoMemory`
    static let noMemory = DBusError.Name(rawValue: DBUS_ERROR_NO_MEMORY)!
    
    /// Existing file and the operation you're using does not silently overwrite.
    ///
    /// `org.freedesktop.DBus.Error.FileExists`
    static let fileExists = DBusError.Name(rawValue: DBUS_ERROR_FILE_EXISTS)!
    
    /// Missing file.
    ///
    /// `org.freedesktop.DBus.Error.FileNotFound`
    static let fileNotFound = DBusError.Name(rawValue: DBUS_ERROR_FILE_NOT_FOUND)!
    
    /// Invalid arguments
    ///
    /// `org.freedesktop.DBus.Error.InvalidArgs`
    static let invalidArguments = DBusError.Name(rawValue: DBUS_ERROR_INVALID_ARGS)!
    
    /// Invalid signature
    ///
    /// `org.freedesktop.DBus.Error.InvalidSignature`
    static let invalidSignature = DBusError.Name(rawValue: DBUS_ERROR_INVALID_SIGNATURE)!
}

extension DBusError.Name: CustomStringConvertible {
    
    public var description: String {
        
        return rawValue
    }
}
