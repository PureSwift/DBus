//
//  CopyOnWrite.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 10/21/18.
//

import Foundation

/// Swift struct wrapper for copyable object.
internal protocol ReferenceConvertible {
    
    associatedtype Reference: CopyableReference
    
    var internalReference: CopyOnWrite<Reference> { get }
    
    init(_ internalReference: CopyOnWrite<Reference>)
}

/// A copyable object
internal protocol CopyableReference: class {
    
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
    
    /// Constructs the copy-on-write wrapper around the given reference.
    ///
    /// - Parameters:
    ///   - reference: The object that is to be given value semantics
    @inline(__always)
    init(_ reference: Reference) {
        self._reference = Box(reference)
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
            }
            
            return _reference.unbox
        }
    }
    
    /// Helper property to determine whether the reference is uniquely held.
    internal var isUniquelyReferenced: Bool {
        @inline(__always)
        mutating get {
            return isKnownUniquelyReferenced(&_reference) // check ARC reference count of box
        }
    }
}
