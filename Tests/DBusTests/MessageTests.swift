//
//  MessageTests.swift
//  DBusTests
//
//  Created by Alsey Coleman Miller on 11/3/18.
//

import Foundation
import XCTest
@testable import DBus

final class MessageTests: XCTestCase {
    
    static let allTests = [
        (testBasicValueArguments, "testBasicValueArguments")
    ]
    
    func testBasicValueArguments() {
        
        let arguments: [DBusMessageArgument] = [
            .byte(.max),
            .boolean(true),
            .int16(.max),
            .uint16(.max),
            .int32(.max),
            .uint32(.max),
            .int64(.max),
            .uint64(.max),
            .string("Test String"),
            .objectPath(DBusObjectPath("/com/example/bus1")),
            .signature(DBusSignature("a{s(ai)}"))
        ]
        
        do {
            
            let message = try DBusMessage(type: .methodCall)
            try message.append(contentsOf: arguments)
            XCTAssertEqual(Array(message), arguments, "Could not iterate message")
        }
        
        catch { XCTFail("\(error)") }
    }
    
    func testArrayArguments() {
        
        let arguments: [DBusMessageArgument] = [
            .array(DBusMessageArgument.Array([.struct([.int32])]))
        ]
        
        do {
            
            let message = try DBusMessage(type: .methodCall)
            try message.append(contentsOf: arguments)
            //XCTAssertEqual(Array(message), arguments, "Could not iterate message")
        }
            
        catch { XCTFail("\(error)") }
    }
}
