//
//  CollectionReference.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 10/23/18.
//

import Foundation

internal protocol StringCollectionElement: Equatable {
    
    static func parse(_ string: String) -> [Self]?
    
    static func string(for elements: [Self]) -> String
}

/// Internal Collection object that has a string representation
internal final class StringCollection <Element: StringCollectionElement> : CopyableReference {
    
    /// The underlying elements array.
    private var elements: [Element]
    
    /// Access queue for thread safety
    private let queue = DispatchQueue(label: "StringCollection Storage Queue", qos: .default, attributes: [.concurrent])
    
    /// Initialize with the elements and a precalculated string.
    private init(elements: [Element], string: String?) {
        
        self.elements = elements
        self.stringCache = string
    }
    
    /// Initialize with the elements.
    internal convenience init(elements: [Element] = []) {
        
        self.init(elements: elements, string: nil)
    }
    
    /// Initialize with a string.
    internal convenience init?(string: String) {
        
        guard let elements = Element.parse(string)
            else { return nil }
        
        self.init(elements: elements, string: string)
    }
    
    internal subscript (index: Int) -> Element {
        
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
    
    internal var copy: StringCollection<Element> {
        
        return queue.sync { [unowned self] in StringCollection<Element>(elements: self.elements) }
    }
    
    /// Whether the string value is internally cached
    internal var isStringCached: Bool {
        
        return queue.sync { [unowned self] in self.stringCache != nil }
    }
        
    /// lazily initialize string value
    internal var string: String {
        
        guard let cache = queue.sync(execute: { [unowned self] in self.stringCache }) else {
            
            return queue.sync(flags: [.barrier]) { [unowned self] in
                
                // lazily initialize
                let stringValue = Element.string(for: self.elements)
                
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
    
    /// Resets and clears the string cache.
    ///
    /// - Note: This should only be neccesary for unique references that are reused upon mutation.
    ///
    /// - Precondition: Only call from access queue blocks.
    @inline(__always)
    private func resetStringCache() {
        
        self.stringCache = nil
    }
    
    internal var count: Int {
        
        return queue.sync { [unowned self] in self.elements.count }
    }
    
    /// Compare equality and identity
    internal func isEqual(to other: StringCollection<Element>) -> Bool {
        
        // fast path for same instance
        guard self !== other else { return true }
        
        // compare values
        let lhsElements = self.queue.sync { [unowned self] in self.elements }
        let rhsElements = other.queue.sync { other.elements }
        
        return lhsElements == rhsElements
    }
    
    /// Adds a new element at the end of the collection.
    ///
    /// Use this method to append a single element to the end of a mutable collection.
    internal func append(_ element: Element) {
        
        queue.sync(flags: [.barrier]) { [unowned self] in
            
            // lazily rebuild string
            resetStringCache()
            
            // add new element
            self.elements.append(element)
        }
    }
    
    /// Removes and returns the last element of the collection.
    ///
    /// - Precondition: The collection must not be empty.
    internal func removeLast() -> Element {
        
        return queue.sync(flags: [.barrier]) { [unowned self] in
            
            // lazily rebuild string
            resetStringCache()
            
            // remove element
            return self.elements.removeLast()
        }
    }
    
    /// Removes and returns the first element of the collection.
    ///
    /// - Precondition: The collection must not be empty.
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
