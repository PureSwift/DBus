//
//  ObjectPath.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 10/20/18.
//

import Foundation

/// DBus Object Path
public struct DBusObjectPath {
    
    @_versioned
    internal private(set) var internalReference: CopyOnWrite<Reference>
    
    internal init(_ internalReference: CopyOnWrite<Reference>) {
        
        self.internalReference = internalReference
    }
}

internal extension DBusObjectPath {
    
    /// Parses the object path string and returns the parsed object path.
    static func parse(_ string: String) -> [Element]? {
        
        // The path must begin with an ASCII '/' (integer 47) character,
        // and must consist of elements separated by slash characters.
        guard let firstCharacter = string.first, // cant't be empty string
            firstCharacter == DBusObjectPath.separator, // must start with "/"
            string.count == 1 || string.last != DBusObjectPath.separator // last character
            else { return nil }
        
        let pathStrings = string.split(separator: DBusObjectPath.separator,
                                       maxSplits: .max,
                                       omittingEmptySubsequences: true)
        
        var elements = [Element]()
        elements.reserveCapacity(pathStrings.count) // pre-allocate buffer
        
        for elementString in pathStrings {
            
            guard let element = Element(rawValue: String(elementString))
                else { return nil }
            
            elements.append(element)
        }
        
        return elements
    }
}

internal extension String {
    
    init(_ objectPath: [DBusObjectPath.Element]) {
        
        let separator = String(DBusObjectPath.separator)
        self = objectPath.isEmpty ? separator : objectPath.reduce("", { $0 + separator + $1.rawValue })
    }
}

// MARK: - Reference Implementation

extension DBusObjectPath: ReferenceConvertible {
    
    /// Internal cache
    final class Reference: CopyableReference {
        
        /// Default value (`/`)
        internal static let `default` = Reference()
        
        /// Parsed elements. Always initialized to this value.
        private var elements: [Element]
        
        private let queue = DispatchQueue(label: "DBusObjectPath Storage Queue", qos: .default, attributes: [.concurrent])
        
        /// initialize with the elements
        private init(elements: [Element], string: String?) {
            
            self.elements = elements
            self.stringCache = string
        }
        
        internal convenience init(elements: [Element] = []) {
            
            self.init(elements: elements, string: nil)
        }
        
        /// Initialize with a string.
        internal convenience init?(string: String) {
            
            guard let elements = DBusObjectPath.parse(string)
                else { return nil }
            
            self.init(elements: elements, string: string)
        }
        
        internal fileprivate(set) subscript (index: Int) -> Element {
            
            @inline(__always)
            get { return queue.sync { [unowned self] in self.elements[index] } }
            
            @inline(__always)
            set {
                
                queue.sync(flags: [.barrier]) { [unowned self] in
                    
                    // set new value
                    self.elements[index] = newValue
                    
                    // reset cache
                    self.resetStringCache()
                }
            }
        }
        
        /// Cached String value.
        private var stringCache: String?
        
        /// Counter for lazy string rebuilds
        #if os(macOS)
        internal var lazyStringBuild: UInt = 0
        #endif
        
        /// Resets and clears the string cache.
        ///
        /// - Note: This should only be neccesary for unique references that are reused upon mutation.
        ///
        /// - Precondition: Only call from access queue blocks.
        @inline(__always)
        private func resetStringCache() {
            
            self.stringCache = nil
        }
        
        /// Whether the string value is internally cached
        internal var isStringCached: Bool {
            
            return queue.sync { [unowned self] in self.stringCache != nil }
        }
        
        internal var copy: Reference {
            
            return queue.sync { [unowned self] in Reference(elements: self.elements) }
        }
        
        /// lazily initialize string value
        internal var string: String {
            
            guard let cache = queue.sync(execute: { [unowned self] in self.stringCache }) else {
                
                return queue.sync(flags: [.barrier]) { [unowned self] in
                    
                    // lazily initialize
                    let stringValue = String(self.elements)
                    
                    // cache value
                    self.stringCache = stringValue
                    
                    // increment counter
                    #if os(macOS)
                    self.lazyStringBuild += 1
                    #endif
                    
                    return stringValue
                }
            }
            
            return cache
        }
        
        internal var count: Int {
            
            return queue.sync { [unowned self] in self.elements.count }
        }
        
        /// Compare equality and identity
        internal func isEqual(to other: Reference) -> Bool {
            
            // fast path for same instance
            guard self !== other else { return true }
            
            // compare values
            let lhsElements = self.queue.sync { [unowned self] in self.elements }
            let rhsElements = other.queue.sync { other.elements }
            
            return lhsElements == rhsElements
        }
        
        /// Adds a new element at the end of the object path.
        ///
        /// Use this method to append a single element to the end of a mutable object path.
        internal func append(_ element: Element) {
            
            queue.sync(flags: [.barrier]) { [unowned self] in
                
                // lazily rebuild string
                resetStringCache()
                
                // add new element
                self.elements.append(element)
            }
        }
        
        /// Removes and returns the last element of the object path.
        ///
        /// - Precondition: The object path must not be empty.
        internal func removeLast() -> Element {
            
            return queue.sync(flags: [.barrier]) { [unowned self] in
                
                // lazily rebuild string
                resetStringCache()
                
                // remove element
                return self.elements.removeLast()
            }
        }
        
        /// Removes and returns the first element of the object path.
        ///
        /// - Precondition: The object path must not be empty.
        internal func removeFirst() -> Element {
            
            return queue.sync(flags: [.barrier]) { [unowned self] in
                
                // lazily rebuild string
                resetStringCache()
                
                // remove element
                return self.elements.removeFirst()
            }
        }
        
        /// Removes and returns the element at the specified position.
        ///
        /// All the elements following the specified position are moved up to close the gap.
        internal func remove(at index: Int) -> Element {
            
            return queue.sync(flags: [.barrier]) { [unowned self] in
                
                // lazily rebuild string
                resetStringCache()
                
                // remove element
                return self.elements.remove(at: index)
            }
        }
    }
}

// MARK: - Constants

internal extension DBusObjectPath {
    
    static let separator = "/".first!
}

public extension DBusObjectPath {
    
    public init() {
        
        // all new empty paths should point to same underlying object
        // and copy upon the first mutation regardless of ARC (due to being a singleton)
        self.init(CopyOnWrite<Reference>(.default, externalRetain: true))
    }
    
    /// Initialize with an array of elements.
    public init(_ elements: [Element]) {
        
        let reference = Reference(elements: elements)
        self.init(reference)
    }
    
    /// Initialize with a variable argument list of elements.
    public init(_ elements: Element...) {
        
        let reference = Reference(elements: elements)
        self.init(reference)
    }
    
    /// Initialize with a sequence of elements.
    public init <S: Sequence> (_ sequence: S) where S.Element == Element {
        
        let reference = Reference(elements: Array(sequence))
        self.init(reference)
    }
}

// MARK: - RawRepresentable

extension DBusObjectPath: RawRepresentable {
    
    public init?(rawValue: String) {
        
        guard let reference = Reference(string: rawValue)
            else { return nil }
        
        self.init(reference)
    }
    
    public var rawValue: String {
        
        get { return internalReference.reference.string }
    }
}

// MARK: - Equatable

extension DBusObjectPath: Equatable {
    
    public static func == (lhs: DBusObjectPath, rhs: DBusObjectPath) -> Bool {
        
        return lhs.internalReference.reference.isEqual(to: rhs.internalReference.reference)
    }
}

// MARK: - Hashable

extension DBusObjectPath: Hashable {
    
    public var hashValue: Int {
        
        return internalReference.reference.string.hashValue
    }
}

// MARK: - CustomStringConvertible

extension DBusObjectPath: CustomStringConvertible {
    
    public var description: String {
        
        return rawValue
    }
}

// MARK: - Array Literal

extension DBusObjectPath: ExpressibleByArrayLiteral {
    
    public init(arrayLiteral elements: Element...) {
        
        self.init(elements)
    }
}

// MARK: - Collection

extension DBusObjectPath: MutableCollection {
    
    public typealias Index = Int
    
    public subscript (index: Index) -> Element {
     
        get { return internalReference.reference[index] }
        
        mutating set { internalReference.mutatingReference[index] = newValue }
    }
    
    public var count: Int {
        
        return internalReference.reference.count
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
    
    public func makeIterator() -> IndexingIterator<DBusObjectPath> {
        return IndexingIterator(_elements: self)
    }
    
    /// Adds a new element at the end of the object path.
    ///
    /// Use this method to append a single element to the end of a mutable object path.
    public mutating func append(_ element: Element) {
        
        internalReference.mutatingReference.append(element)
    }
    
    /// Removes and returns the first element of the object path.
    ///
    /// - Precondition: The object path must not be empty.
    @discardableResult
    public mutating func removeFirst() -> Element {
        
        return internalReference.mutatingReference.removeFirst()
    }
    
    /// Removes and returns the last element of the object path.
    ///
    /// - Precondition: The object path must not be empty.
    @discardableResult
    public mutating func removeLast() -> Element {
        
        return internalReference.mutatingReference.removeLast()
    }
    
    /// Removes and returns the element at the specified position.
    ///
    /// All the elements following the specified position are moved up to close the gap.
    @discardableResult
    public mutating func remove(at index: Int) -> Element {
        
        return internalReference.mutatingReference.remove(at: index)
    }
    
    /// Removes all elements from the object path.
    public mutating func removeAll() {
        
        self = DBusObjectPath() // initialize to singleton
    }
}

extension DBusObjectPath: RandomAccessCollection { }

// MARK: - Element

public extension DBusObjectPath {
    
    /// An element in the object path
    public struct Element: RawRepresentable {
        
        public let rawValue: String
        
        public init?(rawValue: String) {
            
            // validate string
            guard rawValue.isEmpty == false, // No element may be an empty string.
                rawValue.contains(DBusObjectPath.separator) == false, // Multiple '/' characters cannot occur in sequence.
                rawValue.rangeOfCharacter(from: Element.nonASCIICharacters) == nil // only ASCII characters "[A-Z][a-z][0-9]_"
                else { return nil }
            
            // store validated string
            self.rawValue = rawValue
        }
    }
}

private extension DBusObjectPath.Element {
    
    static let nonASCIICharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLKMNOPQRSTUVWXYZ0123456789").inverted
}

extension DBusObjectPath.Element: Equatable {
    
    public static func == (lhs: DBusObjectPath.Element, rhs: DBusObjectPath.Element) -> Bool {
        
        return lhs.rawValue == rhs.rawValue
    }
}

extension DBusObjectPath.Element: CustomStringConvertible {
    
    public var description: String {
        
        return rawValue
    }
}

extension DBusObjectPath.Element: Hashable {
    
    public var hashValue: Int {
        
        return rawValue.hashValue
    }
}
