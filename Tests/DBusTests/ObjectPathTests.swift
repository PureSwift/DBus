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
            XCTAssert(objectPath.reference.isStringCached)
            XCTAssertEqual(objectPath.reference.elements.map { $0.rawValue }, elements, "Invalid elements")
            XCTAssertEqual(objectPath.rawValue, string)
            XCTAssertEqual(objectPath.description, string)
            
            // test collection / subscripting
            XCTAssertEqual(objectPath.count, elements.count)
            objectPath.enumerated().forEach { XCTAssertEqual(elements[$0.offset], $0.element.rawValue) }
            elements.enumerated().forEach { XCTAssertEqual(objectPath[$0.offset].rawValue, $0.element) }
            
            // initialize with elements
            let elementsObjectPath = DBusObjectPath(elements.compactMap({ DBusObjectPath.Element(rawValue: $0) }))
            XCTAssertEqual(elementsObjectPath.map { $0.rawValue }, elements)
            XCTAssertEqual(elementsObjectPath.reference.elements, elements.compactMap({ DBusObjectPath.Element(rawValue: $0) }))
            XCTAssertEqual(Array(elementsObjectPath), elements.compactMap({ DBusObjectPath.Element(rawValue: $0) }))
            
            // test lazy string initialization
            XCTAssertFalse(elementsObjectPath.reference.isStringCached)
            XCTAssertEqual(elementsObjectPath.rawValue, string)
            XCTAssert(elementsObjectPath.reference.isStringCached)
            
            // test equality
            XCTAssertEqual(objectPath, objectPath)
            XCTAssertEqual(elementsObjectPath, elementsObjectPath)
            XCTAssertEqual(objectPath, elementsObjectPath)
            XCTAssert(objectPath.reference !== elementsObjectPath.reference)
            XCTAssertEqual(objectPath.reference.elements, elementsObjectPath.reference.elements)
            XCTAssertEqual(objectPath.reference.string, elementsObjectPath.reference.string)
            XCTAssertEqual(objectPath.rawValue, elementsObjectPath.rawValue)
            XCTAssertEqual(Array(objectPath), Array(elementsObjectPath))
        }
    }
    
    func testMutability() {
        
        
    }
}
