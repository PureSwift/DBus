//
//  Signature.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 10/22/18.
//

import CDBus

/// DBus Signature
public struct DBusSignature {
    
    @_versioned
    internal private(set) var elements: [ValueType]
    
    public init(_ elements: [ValueType]) {
        
        self.elements = elements
    }
}

extension DBusSignature: Equatable {
    
    public static func == (lhs: DBusSignature, rhs: DBusSignature) -> Bool {
        
        return lhs.elements == rhs.elements
    }
}

extension DBusSignature: Hashable {
    
    public var hashValue: Int {
        
        return rawValue.hashValue
    }
}

extension DBusSignature: CustomStringConvertible {
    
    public var description: String {
        
        return rawValue
    }
}

extension DBusSignature: RawRepresentable {
    
    public init?(rawValue: String) {
        
        fatalError()
    }
    
    public var rawValue: String {
        
        return String(self.elements)
    }
}

public extension DBusSignature {
    
    public indirect enum ValueType: Equatable {
        
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
        
        /// Variant type (the type of the value is part of the value itself)
        case variant
    }
}

internal extension DBusSignature.ValueType {
    
    static func parse(_ string: String) -> DBusSignature.ValueType? {
        
        var characters = [DBusSignature.Character]()
        characters.reserveCapacity(string.count)
        
        for stringCharacter in string {
            
            // invalid character
            guard let character = DBusSignature.Character(rawValue: String(stringCharacter))
                else { return nil }
            
            characters.append(character)
        }
        
        guard let valueType = DBusSignature.ValueType(characters)
            else { return nil }
        
        return valueType
    }
}

public extension String {
    
    init(_ type: DBusSignature.ValueType) {
        
        self.init(type.characters)
    }
}

public extension String {
    
    init(_ signature: [DBusSignature.ValueType]) {
        
        self.init(signature.characters)
    }
}

public extension DBusSignature {
    
    /// DBus Signature Character
    public enum Character: String {
        
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
        
        // Container
        
        /// Struct
        ///
        /// - Note: Struct has a type code, ASCII character 'r', but this type code does not appear in signatures.
        /// Instead, ASCII characters '(' and ')' are used to mark the beginning and end of the struct.
        /// So for example, a struct containing two integers would have this signature: "`(ii)`".
        case structStart           = "("
        case structEnd             = ")"
        
        /// Entry in a dict or map (array of key-value pairs).
        ///
        /// - Note: Type code 101 'e' is reserved for use in bindings and implementations
        /// to represent the general concept of a dict or dict-entry, and must not appear in signatures used on D-Bus.
        case dictionaryEntryStart    = "{"
        case dictionaryEntryEnd      = "}"
    }
}

public extension DBusSignature.ValueType {
    
    init?(_ characters: [DBusSignature.Character]) {
        
        guard let character = characters.first
            else { return nil }
        
        switch character {
            
        // simple / single letter types
        case .byte: self = .byte
        case .boolean: self = .boolean
        case .int16: self = .int16
        case .int32: self = .int32
        case .int64: self = .int64
        case .uint16: self = .uint16
        case .uint32: self = .uint32
        case .uint64: self = .uint64
        case .double: self = .double
        case .fileDescriptor: self = .fileDescriptor
        case .string: self = .string
        case .objectPath: self = .objectPath
        case .signature: self = .signature
        case .variant: self = .variant
        
        // container types
        case .array:
            
            guard characters.count > 1,
                let valueType = DBusSignature.ValueType(Array(characters.suffix(from: 1)))
                else { return nil }
            
            self = .array(valueType)
            
        //case .dictionary: fatalError("Confused")
            
        case .structStart:
            
            guard characters.count > 2,
                let structureType = DBusSignature.StructureType(characters)
                else { return nil }
            
            self = .struct(structureType)
            
        default:
            return nil
        }
    }
    
    var characters: [DBusSignature.Character] {
        
        switch self {
        case .byte: return [.byte]
        case .boolean: return [.boolean]
        case .int16: return [.int16]
        case .int32: return [.int32]
        case .int64: return [.int64]
        case .uint16: return [.uint16]
        case .uint32: return [.uint32]
        case .uint64: return [.uint64]
        case .double: return [.double]
        case .fileDescriptor: return [.fileDescriptor]
        case .string: return [.string]
        case .objectPath: return [.objectPath]
        case .signature: return [.signature]
        case .variant: return [.variant]
        case let .array(type): return [.array] + type.characters
        case let .struct(type): return [.structStart] + type.elements.reduce([], { $0 + $1.characters }) + [.structEnd]
        case let .dictionary(type): return [.dictionaryEntryStart] + type.characters + [.dictionaryEntryEnd]
        }
    }
}

public extension Collection where Element == DBusSignature.ValueType {
    
    var characters: [DBusSignature.Character] {
        
        return self.reduce([], { $0 + $1.characters })
    }
}

public extension String {
    
    init(_ signature: [DBusSignature.Character]) {
        
        self = signature.reduce("", { $0 + $1.rawValue })
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

extension DBusSignature.StructureType: Equatable {
    
    public static func == (lhs: DBusSignature.StructureType, rhs: DBusSignature.StructureType) -> Bool {
        
        return lhs.elements == rhs.elements
    }
}

extension DBusSignature.StructureType: RawRepresentable {
    
    public init?(rawValue: String) {
        
        fatalError()
    }
    
    public var rawValue: String {
        
        return String(self.elements)
    }
}

// MARK: Collection

extension DBusSignature.StructureType: MutableCollection {
    
    public typealias Element = DBusSignature.ValueType
    
    public typealias Index = Int
    
    public subscript (index: Index) -> Element {
        
        get { return elements[index] }
        
        mutating set { elements[index] = newValue }
    }
    
    public var count: Int {
        
        return elements.count
    }
    
    /// The start `Index`.
    public var startIndex: Index {
        return 0
    }
    
    /// The end `Index`.
    ///
    /// This is the "one-past-the-end" position, and will always be equal to the `count`.
    public var endIndex: Index {
        return count
    }
    
    public func index(before i: Index) -> Index {
        return i - 1
    }
    
    public func index(after i: Index) -> Index {
        return i + 1
    }
    
    public func makeIterator() -> IndexingIterator<DBusSignature.StructureType> {
        return IndexingIterator(_elements: self)
    }
    
    public mutating func append(_ element: Element) {
        
        elements.append(element)
    }
    
    @discardableResult
    public mutating func removeFirst() -> Element {
        
        return elements.removeFirst()
    }
    
    @discardableResult
    public mutating func removeLast() -> Element {
        
        return elements.removeLast()
    }
    
    @discardableResult
    public mutating func remove(at index: Int) -> Element {
        
        return elements.remove(at: index)
    }
    
    /// Removes all elements from the object path.
    public mutating func removeAll(keepingCapacity: Bool = false) {
        
        self.elements.removeAll(keepingCapacity: keepingCapacity)
    }
}

extension DBusSignature.StructureType: RandomAccessCollection { }
