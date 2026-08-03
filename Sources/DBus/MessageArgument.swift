//
//  MessageArgument.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 2/26/16.
//  Copyright © 2016 Pure All rights reserved.
//

/// DBus Message argument value.
public enum DBusMessageArgument: Equatable, Hashable, Sendable {

    case byte(UInt8)
    case boolean(Bool)
    case int16(Int16)
    case uint16(UInt16)
    case int32(Int32)
    case uint32(UInt32)
    case int64(Int64)
    case uint64(UInt64)
    case double(Double)
    case fileDescriptor(FileDescriptor)

    case string(String)
    case objectPath(DBusObjectPath)
    case signature(DBusSignature)

    case array(Array)
    case `struct`(Structure)
    case dictionary(Dictionary)

    /// A value whose type is carried alongside the value itself.
    ///
    /// - Note: `indirect` because the payload contains a `DBusMessageArgument` directly rather
    /// than through an array, which would otherwise make the enum recursively sized.
    indirect case variant(Variant)
}

public extension DBusMessageArgument {

    /// Argument value type.
    var type: DBusSignature.ValueType {

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
        case .variant: return .variant
        case let .array(array): return .array(array.type)
        case let .struct(structure): return .struct(structure.type)
        case let .dictionary(dictionary): return .dictionary(dictionary.type)
        }
    }
}

// MARK: - Supporting Types

public extension DBusMessageArgument {

    /// File Descriptor
    struct FileDescriptor: RawRepresentable, Equatable, Hashable, Sendable {

        public var rawValue: Int32

        public init(rawValue: Int32) {

            self.rawValue = rawValue
        }
    }
}

// MARK: - Variant

public extension DBusMessageArgument {

    /// A variant contains a single complete value of any type, with the type marshalled
    /// alongside the value.
    struct Variant: Equatable, Hashable, Sendable {

        /// The contained value.
        public let element: DBusMessageArgument

        public init(_ element: DBusMessageArgument) {

            self.element = element
        }
    }
}

public extension DBusMessageArgument.Variant {

    /// The type of the contained value.
    ///
    /// - Note: This is the signature marshalled *inside* the variant, not the variant's own
    /// type code.
    var elementType: DBusSignature.ValueType {

        return element.type
    }
}

// MARK: - Structure

public extension DBusMessageArgument {

    /// Structure
    struct Structure: Equatable, Hashable, Sendable {

        /// Structure elements.
        internal let elements: [DBusMessageArgument]

        /// Initializes a structure argument with the specified arguments.
        ///
        /// - Note: Returns `nil` for an empty array; the specification requires at least one
        /// type code between the parentheses.
        public init?(_ elements: [DBusMessageArgument]) {

            guard elements.isEmpty == false
                else { return nil }

            self.elements = elements
        }
    }
}

public extension DBusMessageArgument.Structure {

    var type: DBusSignature.StructureType {

        let types = elements.map { $0.type }

        guard let structureType = DBusSignature.StructureType(types)
            else { fatalError("Invalid structure") }

        return structureType
    }
}

// MARK: RandomAccessCollection

extension DBusMessageArgument.Structure: RandomAccessCollection {

    public typealias Element = DBusMessageArgument

    public typealias Index = Int

    public subscript (index: Index) -> Element {
        return elements[index]
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

    public func makeIterator() -> IndexingIterator<DBusMessageArgument.Structure> {
        return IndexingIterator(_elements: self)
    }
}

// MARK: - Array

public extension DBusMessageArgument {

    struct Array: Equatable, Hashable, Sendable {

        /// Array elements.
        internal let elements: [DBusMessageArgument]

        /// Type of the elements.
        ///
        /// - Note: Stored explicitly rather than inferred from `elements`, so that an empty
        /// array still marshals with the correct element signature.
        public let type: DBusSignature.ValueType

        /// Initialize with an empty array.
        public init(type: DBusSignature.ValueType) {

            self.elements = []
            self.type = type
        }

        /// Initialize with an array of homogenous array elements and tries to infer the element value type.
        public init?(_ elements: [Element]) {

            // dynamically infer signature
            guard let element = elements.first
                else { return nil } // can't infer from empty array

            self.init(type: element.type, elements)
        }

        /// Initialize with an array of homogenous array elements.
        public init?(type: DBusSignature.ValueType, _ elements: [Element]) {

            // validate homogenous array
            if elements.isEmpty == false {

                for element in elements {

                    guard element.type == type
                        else { return nil } // all elements must have the same type
                }
            }

            self.elements = elements
            self.type = type
        }
    }
}

// MARK: RandomAccessCollection

extension DBusMessageArgument.Array: RandomAccessCollection {

    public typealias Element = DBusMessageArgument

    public typealias Index = Int

    public subscript (index: Index) -> Element {
        return elements[index]
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

    public func makeIterator() -> IndexingIterator<DBusMessageArgument.Array> {
        return IndexingIterator(_elements: self)
    }
}

// MARK: - Dictionary

public extension DBusMessageArgument {

    /// A dictionary, marshalled as an array of key/value entries.
    ///
    /// - Note: Entries are stored in order. D-Bus dictionaries are ordered on the wire, and the
    /// specification does not require unique keys, so this deliberately does not use
    /// `Swift.Dictionary`.
    struct Dictionary: Equatable, Hashable, Sendable {

        /// A single key/value pair.
        public struct Entry: Equatable, Hashable, Sendable {

            public let key: DBusMessageArgument

            public let value: DBusMessageArgument

            public init(key: DBusMessageArgument, value: DBusMessageArgument) {

                self.key = key
                self.value = value
            }
        }

        /// Dictionary entries, in wire order.
        internal let entries: [Entry]

        /// Type of the keys.
        public let keyType: DBusSignature.ValueType

        /// Type of the values.
        public let valueType: DBusSignature.ValueType

        /// Initialize an empty dictionary with the specified key and value types.
        ///
        /// - Note: Returns `nil` if `keyType` is not a basic type.
        public init?(keyType: DBusSignature.ValueType, valueType: DBusSignature.ValueType) {

            guard keyType.isBasic
                else { return nil }

            self.entries = []
            self.keyType = keyType
            self.valueType = valueType
        }

        /// Initialize with entries, validating that all keys and values share a type.
        ///
        /// - Note: Returns `nil` if `keyType` is not a basic type, or if any entry does not
        /// match the declared types.
        public init?(keyType: DBusSignature.ValueType,
                     valueType: DBusSignature.ValueType,
                     _ entries: [Entry]) {

            guard keyType.isBasic
                else { return nil }

            for entry in entries {

                guard entry.key.type == keyType,
                    entry.value.type == valueType
                    else { return nil }
            }

            self.entries = entries
            self.keyType = keyType
            self.valueType = valueType
        }

        /// Initialize with entries, inferring the key and value types from the first entry.
        ///
        /// - Note: Returns `nil` for an empty array, since the types cannot be inferred.
        public init?(_ entries: [Entry]) {

            guard let first = entries.first
                else { return nil }

            self.init(keyType: first.key.type, valueType: first.value.type, entries)
        }
    }
}

public extension DBusMessageArgument.Dictionary {

    var type: DBusSignature.DictionaryType {

        guard let dictionaryType = DBusSignature.DictionaryType(key: keyType, value: valueType)
            else { fatalError("Invalid dictionary key type \(keyType)") }

        return dictionaryType
    }
}

// MARK: RandomAccessCollection

extension DBusMessageArgument.Dictionary: RandomAccessCollection {

    public typealias Element = Entry

    public typealias Index = Int

    public subscript (index: Index) -> Element {
        return entries[index]
    }

    public var count: Int {
        return entries.count
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

    public func makeIterator() -> IndexingIterator<DBusMessageArgument.Dictionary> {
        return IndexingIterator(_elements: self)
    }
}

// MARK: - Convenience Accessors

public extension DBusMessageArgument {

    /// The contained value if this is a variant, otherwise `nil`.
    var variantValue: DBusMessageArgument? {

        guard case let .variant(variant) = self else { return nil }
        return variant.element
    }

    /// The string value, unwrapping a single level of variant.
    var stringValue: String? {

        switch self {
        case let .string(value): return value
        case let .variant(variant): return variant.element.stringValue
        default: return nil
        }
    }
}
