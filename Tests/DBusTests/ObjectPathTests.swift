//
//  ObjectPathTests.swift
//  DBusTests
//
//  Created by Alsey Coleman Miller on 10/21/18.
//

import Foundation
import XCTest
@testable import DBus

final class ObjectPathTests: XCTestCase {
    
    static let allTests = [
        (testInvalid, "testInvalid"),
        (testValid, "testValid"),
        (testEmpty, "testEmpty"),
        (testCopyOnWrite, "testCopyOnWrite"),
        (testMultithread, "testMultithread")
    ]
    
    func testInvalid() {
        
        let strings = [
            "",
            "/com/example/ñanó",
            "/com/example/bus1/",
            "//",
            "///",
            "\\",
        ]
        
        strings.forEach { XCTAssertNil(DBusObjectPath(rawValue: $0)) }
    }
    
    func testValid() {
        
        let values: [(String, [String])] = [
            ("/", []),
            ("/com", ["com"]),
            ("/com/example/bus1", ["com", "example", "bus1"])
        ]
        
        for (string, elements) in values {
            
            // initialize
            guard let objectPath = DBusObjectPath(rawValue: string)
                else { XCTFail("Invalid string \(string)"); return }
            
            // test underlying values
            XCTAssert(objectPath.internalReference.reference.isStringCached)
            XCTAssertEqual(objectPath.internalReference.reference.elements.map { $0.rawValue }, elements, "Invalid elements")
            XCTAssertEqual(objectPath.rawValue, string)
            XCTAssertEqual(objectPath.description, string)
            
            // test collection / subscripting
            XCTAssertEqual(objectPath.count, elements.count)
            objectPath.enumerated().forEach { XCTAssertEqual(elements[$0.offset], $0.element.rawValue) }
            elements.enumerated().forEach { XCTAssertEqual(objectPath[$0.offset].rawValue, $0.element) }
            
            // initialize with elements
            let elementsObjectPath = DBusObjectPath(elements.compactMap({ DBusObjectPath.Element(rawValue: $0) }))
            XCTAssertEqual(elementsObjectPath.map { $0.rawValue }, elements)
            XCTAssertEqual(elementsObjectPath.internalReference.reference.elements, elements.compactMap({ DBusObjectPath.Element(rawValue: $0) }))
            XCTAssertEqual(Array(elementsObjectPath), elements.compactMap({ DBusObjectPath.Element(rawValue: $0) }))
            
            // test lazy string initialization
            XCTAssertFalse(elementsObjectPath.internalReference.reference.isStringCached)
            XCTAssertEqual(elementsObjectPath.rawValue, string)
            XCTAssert(elementsObjectPath.internalReference.reference.isStringCached)
            
            // test equality
            XCTAssertEqual(objectPath, objectPath)
            XCTAssertEqual(elementsObjectPath, elementsObjectPath)
            XCTAssertEqual(objectPath, elementsObjectPath)
            
            // test internal reference
            XCTAssert(objectPath.internalReference.reference !== DBusObjectPath.Reference.default)
            XCTAssert(objectPath.internalReference.reference !== elementsObjectPath.internalReference.reference)
            XCTAssertEqual(objectPath.internalReference.reference.elements, elementsObjectPath.internalReference.reference.elements)
            XCTAssertEqual(objectPath.internalReference.reference.string, elementsObjectPath.internalReference.reference.string)
            XCTAssertEqual(objectPath.rawValue, elementsObjectPath.rawValue)
            XCTAssertEqual(Array(objectPath), Array(elementsObjectPath))
            
            // string was never calculated / lazily initialized
            XCTAssertEqual(objectPath.internalReference.reference.lazyStringBuild.read(), 0)
        }
    }
    
    func testEmpty() {
        
        // empty object path
        let objectPath = DBusObjectPath()
        XCTAssertEqual(objectPath.internalReference.reference.lazyStringBuild.read(), 0)
        XCTAssertEqual(objectPath.rawValue, "/")
        XCTAssertEqual(objectPath.internalReference.reference.lazyStringBuild.read(), 1)
        XCTAssert(objectPath.isEmpty)
        XCTAssertEqual(objectPath, [])
        XCTAssertEqual(DBusObjectPath(), DBusObjectPath(rawValue: "/"))
        XCTAssertEqual(DBusObjectPath(), DBusObjectPath())
        XCTAssertNotEqual(DBusObjectPath(), DBusObjectPath(rawValue: "/com/example")!)
        
        // test unique reference
        XCTAssert(objectPath.internalReference.reference === DBusObjectPath.Reference.default)
        XCTAssert(objectPath.internalReference.reference === DBusObjectPath().internalReference.reference)
        XCTAssert(DBusObjectPath().internalReference.reference === DBusObjectPath().internalReference.reference)
        
        // don't break value semantics by modifying global instance
        var mutable = DBusObjectPath()
        XCTAssertEqual(mutable, objectPath)
        XCTAssert(mutable.internalReference.reference === objectPath.internalReference.reference)
        mutable.append(DBusObjectPath.Element(rawValue: "mutation1")!)
        XCTAssert(mutable.internalReference.reference !== objectPath.internalReference.reference)
        XCTAssertNotEqual(mutable, objectPath)
        mutable.removeLast()
        XCTAssertEqual(mutable, objectPath)
        XCTAssert(mutable.internalReference.reference !== objectPath.internalReference.reference)
        XCTAssertFalse(mutable.internalReference.reference.isStringCached)
        XCTAssertEqual(mutable.internalReference.reference.lazyStringBuild.read(), 0)
        XCTAssertEqual(mutable.rawValue, objectPath.rawValue)
        XCTAssert(mutable.internalReference.reference.isStringCached)
        XCTAssertEqual(mutable.internalReference.reference.lazyStringBuild.read(), 1)
        
        // string should only be calculated once
        XCTAssertEqual(DBusObjectPath.Reference.default.lazyStringBuild.read(), 1)
    }
    
    func testCopyOnWrite() {
        
        let string = "/com/example/bus1"
        
        guard var objectPath = DBusObjectPath(rawValue: string)
            else { XCTFail("Invalid string \(string)"); return }
        
        let originalReference = objectPath.internalReference.reference
        XCTAssertEqual(originalReference.lazyStringBuild.read(), 0)
        
        // mutate, should not copy (ref count == 1)
        objectPath.append(DBusObjectPath.Element(rawValue: "mutation1")!)
        XCTAssert(objectPath.internalReference.reference === originalReference, "Should use same reference")
        XCTAssertEqual(objectPath.internalReference.reference.lazyStringBuild.read(), 0)
        XCTAssertEqual(objectPath.rawValue, "/com/example/bus1/mutation1")
        XCTAssertEqual(objectPath.internalReference.reference.lazyStringBuild.read(), 1)
        
        // same instance (ref count == 2)
        var copy1 = objectPath
        XCTAssertEqual(copy1, objectPath)
        XCTAssertEqual(copy1.rawValue, objectPath.rawValue)
        XCTAssert(copy1.internalReference.reference === originalReference, "Should use same reference")
        XCTAssert(copy1.internalReference.reference === objectPath.internalReference.reference, "Should use same reference")
        XCTAssertEqual(copy1.internalReference.reference.lazyStringBuild.read(), 1)
        
        // should copy when mutating since ref is shared
        objectPath.append(DBusObjectPath.Element(rawValue: "mutation2")!)
        XCTAssertEqual(objectPath.internalReference.reference.lazyStringBuild.read(), 0)
        XCTAssertNotEqual(copy1, objectPath)
        XCTAssertNotEqual(copy1.rawValue, objectPath.rawValue)
        XCTAssertEqual(objectPath.internalReference.reference.lazyStringBuild.read(), 1)
        XCTAssert(copy1.internalReference.reference === originalReference, "Should use same reference (not mutated)")
        XCTAssert(objectPath.internalReference.reference !== originalReference, "Should not use same reference")
        XCTAssert(objectPath.internalReference.reference !== copy1.internalReference.reference, "Should not use same reference")
        
        // copy should not be unique, mutations should not copy
        copy1.append(DBusObjectPath.Element(rawValue: "mutation2")!)
        XCTAssertEqual(copy1, objectPath)
        XCTAssertEqual(copy1.internalReference.reference.lazyStringBuild.read(), 1)
        XCTAssertEqual(copy1.rawValue, objectPath.rawValue)
        XCTAssertEqual(copy1.internalReference.reference.lazyStringBuild.read(), 2)
        XCTAssert(copy1.internalReference.reference === originalReference, "Should use same reference (mutated unique)")
        XCTAssert(objectPath.internalReference.reference !== copy1.internalReference.reference, "Should not use same reference")
        
        // reset string again
        copy1.append(DBusObjectPath.Element(rawValue: "mutation3")!)
        XCTAssertNotEqual(copy1, objectPath)
        XCTAssertEqual(copy1.internalReference.reference.lazyStringBuild.read(), 2)
        XCTAssertNotEqual(copy1.rawValue, objectPath.rawValue)
        XCTAssertEqual(copy1.internalReference.reference.lazyStringBuild.read(), 3)
        XCTAssertNotEqual(copy1.rawValue, objectPath.rawValue)
        XCTAssertEqual(copy1.internalReference.reference.lazyStringBuild.read(), 3)
        
        // multiple mutations without recalculating the string value
        var mutable: DBusObjectPath = []
        let mutableReference = mutable.internalReference.reference
        XCTAssertFalse(mutableReference.isStringCached)
        XCTAssertEqual(mutableReference.lazyStringBuild.read(), 0)
        
        for i in 1 ... 100 {
            mutable.append(DBusObjectPath.Element(rawValue: "mutation\(i)")!)
        }
        
        XCTAssertFalse(mutable.isEmpty)
        XCTAssertEqual(mutable.count, 100)
        XCTAssert(mutable.internalReference.reference === mutableReference, "Should be same reference")
        XCTAssertFalse(mutableReference.isStringCached)
        XCTAssertEqual(mutableReference.lazyStringBuild.read(), 0)
        XCTAssertNotEqual(mutable.rawValue, "/")
        XCTAssert(mutable.internalReference.reference.isStringCached)
        XCTAssertEqual(mutable.internalReference.reference.lazyStringBuild.read(), 1)
        XCTAssert(mutableReference.isStringCached)
        XCTAssertEqual(mutableReference.lazyStringBuild.read(), 1)
        XCTAssertNotEqual(mutable.rawValue, "/")
        XCTAssertEqual(mutableReference.lazyStringBuild.read(), 1)
    }
    
    func testMultithread() {
        
        let string = "/com/example/bus1"
        
        let objectPath = DBusObjectPath([
            DBusObjectPath.Element(rawValue: "com")!,
            DBusObjectPath.Element(rawValue: "example")!,
            DBusObjectPath.Element(rawValue: "bus1")!
            ])
        
        let originalReference = objectPath.internalReference.reference
        
        XCTAssertFalse(originalReference.isStringCached, "String has not been calculated yet")
        XCTAssertEqual(originalReference.lazyStringBuild.read(), 0)
        
        // for initializing string
        let readStringCopy = objectPath
        
        let queue = DispatchQueue(label: "\(#function) Queue", attributes: [.concurrent])
        
        XCTAssertFalse(originalReference.isStringCached)
        
        // initialize string from another thread
        let end = Date() + 1.0
        while Date() < end {
            
            let _ = originalReference.isStringCached
            
            for _ in 0 ..< 1000 {
                
                queue.async {
                    
                    // access variable from different threads
                    let _ = originalReference.isStringCached
                }
            }
            
            queue.async {
                
                let _ = originalReference.isStringCached
                
                /// read string
                XCTAssert(readStringCopy.internalReference.reference === originalReference)
                XCTAssertEqual(readStringCopy.rawValue, string)
                XCTAssert(readStringCopy.internalReference.reference.isStringCached)
                XCTAssert(originalReference.isStringCached)
            }
            
            queue.async {
                
                let _ = originalReference.isStringCached
                
                var mutateCopy = readStringCopy
                XCTAssert(mutateCopy.internalReference.reference === originalReference)
                mutateCopy.append(DBusObjectPath.Element(rawValue: "mutation")!)
                XCTAssert(mutateCopy.internalReference.reference !== originalReference)
                XCTAssertFalse(mutateCopy.internalReference.reference.isStringCached)
                XCTAssertNotEqual(readStringCopy, mutateCopy)
                XCTAssertFalse(mutateCopy.internalReference.reference.isStringCached)
                XCTAssertNotEqual(mutateCopy.rawValue, string)
                XCTAssert(mutateCopy.internalReference.reference.isStringCached)
                XCTAssert(mutateCopy.internalReference.reference !== originalReference)
            }
        }
        
        XCTAssertEqual(objectPath.rawValue, string)
        XCTAssert(objectPath.internalReference.reference === originalReference)
        XCTAssert(originalReference.isStringCached)
        XCTAssertEqual(objectPath.internalReference.reference.lazyStringBuild.read(), 1, "Original instance should not be mutated")
    }
}
