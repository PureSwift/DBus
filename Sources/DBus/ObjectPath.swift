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
    internal private(set) var elements: [DBusObjectPath.Element]
    
    /// Cached string.
    /// This will be the original string the object path was created from.
    internal private(set) var string: String?
    
    /// Initialize with an array of elements.
    public init(_ elements: [Element] = []) {
        
        self.elements = elements
        self.string = String(elements)
    }
}

// MARK: - String Parsing

internal extension DBusObjectPath {
    
    static let separator = "/".first!
    
    /// Parses the object path string and returns the parsed object path.
    static func parse(_ string: String) -> [Element]? {
        
        // The path must begin with an ASCII '/' (integer 47) character,
        // and must consist of elements separated by slash characters.
        guard let firstCharacter = string.first, // cant't be empty string
            firstCharacter == separator, // must start with "/"
            string.count == 1 || string.last != separator // last character
            else { return nil }
        
        let pathStrings = string.split(separator: separator,
                                       maxSplits: .max,
                                       omittingEmptySubsequences: true)
        
        var elements = [Element]()
        elements.reserveCapacity(pathStrings.count) // pre-allocate buffer
        
        for elementString in pathStrings {
            
            guard let element = Element(substring: elementString)
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

// MARK: - RawRepresentable

extension DBusObjectPath: RawRepresentable {
    
    public init?(rawValue: String) {
        
        guard let elements = DBusObjectPath.parse(rawValue)
            else { return nil }
        
        self.elements = elements
        self.string = rawValue // store original string
    }
    
    public var rawValue: String {
        
        get { return string ?? String(elements) }
    }
}

// MARK: - Equatable

extension DBusObjectPath: Equatable {
    
    public static func == (lhs: DBusObjectPath, rhs: DBusObjectPath) -> Bool {
        
        // fast path
        if let lhsString = lhs.string,
            let rhsString = rhs.string {
            
            return lhsString == rhsString
        }
        
        // slower comparison
        return lhs.elements == rhs.elements
    }
}

// MARK: - Hashable

extension DBusObjectPath: Hashable {
    
    public var hashValue: Int {
        
        return rawValue.hashValue
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
    
    public func makeIterator() -> IndexingIterator<DBusObjectPath> {
        return IndexingIterator(_elements: self)
    }
    
    /// Adds a new element at the end of the object path.
    ///
    /// Use this method to append a single element to the end of a mutable object path.
    public mutating func append(_ element: Element) {
        
        string = nil
        elements.append(element)
    }
    
    /// Removes and returns the first element of the object path.
    ///
    /// - Precondition: The object path must not be empty.
    @discardableResult
    public mutating func removeFirst() -> Element {
        
        string = nil
        return elements.removeFirst()
    }
    
    /// Removes and returns the last element of the object path.
    ///
    /// - Precondition: The object path must not be empty.
    @discardableResult
    public mutating func removeLast() -> Element {
        
        string = nil
        return elements.removeLast()
    }
    
    /// Removes and returns the element at the specified position.
    ///
    /// All the elements following the specified position are moved up to close the gap.
    @discardableResult
    public mutating func remove(at index: Int) -> Element {
        
        string = nil
        return elements.remove(at: index)
    }
    
    /// Removes all elements from the object path.
    public mutating func removeAll() {
        
        self = DBusObjectPath()
    }
}

extension DBusObjectPath: RandomAccessCollection { }

// MARK: - Element

public extension DBusObjectPath {
    
    /// An element in the object path
    public struct Element {
        
        /// Don't copy buffer of individual elements.
        internal let substring: Substring
        
        internal init?(substring: Substring) {
            
            // validate string
            guard substring.isEmpty == false, // No element may be an empty string.
                substring.contains(DBusObjectPath.separator) == false, // Multiple '/' characters cannot occur in sequence.
                substring.rangeOfCharacter(from: Element.nonASCIICharacters) == nil // only ASCII characters "[A-Z][a-z][0-9]_"
                else { return nil }
            
            self.substring = substring
        }
    }
}

extension DBusObjectPath.Element: RawRepresentable {
    
    public init?(rawValue: String) {
        
        let substring = Substring(rawValue)
        
        self.init(substring: substring)
    }
    
    public var rawValue: String {
        
        return String(substring)
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
