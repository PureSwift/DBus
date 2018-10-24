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
            "a."
        ]
        
        strings.forEach {
            XCTAssertNil(DBusInterface(rawValue: $0), "\($0) should be invalid")
            do { try DBusInterface.validate($0) }
            catch { print($0, error); return }
            XCTFail("Error expected for \($0)")
        }
    }
    
    func testValid() {
        
        let values = [
            ("a.b", ["a", "b"]),
            ("com.example.Music1", ["com", "example", "Music1"]),
            ("com.example", ["com", "example"]),
            ("com.example.MusicPlayer1.Track", ["com", "example", "MusicPlayer1", "Track"])
        ]
        
        for (string, elements) in values {
            
            XCTAssertNoThrow(try DBusInterface.validate(string))
            
            guard let interface = DBusInterface(rawValue: string)
                else { XCTFail("Could not parse \(string)"); return }
            
            XCTAssertEqual(interface.rawValue, string)
            XCTAssertEqual(interface.elements.map { $0.rawValue }, elements)
        }
    }
}
