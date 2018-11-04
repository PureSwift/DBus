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
        (testMultithread, "testMultithread")
    ]
    
    func testInvalid() {
        
        let strings = [
            "",
            """
            /com//example/
            """,
            "/com/example/ñanó",
            "/com/example/b$@s1",
            "/com/example/bus1/",
            "/com/example/😀",
            "//",
            "///",
            "\\"
        ]
                
        for string in strings {
            
            XCTAssertNil(DBusObjectPath(rawValue: string), "\(string) should be invalid")
            XCTAssertThrowsError(try DBusObjectPath.validate(string))
            do { try DBusObjectPath.validate(string) }
            catch let error as DBusError {
                XCTAssertEqual(error.name, .invalidArguments)
                print("\"\(string)\" is invalid: \(error.message)"); return
            }
            catch { XCTFail("\(error)"); return }
            XCTFail("Error expected for \(string)")
        }
    }
    
    func testValid() {
        
        let values: [(String, [String])] = [
            ("/", []),
            ("/com", ["com"]),
            ("/com/example/bus1", ["com", "example", "bus1"])
        ]
        
        for (string, elements) in values {
            
            XCTAssertNoThrow(try DBusObjectPath.validate(string))
            
            // initialize
            guard let objectPath = DBusObjectPath(rawValue: string)
                else { XCTFail("Invalid string \(string)"); return }
            
            // test underlying values
            XCTAssertEqual(objectPath.map { $0.rawValue }, elements, "Invalid elements")
            XCTAssertEqual(objectPath.rawValue, string)
            XCTAssertEqual(objectPath.description, string)
            XCTAssertEqual(objectPath.hashValue, string.hashValue)
            
            // test collection / subscripting
            XCTAssertEqual(objectPath.count, elements.count)
            objectPath.enumerated().forEach { XCTAssertEqual(elements[$0.offset], $0.element.rawValue) }
            elements.enumerated().forEach { XCTAssertEqual(objectPath[$0.offset].rawValue, $0.element) }
            
            // initialize with elements
            let elementsObjectPath = DBusObjectPath(elements.compactMap({ DBusObjectPath.Element(rawValue: $0) }))
            XCTAssertEqual(elementsObjectPath.map { $0.rawValue }, elements)
            XCTAssertEqual(Array(elementsObjectPath), elements.compactMap({ DBusObjectPath.Element(rawValue: $0) }))
            XCTAssertEqual(elementsObjectPath, objectPath)
            
            // test equality
            XCTAssertEqual(objectPath, objectPath)
            XCTAssertEqual(elementsObjectPath, elementsObjectPath)
            XCTAssertEqual(objectPath, elementsObjectPath)
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
        XCTAssertNotEqual(DBusObjectPath().rawValue, DBusObjectPath(rawValue: "/com/example")!.rawValue)
        XCTAssertNotEqual(DBusObjectPath().elements, DBusObjectPath(rawValue: "/com/example")!.elements)
        
        // don't break value semantics by modifying instance
        var mutable = DBusObjectPath()
        XCTAssertEqual(mutable, objectPath)
        mutable.append(DBusObjectPath.Element(rawValue: "mutation1")!)
        mutable.removeLast()
        XCTAssertEqual(mutable, objectPath)
        XCTAssertEqual(mutable.rawValue, objectPath.rawValue)
    }
    
    func testMultithread() {
        
        let string = "/com/example/bus1"
        
        let objectPath = DBusObjectPath([
            DBusObjectPath.Element(rawValue: "com")!,
            DBusObjectPath.Element(rawValue: "example")!,
            DBusObjectPath.Element(rawValue: "bus1")!
            ])
        
        // instance for initializing string
        let readStringCopy = objectPath
        
        // initialize string from another thread
        let queue = DispatchQueue(label: "\(#function) Queue", attributes: [.concurrent])
        let end = Date() + 0.5
        while Date() < end {
            
            for _ in 0 ..< 100 {
                
                let mutableArray = [""]

                var newObjectPath: DBusObjectPath = []
                XCTAssertEqual(newObjectPath.rawValue, "/")
                newObjectPath.append(DBusObjectPath.Element(rawValue: "example")!)
                XCTAssertEqual(newObjectPath.rawValue, "/example")
                newObjectPath.append(DBusObjectPath.Element(rawValue: "mutation")!)
                
                queue.async {
                    
                    // access variable from different threads
                    
                    // trigger lazy initialization from another thread
                    XCTAssertEqual(newObjectPath.rawValue, "/example/mutation")
                    
                    var mutableCopy1 = newObjectPath
                    var mutableCopy2 = newObjectPath
                    
                    var arrayCopy1 = mutableArray
                    var arrayCopy2 = mutableArray
                    
                    queue.async {
                        
                        mutableCopy1.append(DBusObjectPath.Element(rawValue: "1")!)
                        XCTAssertEqual(mutableCopy1.rawValue, "/example/mutation/1")
                        
                        XCTAssertEqual(arrayCopy1, [""])
                        arrayCopy1.append("1")
                        XCTAssertEqual(arrayCopy1, ["", "1"])
                    }
                    
                    queue.async {
                        
                        mutableCopy2.append(DBusObjectPath.Element(rawValue: "2")!)
                        XCTAssertEqual(mutableCopy2.rawValue, "/example/mutation/2")
                        
                        XCTAssertEqual(arrayCopy2, [""])
                        arrayCopy2.append("2")
                        XCTAssertEqual(arrayCopy2, ["", "2"])
                    }
                }
            }
            
            queue.async {
                
                XCTAssertEqual(readStringCopy.rawValue, string)
            }
            
            queue.async {
                
                var mutateCopy = readStringCopy
                mutateCopy.append(DBusObjectPath.Element(rawValue: "mutation")!)
                XCTAssertNotEqual(readStringCopy, mutateCopy)
                XCTAssertNotEqual(mutateCopy.rawValue, string)
            }
        }
        
        XCTAssertEqual(objectPath.rawValue, string)
    }
}
