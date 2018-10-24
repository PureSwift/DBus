//
//  InterfaceTests.swift
//  DBusTests
//
//  Created by Alsey Coleman Miller on 10/24/18.
//

import Foundation
import XCTest
@testable import DBus

final class InterfaceTests: XCTestCase {
    
    static let allTests = [
        (testInvalid, "testInvalid"),
        (testValid, "testValid")
    ]
    
    func testInvalid() {
        
        let strings = [
            "org.7-zip.Plugin",
            "com.example..MusicPlayer1.Track",
            "com.example.MusicPlayer1.Track.",
            "com.example.",
            "com.example.MusicPlayer1.Track@",
            "com.example.MusicPlayer1.Trackñ",
            "",
            "/",
            ".",
            "..",
            "com",
            "com.",
            "a.",
            "a.ñ"
        ]
        
        for string in strings {
            
            XCTAssertNil(DBusInterface(rawValue: string), "\(string) should be invalid")
            do { try DBusInterface.validate(string) }
            catch let error as DBusError {
                XCTAssertEqual(error.name, .invalidArguments)
                print(string, error)
                return
            }
            catch {
                XCTFail("\(error)")
                return
            }
            XCTFail("Error expected for \(string)")
        }
        
        XCTAssertNil(DBusInterface([]))
    }
    
    func testValid() {
        
        let values = [
            ("org._7_zip.Plugin", ["org", "_7_zip", "Plugin"]),
            ("a.b", ["a", "b"]),
            ("com.example", ["com", "example"]),
            ("com.example.MusicPlayer1", ["com", "example", "MusicPlayer1"]),
            ("com.example.MusicPlayer1.Track", ["com", "example", "MusicPlayer1", "Track"])
        ]
        
        for (string, elements) in values {
            
            XCTAssertNoThrow(try DBusInterface.validate(string))
            
            guard let interface = DBusInterface(rawValue: string)
                else { XCTFail("Could not parse \(string)"); return }
            
            XCTAssertEqual(interface.rawValue, string)
            XCTAssertEqual(interface.elements.map { $0.rawValue }, elements)
            XCTAssertEqual(Array(interface), interface.elements)
            XCTAssert(interface.count > 1)
            XCTAssertEqual(interface, DBusInterface(interface.elements))
        }
    }
}
