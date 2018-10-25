//
//  SignatureTests.swift
//  DBusTests
//
//  Created by Alsey Coleman Miller on 10/22/18.
//

import Foundation
import XCTest
@testable import DBus

final class SignatureTests: XCTestCase {
    
    static let allTests = [
        (testInvalid, "testInvalid"),
        (testValid, "testValid")
    ]
    
    func testInvalid() {
        
        let strings = [
            "aa",
            "(ii",
            "ii)",
            //"()",
            "a",
            "test",
            "(ii)(ii) (ii)",
            "{si}",
            "a{i}",
            "v{i}",
            "a{s}",
            "a{(i)a}",
            "a{vs}"
        ]
        
        for string in strings {
            
            XCTAssertNil(DBusSignature(rawValue: string), "\(string) should be invalid")
            do { try DBusSignature.validate(string) }
            catch let error as DBusError {
                XCTAssertEqual(error.name, .invalidSignature)
                print(string, error); return
            }
            catch { XCTFail("\(error)"); return }
            XCTFail("Error expected for \(string)")
        }
    }
    
    func testValid() {
        
        let values: [(String, DBusSignature)] = [
            ("", []),
            ("s", [.string]),
            ("v", [.variant]),
            ("i", [.int32]),
            ("ii", [.int32, .int32]),
            ("aiai", [.array(.int32), .array(.int32)]),
            ("(i)", [.struct([.int32])]),
            ("(ii)", [.struct([.int32, .int32])]),
            ("(aii)", [.struct([.array(.int32), .int32])]),
            ("ai(i)", [.array(.int32), .struct([.int32])]),
            ("a(i)", [.array(.struct([.int32]))]),
            ("(ii)(ii)", [.struct([.int32, .int32]), .struct([.int32, .int32])]),
            ("(ii)(ii)(ii)", [.struct([.int32, .int32]), .struct([.int32, .int32]), .struct([.int32, .int32])]),
            ("a{si}", [.dictionary(DBusSignature.DictionaryType(key: .string, value: .int32)!)]),
            ("a{is}", [.dictionary(DBusSignature.DictionaryType(key: .int32, value: .string)!)]),
            ("a{s(ai)}", [.dictionary(DBusSignature.DictionaryType(key: .string, value: .struct([.array(.int32)]))!)]),
            ("a{sai}", [.dictionary(DBusSignature.DictionaryType(key: .string, value: .array(.int32))!)]),
            ("a{sv}", [.dictionary(DBusSignature.DictionaryType(key: .string, value: .variant)!)])
        ]
        
        for (string, expectedSignature) in values {
            
            XCTAssertNoThrow(try DBusSignature.validate(string))
            
            guard let signature = DBusSignature(rawValue: string)
                else { XCTFail("Could not parse string \(string)"); continue }
            
            XCTAssertEqual(signature, expectedSignature)
            XCTAssertEqual(signature.rawValue, string)
            XCTAssertEqual(signature.string, string)
            XCTAssertEqual(signature.elements, expectedSignature.elements)
            XCTAssertEqual(Array(signature), Array(expectedSignature))
            
            var mutable = signature
            mutable.append(.double)
            XCTAssertNil(mutable.string)
            XCTAssertNotEqual(mutable, signature)
            XCTAssertNotEqual(mutable.rawValue, signature.rawValue)
            XCTAssertNotEqual(mutable.elements, signature.elements)
        }
    }
}
