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

// MARK: - Reference Implementation

extension DBusObjectPath: ReferenceConvertible {
    
    /// Internal cache
    final class Reference: CopyableReference {
        
        /// Default value (`/`)
        internal static let `default` = Reference()
        
        /// initialize with the elements
        internal init(elements: [Element] = []) {
            
            self.elements = elements
        }
        
        /// Initialize with a string.
        internal convenience init?(string: String) {
            
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
            
            self.init(elements: elements)
            self.stringCache.write(string) // store parsed string
        }
        
        /// Parsed elements. Always initialized to this value.
        @_versioned
        internal private(set) var elements: [Element]
        
        internal fileprivate(set) subscript (index: Int) -> Element {
            
            @inline(__always)
            get { return elements[index] }
            
            @inline(__always)
            set {
                
                // set new value
                elements[index] = newValue
                
                // reset cache
                resetStringCache()
            }
        }
        
        /// Cached String value.
        private var stringCache = Atomic<String?>()
        
        /// Counter for lazy string rebuilds
        internal var lazyStringBuild = Atomic<UInt>(0)
        
        /// Resets and clears the string cache.
        ///
        /// - Note: This should only be neccesary for unique references that are reused upon mutation. 
        @inline(__always)
        private func resetStringCache() {
            
            self.stringCache.clear()
        }
        
        /// Whether the string value is internally cached
        internal var isStringCached: Bool {
            
            return stringCache.read() != nil
        }
        
        internal var copy: Reference {
            
            // initialize new instance with underlying elements
            let copy = Reference(elements: elements)
            
            // dont copy cached string, because the object is mostly likely going to be mutated
            //copy.stringCache = stringCache
            assert(copy.isStringCached == false)
            
            return copy
        }
        
        /// lazily initialized string value
        internal var string: String {
            
            guard let cache = stringCache.read() else {
                
                // lazily initialize
                let separator = String(DBusObjectPath.separator)
                let stringValue = elements.isEmpty ? separator :
                    elements.reduce("", { $0 + separator + $1.rawValue })
                
                // cache value
                stringCache.write(stringValue)
                
                // increment counter
                lazyStringBuild.write(lazyStringBuild.read() + 1)
                
                return stringValue
            }
            
            return cache
        }
        
        /// Append a new element.
        internal func append(_ element: Element) {
            
            // lazily rebuild string
            resetStringCache()
            
            // add new element
            self.elements.append(element)
        }
        
        /// Removes and returns the last element of the collection.
        ///
        /// - Precondition: The collection must not be empty.
        internal func removeLast() -> Element {
            
            // lazily rebuild string
            resetStringCache()
            
            // remove element
            return self.elements.removeLast()
        }
        
        /// Removes and returns the first element of the collection.
        ///
        /// - Precondition: The collection must not be empty.
        internal func removeFirst() -> Element {
            
            // lazily rebuild string
            resetStringCache()
            
            // remove element
            return self.elements.removeFirst()
        }
        
        
        /// Removes and returns the element at the specified position.
        ///
        /// All the elements following the specified position are moved up to close the gap.
        internal func remove(at index: Int) -> Element {
            
            // lazily rebuild string
            resetStringCache()
            
            // remove element
            return self.elements.remove(at: index)
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
        
        // fast path for structs with same reference
        guard lhs.internalReference.reference !== rhs.internalReference.reference
            else { return true }
        
        // compare values
        return lhs.internalReference.reference.elements == rhs.internalReference.reference.elements
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
        
        return internalReference.reference.elements.count
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
    
    mutating func append(_ element: Element) {
        
        internalReference.mutatingReference.append(element)
    }
    
    /// Removes and returns the first element of the collection.
    ///
    /// - Precondition: The collection must not be empty.
    @discardableResult
    mutating func removeFirst() -> Element {
        
        return internalReference.mutatingReference.removeFirst()
    }
    
    /// Removes and returns the last element of the collection.
    ///
    /// - Precondition: The collection must not be empty.
    @discardableResult
    mutating func removeLast() -> Element {
        
        return internalReference.mutatingReference.removeLast()
    }
    
    /// Removes and returns the element at the specified position.
    ///
    /// All the elements following the specified position are moved up to close the gap.
    @discardableResult
    mutating func remove(at index: Int) -> Element {
        
        return internalReference.mutatingReference.remove(at: index)
    }
    
    /// Removes all elements from the collection.
    mutating func removeAll() {
        
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
