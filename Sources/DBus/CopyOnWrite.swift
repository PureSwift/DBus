//
//  CopyOnWrite.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 10/21/18.
//

import Foundation

/// Swift struct wrapper for copyable object.
internal protocol ReferenceConvertible {
    
    /// Underlying reference type.
    associatedtype Reference: CopyableReference
    
    /// Reference to underlying object.
    var internalReference: CopyOnWrite<Reference> { get }
    
    /// Initialized with internal reference.
    init(_ internalReference: CopyOnWrite<Reference>)
}

internal extension ReferenceConvertible {
    
    /// Initializes with a new reference.
    init(_ reference: Reference) {
        
        self.init(CopyOnWrite(reference))
    }
}

/// A copyable object
internal protocol CopyableReference: class {
    
    /// Clone the current object. 
    var copy: Self { get }
}

/// Encapsulates behavior surrounding value semantics and copy-on-write behavior
internal struct CopyOnWrite <Reference: CopyableReference> {
    
    /// Needed for `isKnownUniquelyReferenced`
    final class Box {
        
        let unbox: Reference
        
        @inline(__always)
        init(_ value: Reference) {
            unbox = value
        }
    }
    
    /// Box object whose reference count is checked for uniqueness.
    @_versioned
    internal var _reference: Box
    
    /// The reference is already retained externally (e.g. C manual reference count, singleton instance)
    /// and should be copied on first mutation regardless of Swift ARC uniqueness.
    private(set) var externalRetain: Bool
    
    /// Constructs the copy-on-write wrapper around the given reference.
    ///
    /// - Parameters:
    ///   - reference: The object that is to be given value semantics
    ///   - externalRetain: Whether the object should be copied on next mutation regardless of Swift ARC uniqueness.
    @inline(__always)
    init(_ reference: Reference, externalRetain: Bool = false) {
        self._reference = Box(reference)
        self.externalRetain = externalRetain
    }
    
    /// Returns the reference meant for read-only operations.
    var reference: Reference {
        @inline(__always)
        get {
            return _reference.unbox
        }
    }
    
    /// Returns the reference meant for mutable operations.
    ///
    /// If necessary, the reference is copied before returning, in order to preserve value semantics.
    var mutatingReference: Reference {
        
        mutating get {
            
            // copy the reference if multiple structs are backed by the reference
            if isUniquelyReferenced == false {
                
                // make copy of underlying reference object (not box used for ARC)
                let copy = _reference.unbox.copy
                _reference = Box(copy)
                externalRetain = false // reset, because new unique instance
            }
            
            return _reference.unbox
        }
    }
    
    /// Helper property to determine whether the reference is uniquely held.
    internal var isUniquelyReferenced: Bool {
        @inline(__always)
        mutating get {
            return isKnownUniquelyReferenced(&_reference) && externalRetain == false // check ARC reference count of box object
        }
    }
}
