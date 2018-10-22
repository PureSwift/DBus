//
//  Signature.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 10/22/18.
//

import CDBus

public struct DBusSignature {
    
    @_versioned
    internal var elements: [ValueType]
}

extension DBusSignature: RawRepresentable {
    
    public init?(rawValue: String) {
        
        fatalError()
    }
    
    public var rawValue: String {
        
        fatalError()
    }
}

public extension DBusSignature {
    
    public indirect enum ValueType {
        
        /// Type code marking an 8-bit unsigned integer.
        case byte
        
        /// Type code marking a boolean.
        ///
        /// Boolean value: 0 is false, 1 is true, any other value allowed by the marshalling format is invalid.
        case boolean
        
        /// Type code marking a 16-bit signed integer
        case int16
        
        /// Type code marking a 16-bit unsigned integer.
        case uint16
        
        /// Signed (two's complement) 32-bit integer
        case int32
        
        /// Unsigned 32-bit integer
        case uint32
        
        /// Signed (two's complement) 64-bit integer
        case int64
        
        /// Unsigned 64-bit integer
        case uint64
        
        /// IEEE 754 double-precision floating point
        case double
        
        ///  Unix file descriptor
        ///
        /// Unsigned 32-bit integer representing an index into an out-of-band array of file descriptors, transferred via some platform-specific mechanism
        case fileDescriptor
        
        // String-like types
        
        /// String
        ///
        /// - Note: No extra constraints.
        case string
        
        /// DBus Object Path
        ///
        /// - Note: Must be a [syntactically valid object path](https://dbus.freedesktop.org/doc/dbus-specification.html#message-protocol-marshaling-object-path).
        case objectPath
        
        /// DBus Signature
        ///
        /// - Note: Zero or more single complete types
        case signature
        
        // Container Type
        
        /// STRUCT has a type code, ASCII character 'r', but this type code does not appear in signatures.
        /// Instead, ASCII characters '(' and ')' are used to mark the beginning and end of the struct.
        /// So for example, a struct containing two integers would have this signature: "`(ii)`".
        case `struct`(StructureType)
        
        /// Array
        case array(ValueType)
        
        /// Dictionary
        case dictionary(ValueType)
    }
}

public extension DBusSignature {
    
    public struct StructureType {
        
        @_versioned
        internal private(set) var elements: [ValueType]
        
        /// Empty structures are not allowed; there must be at least one type code between the parentheses.
        public init?(_ elements: [ValueType]) {
            
            guard elements.isEmpty == false
                else { return nil }
            
            self.elements = elements
        }
    }
}

extension DBusSignature.StructureType: RawRepresentable {
    
    public init?(rawValue: String) {
        
        fatalError()
    }
    
    public var rawValue: String {
        
        fatalError()
    }
}

public extension DBusSignature {
    
    public enum ArrayType {
        
        case dictionary(ValueType)
        case value(ValueType)
    }
}

extension DBusSignature.ArrayType: RawRepresentable {
    
    public init?(rawValue: String) {
        
        fatalError()
    }
    
    public var rawValue: String {
        
        fatalError()
    }
}
