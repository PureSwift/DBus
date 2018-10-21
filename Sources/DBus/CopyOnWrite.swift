//
//  CopyOnWrite.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 10/21/18.
//

import Foundation

internal protocol CopyableReference: class {
    
    var copy: Self { get }
}

/// Encapsulates behavior surrounding value semantics and copy-on-write behavior
/// Modified version of https://github.com/klundberg/CopyOnWrite
internal struct CopyOnWrite <Reference: CopyableReference> {
    
    /// Needed for `isKnownUniquelyReferenced`
    final class Box {
        
        let unbox: Reference
        
        @inline(__always)
        init(_ value: Reference) {
            unbox = value
        }
    }
    
    var _reference: Box
    
    /// Constructs the copy-on-write wrapper around the given reference and copy function
    ///
    /// - Parameters:
    ///   - reference: The object that is to be given value semantics
    ///   - externalRetain: Whether the object should be copied on next mutation regardless of Swift ARC uniqueness.
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
                
                // make copy
                let copy = _reference.unbox.copy
                _reference = Box(copy)
            }
            
            return _reference.unbox
        }
    }
    
    /// Helper property to determine whether the reference is uniquely held.
    /// Checks both Swift ARC and the external C manual reference count.
    internal var isUniquelyReferenced: Bool {
        @inline(__always)
        mutating get {
            return isKnownUniquelyReferenced(&_reference)
        }
    }
}
