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
        (testValid, "testValid")
    ]
    
    func testInvalid() {
        
        let strings = [
            "",
            "/com/example/ñanó",
            "/com/example/bus1/",
            //"//",
            //"///",
            //"\\",
        ]
        
        strings.forEach { XCTAssertNil(DBusObjectPath(rawValue: $0)) }
    }
    
    func testValid() {
        
        let values: [(String, [String])] = [
            ("/", []),
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
            XCTAssert(objectPath.internalReference.reference !== elementsObjectPath.internalReference.reference)
            XCTAssertEqual(objectPath.internalReference.reference.elements, elementsObjectPath.internalReference.reference.elements)
            XCTAssertEqual(objectPath.internalReference.reference.string, elementsObjectPath.internalReference.reference.string)
            XCTAssertEqual(objectPath.rawValue, elementsObjectPath.rawValue)
            XCTAssertEqual(Array(objectPath), Array(elementsObjectPath))
        }
    }
    
    func testEmpty() {
        
        // empty object path
        let objectPath = DBusObjectPath()
        XCTAssertEqual(objectPath.rawValue, "/")
        XCTAssert(objectPath.isEmpty)
        XCTAssertEqual(objectPath, [])
        XCTAssertEqual(DBusObjectPath(), DBusObjectPath(rawValue: "/"))
        XCTAssertEqual(DBusObjectPath(), DBusObjectPath())
        XCTAssertNotEqual(DBusObjectPath(), DBusObjectPath(rawValue: "/com/example")!)
        
        // test unique reference
        XCTAssert(objectPath.internalReference.reference === DBusObjectPath.Reference.default)
        XCTAssert(objectPath.internalReference.reference === DBusObjectPath().internalReference.reference)
        XCTAssert(DBusObjectPath().internalReference.reference === DBusObjectPath().internalReference.reference)
        
    }
    
    func testCopyOnWrite() {
        
        let string = "/com/example/bus1"
        
        guard let objectPath = DBusObjectPath(rawValue: string)
            else { XCTFail("Invalid string \(string)"); return }
        
        
    }
}
