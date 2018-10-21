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
    internal let internalReference: CopyOnWrite<Reference>
    
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
            self.stringCache = string // store parsed string
        }
        
        /// Parsed elements. Always initialized to this value.
        @_versioned
        internal private(set) var elements: [Element]
        
        /// Cached String value.
        private var stringCache: String?
        
        /// Whether the string value is internally cached
        internal var isStringCached: Bool {
            
            return stringCache != nil
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
            
            guard let cache = stringCache else {
                
                // lazily initialize
                let separator = String(DBusObjectPath.separator)
                let stringValue = elements.isEmpty ? separator :
                    elements.reduce("", { $0 + separator + $1.rawValue })
                
                // cache value
                stringCache = stringValue
                
                return stringValue
            }
            
            return cache
        }
        
        /// Append a new element.
        internal func append(_ element: Element) {
            
            // add new element
            self.elements.append(element)
            
            // lazily rebuild string
            stringCache = nil
        }
    }
}

// MARK: - Constants

internal extension DBusObjectPath {
    
    static let separator = "/".first!
}

public extension DBusObjectPath {
    
    public init() {
        
        self.init(Reference.default) // all new empty paths should point to same underlying object
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

extension DBusObjectPath: Collection {
    
    public typealias Index = Int
    
    public subscript (index: Index) -> Element {
     
        return internalReference.reference.elements[index]
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
}

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
