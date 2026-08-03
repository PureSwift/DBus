//
//  Signature.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 10/22/18.
//

/// DBus Signature
public struct DBusSignature: Sendable {

    /// Elements.
    @usableFromInline
    internal private(set) var elements: [Element]

    /// Cached string.
    /// This will be the original string the object path was created from.
    ///
    /// - Note: Any subsequent mutation will set this value to nil, and `rawValue` and `description` getters
    /// will have to rebuild the string for every invocation. Mutating leads to an unoptimized code path,
    /// but for values created from either a string or an array of elements, this value is cached.
    @usableFromInline
    internal private(set) var string: String?

    public init(_ elements: [Element] = []) {

        self.elements = elements
        self.string = String(elements)
    }
}

internal extension DBusSignature {

    init(_ unsafe: String) {

        guard let value = DBusSignature(rawValue: unsafe)
            else { fatalError("Invalid signature \(unsafe)") }

        self = value
    }
}

// MARK: - String Parsing

internal extension DBusSignature {

    static let length = (min: 0, max: 255)

    /// Maximum container nesting depth, per the D-Bus specification.
    ///
    /// Arrays and structs are counted separately.
    static let maximumDepth = 32

    /// Validates the signature string, throwing a descriptive error if it is malformed.
    static func validate(_ string: String) throws {

        _ = try parseThrowing(string)
    }

    /// Parse the DBus signature string.
    static func parse(_ string: String) -> [ValueType]? {

        return try? parseThrowing(string)
    }

    static func parseThrowing(_ string: String) throws -> [ValueType] {

        // The signature is a UTF-8 string, but only ASCII type codes are legal, so the
        // byte count is the meaningful length. Measured in bytes, not `Character`s.
        guard string.utf8.count >= length.min
            else { throw DBusError.invalidSignature(string, "Signature is too short") }

        guard string.utf8.count <= length.max
            else { throw DBusError.invalidSignature(string, "Signature exceeds maximum length of \(length.max) bytes") }

        var characters = [Character]()
        characters.reserveCapacity(string.utf8.count)

        for stringCharacter in string {

            // invalid character
            guard let character = Character(rawValue: String(stringCharacter))
                else { throw DBusError.invalidSignature(string, "Unknown typecode '\(stringCharacter)'") }

            characters.append(character)
        }

        var position = 0
        var elements = [Element]()

        while position < characters.count {

            let element = try parseFirst(characters, position: &position, arrayDepth: 0, structDepth: 0)

            elements.append(element)
        }

        return elements
    }

    static func parse(_ characters: [Character]) -> [Element]? {

        guard characters.isEmpty == false
            else { return [] }

        var position = 0
        var elements = [Element]()

        while position < characters.count {

            guard let element = try? parseFirst(characters, position: &position, arrayDepth: 0, structDepth: 0)
                else { return nil }

            elements.append(element)
        }

        return elements
    }

    /// Parse a single complete type starting at `position`.
    private static func parseFirst(_ characters: [Character],
                                   position: inout Int,
                                   arrayDepth: Int,
                                   structDepth: Int) throws -> ValueType {

        // get first character
        let character = characters[position]

        position += 1

        let charactersLeft = characters.count - position
        assert(charactersLeft >= 0)

        switch character {

        // simple / single letter types
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

        // container types
        case .array:

            guard arrayDepth < maximumDepth
                else { throw DBusError.invalidSignature(String(characters), "Array nesting exceeds maximum depth of \(maximumDepth)") }

            guard charactersLeft >= 1
                else { throw DBusError.invalidSignature(String(characters), "Missing array element type") }

            if characters[position] == .dictionaryEntryStart {

                position += 1

                var elements = [Element]()

                while position < characters.count, characters[position] != .dictionaryEntryEnd  {

                    let element = try parseFirst(characters,
                                                 position: &position,
                                                 arrayDepth: arrayDepth + 1,
                                                 structDepth: structDepth)

                    elements.append(element)
                }

                guard elements.count == 2
                    else { throw DBusError.invalidSignature(String(characters), "Dictionary entry must contain exactly two types") }

                guard position < characters.count,
                    characters[position] == .dictionaryEntryEnd
                    else { throw DBusError.invalidSignature(String(characters), "Dictionary entry started but not ended") }

                guard let dictionary = DictionaryType(key: elements[0], value: elements[1])
                    else { throw DBusError.invalidSignature(String(characters), "Dictionary entry key must be a basic type") }

                position += 1

                return .dictionary(dictionary)

            } else {

                let valueType = try parseFirst(characters,
                                               position: &position,
                                               arrayDepth: arrayDepth + 1,
                                               structDepth: structDepth)

                return .array(valueType)
            }

        case .structStart:

            guard structDepth < maximumDepth
                else { throw DBusError.invalidSignature(String(characters), "Struct nesting exceeds maximum depth of \(maximumDepth)") }

            guard charactersLeft >= 2
                else { throw DBusError.invalidSignature(String(characters), "Struct started but not ended") }

            var elements = [Element]()

            while position < characters.count, characters[position] != .structEnd  {

                let element = try parseFirst(characters,
                                             position: &position,
                                             arrayDepth: arrayDepth,
                                             structDepth: structDepth + 1)

                elements.append(element)
            }

            guard position < characters.count,
                characters[position] == .structEnd
                else { throw DBusError.invalidSignature(String(characters), "Struct started but not ended") }

            position += 1

            guard let structureType = StructureType(elements)
                else { throw DBusError.invalidSignature(String(characters), "Empty structs are not allowed") }

            return .struct(structureType)

        case .structEnd:

            throw DBusError.invalidSignature(String(characters), "Struct ended but not started")

        case .dictionaryEntryStart, .dictionaryEntryEnd:

            throw DBusError.invalidSignature(String(characters), "Dict entry not inside array")
        }
    }
}

private extension DBusError {

    static func invalidSignature(_ string: String, _ reason: String) -> DBusError {

        return DBusError(name: .invalidSignature, message: "\(reason): '\(string)'")
    }
}

// MARK: - RawRepresentable

extension DBusSignature: RawRepresentable {

    public init?(rawValue: String) {

        guard let elements = try? DBusSignature.parseThrowing(rawValue)
            else { return nil }

        self.elements = elements
        self.string = rawValue
    }

    public var rawValue: String {

        return string ?? String(elements)
    }
}

// MARK: - Equatable

extension DBusSignature: Equatable {

    public static func == (lhs: DBusSignature, rhs: DBusSignature) -> Bool {

        // fast path
        if let lhsString = lhs.string,
            let rhsString = rhs.string {

            return lhsString == rhsString
        }

        // slower comparison
        return lhs.elements == rhs.elements
    }
}

extension DBusSignature: Hashable {

    public func hash(into hasher: inout Hasher) {

        hasher.combine(rawValue)
    }
}

extension DBusSignature: CustomStringConvertible {

    public var description: String {

        return rawValue
    }
}

extension DBusSignature: ExpressibleByArrayLiteral {

    public init(arrayLiteral elements: Element...) {

        self.init(elements)
    }
}

// MARK: Collection

extension DBusSignature: MutableCollection {

    public typealias Element = ValueType

    public typealias Index = Int

    public subscript (index: Index) -> Element {

        get { return elements[index] }

        mutating set {
            string = nil
            elements[index] = newValue
        }
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

    public func makeIterator() -> IndexingIterator<DBusSignature> {
        return IndexingIterator(_elements: self)
    }

    public mutating func append(_ element: Element) {

        string = nil
        elements.append(element)
    }

    @discardableResult
    public mutating func removeFirst() -> Element {

        string = nil
        return elements.removeFirst()
    }

    @discardableResult
    public mutating func removeLast() -> Element {

        string = nil
        return elements.removeLast()
    }

    @discardableResult
    public mutating func remove(at index: Int) -> Element {

        string = nil
        return elements.remove(at: index)
    }

    /// Removes all elements from the object path.
    public mutating func removeAll(keepingCapacity: Bool = false) {

        string = nil
        self.elements.removeAll(keepingCapacity: keepingCapacity)
    }
}

extension DBusSignature: RandomAccessCollection { }

public extension DBusSignature {

    indirect enum ValueType: Equatable, Hashable, Sendable {

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

        /// Variant type (the type of the value is part of the value itself)
        case variant

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
        case dictionary(DictionaryType)
    }
}

public extension DBusSignature.ValueType {

    var isContainer: Bool {

        switch self {
        case .struct,
             .array,
             .dictionary:
            return true
        default:
            return false
        }
    }

    /// A basic type is fully specified by a single type code, with no nested type information.
    ///
    /// - Note: `variant` is *not* a basic type, even though it is written as a single type code —
    /// its contained type is part of the value rather than the signature. Only basic types are
    /// permitted as dictionary keys.
    var isBasic: Bool {

        switch self {
        case .byte,
             .boolean,
             .int16,
             .uint16,
             .int32,
             .uint32,
             .int64,
             .uint64,
             .double,
             .fileDescriptor,
             .string,
             .objectPath,
             .signature:
            return true
        case .variant,
             .struct,
             .array,
             .dictionary:
            return false
        }
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
    enum Character: String, Sendable {

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
        case let .struct(structureType): return structureType.characters
        case let .dictionary(dictionary): return dictionary.characters
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

// MARK: - DictionaryType

public extension DBusSignature {

    struct DictionaryType: Equatable, Hashable, Sendable {

        public let key: ValueType

        public let value: ValueType

        /// - Note: Returns `nil` if `key` is not a basic type. The specification restricts
        /// dictionary keys to basic types, which excludes `variant` as well as the containers.
        public init?(key: ValueType,
                    value: ValueType) {

            guard key.isBasic
                else { return nil }

            self.key = key
            self.value = value
        }
    }
}

public extension DBusSignature.DictionaryType {

    var characters: [DBusSignature.Character] {

        return [.array, .dictionaryEntryStart] + key.characters + value.characters + [.dictionaryEntryEnd]
    }
}

extension DBusSignature.DictionaryType: RawRepresentable {

    public init?(rawValue: String) {

        guard let elements = DBusSignature.parse(rawValue),
            elements.count == 1,
            case let .dictionary(dictionaryType) = elements[0]
            else { return nil }

        self = dictionaryType
    }

    public var rawValue: String {

        return String(characters)
    }
}

// MARK: - StructureType

public extension DBusSignature {

    struct StructureType: Sendable {

        @usableFromInline
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

extension DBusSignature.StructureType: Hashable {

    public func hash(into hasher: inout Hasher) {

        hasher.combine(elements)
    }
}

public extension DBusSignature.StructureType {

    var characters: [DBusSignature.Character] {

        return [.structStart] + elements.reduce([], { $0 + $1.characters }) + [.structEnd]
    }
}

extension DBusSignature.StructureType: RawRepresentable {

    public init?(rawValue: String) {

        guard let elements = DBusSignature.parse(rawValue),
            elements.count == 1,
            case let .struct(structureType) = elements[0]
            else { return nil }

        self = structureType
    }

    public var rawValue: String {

        return String(characters)
    }
}

extension DBusSignature.StructureType: ExpressibleByArrayLiteral {

    public init(arrayLiteral elements: Element...) {

        guard let structureType = DBusSignature.StructureType(elements)
            else { fatalError("Invalid array literal \(elements)") }

        self = structureType
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
