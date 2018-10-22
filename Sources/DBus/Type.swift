//
//  Type.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 2/25/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import CDBus

/// DBus Type (for internal usage with libdbus)
public enum DBusType: String {
    
    // MARK: - Fixed Length Types
    
    /// Type code marking an 8-bit unsigned integer.
    case byte               = "y" // y (121)
    
    /// Type code marking a boolean.
    ///
    /// Boolean value: 0 is false, 1 is true, any other value allowed by the marshalling format is invalid.
    case boolean            = "b" // b (98)
    
    /// Type code marking a 16-bit signed integer
    case int16              = "n" // n (110)
    
    /// Type code marking a 16-bit unsigned integer. 
    case uint16             = "q" // q (113)
    
    /// Signed (two's complement) 32-bit integer
    case int32              = "i" // i (105)
    
    /// Unsigned 32-bit integer
    case uint32             = "u" // u (117)
    
    /// Signed (two's complement) 64-bit integer
    case int64              = "x" // x (120)
    
    /// Unsigned 64-bit integer
    case uint64             = "t" // t (116)
    
    /// IEEE 754 double-precision floating point
    case double             = "d" // d (100)
    
    ///  Unix file descriptor
    ///
    /// Unsigned 32-bit integer representing an index into an out-of-band array of file descriptors, transferred via some platform-specific mechanism
    case fileDescriptor     = "h" // h (104)
    
    // MARK: - String-like types
    
    /// String
    ///
    /// - Note: No extra constraints.
    case string             = "s" // s (115)
    
    /// DBus Object Path
    ///
    /// - Note: Must be a [syntactically valid object path](https://dbus.freedesktop.org/doc/dbus-specification.html#message-protocol-marshaling-object-path).
    case objectPath         = "o" // o (111)
    
    /// DBus Signature
    ///
    /// - Note: Zero or more single complete types
    case signature          = "g" // g (103)
    
    // MARK: - Container types
    
    /// Array
    case array              = "a" // a (97)
    
    /// Variant type (the type of the value is part of the value itself)
    case variant            = "v" // v (118)
    
    /// Struct
    ///
    /// - Note: Struct has a type code, ASCII character 'r', but this type code does not appear in signatures.
    /// Instead, ASCII characters '(' and ')' are used to mark the beginning and end of the struct.
    /// So for example, a struct containing two integers would have this signature: "`(ii)`".
    case `struct`           = "r" // r (114)
    
    /// Entry in a dict or map (array of key-value pairs).
    ///
    /// - Note: Type code 101 'e' is reserved for use in bindings and implementations
    /// to represent the general concept of a dict or dict-entry, and must not appear in signatures used on D-Bus.
    case dictionaryEntry    = "e" // e (101)
}

public extension DBusType {
    
    /// A "basic type" is a somewhat arbitrary concept, but the intent is to include those types that
    /// are fully-specified by a single typecode, with no additional type information or nested values.
    var isBasic: Bool {
        
        return Bool(dbus_type_is_basic(Int32(integerValue)))
    }
    
    /// A "container type" can contain basic types, or nested container types.
    var isContainer: Bool {
        
        return Bool(dbus_type_is_container(Int32(integerValue)))
    }
    
    /// Tells you whether values of this type can change length if you set them to some other value.
    ///
    /// For this purpose, you assume that the first byte of the old and new value would be in the same location,
    /// so alignment padding is not a factor.
    var isFixed: Bool {
        
        return Bool(dbus_type_is_fixed(Int32(integerValue)))
    }
}

internal extension DBusType {
    
    /// Return `true` if the argument is a valid typecode.
    var isValid: Bool {
        
        return Bool(dbus_type_is_fixed(Int32(integerValue)))
    }
}

internal extension DBusType {
    
    init?(_ integerValue: Int) {
        
        guard let scalar = Unicode.Scalar(integerValue)
            else { return nil }
        
        self.init(rawValue: String(Character(scalar)))
        
        assert(isValid)
    }
    
    var integerValue: Int {
        return Int(rawValue.utf8.first!)
    }
}

public extension DBusMessageArgument {
    
    public var type: DBusType {
        
        switch self {
        case .byte: return .byte
        case .boolean: return .boolean
        case .int16: return .int16
        case .int32: return .int32
        case .int64: return .int64
        case .uint16: return .uint16
        case .uint32: return .uint32
        case .uint64: return .uint64
        case .double: return .double
        case .fileDescriptor: return .fileDescriptor
        case .string: return .string
        case .objectPath: return .objectPath
        case .signature: return .signature
        case .array: return .array
        case .variant: return .variant
        case .struct: return .struct
        case .dictionaryEntry: return .dictionaryEntry
        }
    }
}
