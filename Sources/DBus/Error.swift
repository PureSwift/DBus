//
//  Error.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 2/25/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import Foundation
import CDBus

// This error is for DBus (swift) runtime failures.
public enum RuntimeError: Error {
    case generic(String)
}

// Given a swift string, make a copy of the C string (const char *) and return a pointer to it.
// This will throw RuntimeError.generic if malloc() fails∫.
func swiftStringToConstCharStar(_ s: String) throws -> UnsafePointer<Int8> {
    return try s.withCString { (unsafePointer: UnsafePointer<Int8>) -> UnsafePointer<Int8> in
        // We need to copy the string to save a copy. unsafePointer is only valid in this closure
        // UnsafeMutableRawPointer
        let bufferLen = strlen(unsafePointer) + 1
        guard let unsafeMutableRawPointer = malloc(bufferLen) else {
            throw RuntimeError.generic("malloc() failed")
        }
        memcpy(unsafeMutableRawPointer, unsafePointer, bufferLen)
        // UnsafeMutablePointer<Int8>
        let unsafeMutablePointer = unsafeMutableRawPointer.assumingMemoryBound(to: Int8.self)
        // UnsafePointer<Int8>
        return UnsafePointer(unsafeMutablePointer)
    }
}

// This is a wrapper of the libdbus DBusError type.
public class DBusError: Error, Equatable, CustomStringConvertible {
    internal var internalValue = CDBus.DBusError()

    init() {
        dbus_error_init(&internalValue);
    }

    // This will throw RuntimeError.generic if the name passed in is not a valid DBus error name,
    // or if malloc() fails when we are copying the strings to live in C land.
    convenience init(name: String, message: String = "") throws {
        self.init()

        let validationError = DBusError()
        let isValid = dbus_validate_error_name(name, &validationError.internalValue)
        if isValid == false {
            throw RuntimeError.generic("\(name) is not a valid DBus Error name.")
        }

        let cName = try swiftStringToConstCharStar(name)
        let cMessage = try swiftStringToConstCharStar(message)
        dbus_set_error_const(&internalValue, cName, cMessage)
    }

    deinit {
        dbus_error_free(&internalValue)
    }

    public var isSet: Bool {
        let dbusBool = dbus_error_is_set(&internalValue)
        return Bool(dbusBool)
    }

    public var name: String {
        return String(cString: internalValue.name)
    }

    public var message: String {
        return String(cString: internalValue.message)
    }

    public static func == (lhs: DBusError, rhs: DBusError) -> Bool {
        let lhsName = String(cString: lhs.internalValue.name)
        let rhsName = String(cString: rhs.internalValue.name)
        let lhsMessage = String(cString: lhs.internalValue.message)
        let rhsMessage = String(cString: rhs.internalValue.message)
        return (lhsName == rhsName &&
            lhsMessage == rhsMessage)
    }

    public var description: String {
        return "DBusError(name: '\(name)', message: '\(message)') "
    }
}

public extension DBusError {

    public struct Name {
        /// A generic error; "something went wrong" - see the error message for more.
        ///
        /// `org.freedesktop.DBus.Error.Failed`
        public static let failed = String(DBUS_ERROR_FAILED)

        /// No Memory
        ///
        /// `org.freedesktop.DBus.Error.NoMemory`
        public static let noMemory = String(DBUS_ERROR_NO_MEMORY)

        /// Existing file and the operation you're using does not silently overwrite.
        ///
        /// `org.freedesktop.DBus.Error.FileExists`
        public static let fileExists = String(DBUS_ERROR_FILE_EXISTS)

        /// Missing file.
        ///
        /// `org.freedesktop.DBus.Error.FileNotFound`
        public static let fileNotFound = String(DBUS_ERROR_FILE_NOT_FOUND)

        /// Invalid arguments
        ///
        /// `org.freedesktop.DBus.Error.InvalidArgs`
        public static let invalidArguments = String(DBUS_ERROR_INVALID_ARGS)

        /// Invalid signature
        ///
        /// `org.freedesktop.DBus.Error.InvalidSignature`
        public static let invalidSignature = String(DBUS_ERROR_INVALID_SIGNATURE)
    }
}
