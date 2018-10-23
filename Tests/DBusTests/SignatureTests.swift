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
            "",
            "aa",
            "(ii",
            "ii)",
            "()",
            "a",
            "test"
        ]
        
        strings.forEach { XCTAssertNil(DBusSignature(rawValue: $0)) }
    }
    
    func testValid() {
        
        let values: [(String, DBusSignature)] = [
            ("i", [.int32]),
            ("ii", [.int32, .int32]),
            ("aiai", [.array(.int32), .array(.int32)]),
            ("(ii)(ii)", [.struct([.int32]), .struct([.int32])])
        ]
        
        for (string, expectedSignature) in values {
            
            guard let signature = DBusSignature(rawValue: string)
                else { XCTFail("Could not parse string \(string)"); continue }
            
            XCTAssertEqual(signature, expectedSignature)
            XCTAssertEqual(signature.rawValue, string)
            XCTAssertEqual(signature.elements, expectedSignature.elements)
        }
    }
}
