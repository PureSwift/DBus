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
    internal let reference: Reference
    
    /// Reference type with value semantics
    internal init(reference: Reference) {
        
        self.reference = reference
    }
}

// MARK: - Reference Implementation

internal extension DBusObjectPath {
    
    /// Internal cache
    final class Reference {
        
        /// initialize with the elements
        internal init(elements: [Element] = []) {
            
            self.elements = elements
        }
        
        /// Initialize with a string.
        internal convenience init?(string: String) {
            
            // The path must begin with an ASCII '/' (integer 47) character,
            // and must consist of elements separated by slash characters.
            guard let firstCharacter = string.first,
                firstCharacter == DBusObjectPath.separator
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
        internal let elements: [Element]
        
        /// Cached String value.
        private var stringCache: String?
        
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
    }
}

// MARK: - Constants

internal extension DBusObjectPath {
    
    static let separator = "/".first!
}

public extension DBusObjectPath {
    
    public init() {
        
        self.init(reference: Reference())
    }
    
    /// Initialize with an array of elements.
    public init(_ elements: [Element]) {
        
        let reference = Reference(elements: elements)
        self.init(reference: reference)
    }
    
    /// Initialize with a variable argument list of elements.
    public init(_ elements: Element...) {
        
        let reference = Reference(elements: elements)
        self.init(reference: reference)
    }
    
    /// Initialize with a sequence of elements.
    public init <S: Sequence> (_ sequence: S) where S.Element == Element {
        
        let reference = Reference(elements: Array(sequence))
        self.init(reference: reference)
    }
}

// MARK: - RawRepresentable

extension DBusObjectPath: RawRepresentable {
    
    public init?(rawValue: String) {
        
        guard let reference = Reference(string: rawValue)
            else { return nil }
        
        self.init(reference: reference)
    }
    
    public var rawValue: String {
        
        get { return reference.string }
    }
}

// MARK: - Equatable

extension DBusObjectPath: Equatable {
    
    public static func == (lhs: DBusObjectPath, rhs: DBusObjectPath) -> Bool {
        
        // fast path for structs with same reference
        guard lhs.reference !== rhs.reference
            else { return true }
        
        // compare values
        return lhs.reference.elements == rhs.reference.elements
    }
}

// MARK: - Hashable

extension DBusObjectPath: Hashable {
    
    public var hashValue: Int {
        
        return reference.string.hashValue
    }
}

// MARK: - CustomStringConvertible

extension DBusObjectPath: CustomStringConvertible {
    
    public var description: String {
        
        return rawValue
    }
}

// MARK: - Collection

extension DBusObjectPath: Collection {
    
    public typealias Index = Int
    
    public subscript (index: Index) -> Element {
     
        return reference.elements[index]
    }
    
    public var count: Int {
        return reference.elements.count
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
