//
//  CollectionReference.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 10/23/18.
//

import Foundation

/// Internal Collection object that has a string representation
internal protocol StringCollectionReference: CopyableReference {
    
    associatedtype Element
    
    /// Initialize with the elements and a precalculated string.
    init(elements: [Element], string: String?)
    
    /// The underlying elements array
    var elements: [Element] { get set }
    
    var queue: DispatchQueue { get }
    
    func buildString() -> String
    
    static func parse(_ string: String) -> [Element]?
}

extension StringCollectionReference {
    
    /// Initialize with a string.
    init?(string: String) {
        
        guard let elements = Self.parse(string)
            else { return nil }
        
        self.init(elements: elements, string: string)
    }
    
    /// Initialize with the elements.
    init(elements: [Element] = []) {
        
        self.init(elements: elements, string: nil)
    }
    
    subscript (index: Int) -> Element {
        
        get { return queue.sync { [unowned self] in self.elements[index] } }
        
        set {
            
            queue.sync(flags: [.barrier]) { [unowned self] in
                
                // set new value
                self.elements[index] = newValue
                
                // reset cache
                self.resetStringCache()
            }
        }
    }
}

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
