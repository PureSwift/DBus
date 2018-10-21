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
        (testInvalidStrings, "testInvalidStrings"),
        (testValidStrings, "testValidStrings")
    ]
    
    func testInvalidStrings() {
        
        let strings = [
            "",
            //"//",
            //"///",
            //"\\",
            "/com/example/bus1/",
            "/com/example/ñanó"
        ]
        
        //strings.forEach { XCTAssertNil(DBusObjectPath(rawValue: $0)) }
    }
    
    func testValidStrings() {
        
        let values: [(String, [String])] = [
            ("/", []),
            ("/com/example/bus1", ["com", "example", "bus1"])
        ]
        
        for (string, elements) in values {
            
            // initialize
            guard let objectPath = DBusObjectPath(rawValue: string)
                else { XCTFail("Invalid string \(string)"); return }
            
            // test underlying values
            XCTAssertEqual(objectPath.reference.elements.map { $0.rawValue }, elements, "Invalid elements")
            XCTAssertEqual(objectPath.rawValue, string)
            
            // test collection / subscripting
            XCTAssertEqual(objectPath.count, elements.count)
            objectPath.enumerated().forEach { XCTAssertEqual(elements[$0.offset], $0.element.rawValue) }
            elements.enumerated().forEach { XCTAssertEqual(objectPath[$0.offset].rawValue, $0.element) }
            
            // initialize with elements
            //let elementsObjectPath = DBusObjectPath(elements.compactMap({ DBusObjectPath.Element(rawValue: $0) }))
        }
    }
}
