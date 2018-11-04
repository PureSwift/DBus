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
        (testBasicValueArguments, "testBasicValueArguments"),
        (testArrayArguments, "testArrayArguments"),
        (testStructureArguments, "testStructureArguments"),
        (testErrorMessage, "testErrorMessage")
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
            .array(DBusMessageArgument.Array([.int16(1), .int16(2), .int16(3)])!),
            .array(DBusMessageArgument.Array(type: .int16, [.int16(1), .int16(2), .int16(3)])!),
            .array(DBusMessageArgument.Array(type: .int16)),
            .array(DBusMessageArgument.Array(type: .int32, [.int32(1), .int32(2), .int32(3)])!),
            .array(DBusMessageArgument.Array(type: .int32)),
            .array(DBusMessageArgument.Array(type: .string, [.string("1"), .string("2"), .string("3")])!),
            .array(DBusMessageArgument.Array(type: .string)),
            .array(DBusMessageArgument.Array(type: .objectPath, [
                .objectPath(DBusObjectPath("/com/example/bus1")),
                .objectPath(DBusObjectPath("/com/example/bus2")),
                .objectPath(DBusObjectPath("/com/example/bus3"))
                ])!),
            .array(DBusMessageArgument.Array(type: .objectPath)),
            .array(DBusMessageArgument.Array(type: .array(.string), [
                .array(DBusMessageArgument.Array(type: .string, [.string("A1"), .string("A2"), .string("A3")])!),
                .array(DBusMessageArgument.Array(type: .string, [.string("B1"), .string("B2"), .string("B3")])!),
                .array(DBusMessageArgument.Array(type: .string, [.string("C1"), .string("C2"), .string("C3")])!)
                ])!),
            .array(DBusMessageArgument.Array(type: .struct([.int32, .string]), [
                .struct(DBusMessageArgument.Structure([
                    .int32(1),
                    .string("Test String 1")
                    ])!),
                .struct(DBusMessageArgument.Structure([
                    .int32(2),
                    .string("Test String 2")
                    ])!)
                ])!)
        ]
        
        do {
            
            let message = try DBusMessage(type: .methodCall)
            try message.append(contentsOf: arguments)
            XCTAssertEqual(Array(message), arguments, "Could not iterate message")
        }
        catch { XCTFail("\(error)") }
    }
    
    func testStructureArguments() {
        
        let arguments: [DBusMessageArgument] = [
            .struct(DBusMessageArgument.Structure([
                .int32(1),
                .string("Test String")
                ])!),
            .struct(DBusMessageArgument.Structure([
                .int32(1),
                .string("Test String 1"),
                .objectPath(DBusObjectPath("/com/example/bus1")),
                .struct(DBusMessageArgument.Structure([
                    .int32(2),
                    .string("Test String 2"),
                    .objectPath(DBusObjectPath("/com/example/bus2"))
                    ])!)
                ])!)
        ]
        
        do {
            
            let message = try DBusMessage(type: .methodCall)
            try message.append(contentsOf: arguments)
            XCTAssertEqual(Array(message), arguments, "Could not iterate message")
        }
        catch { XCTFail("\(error)") }
    }
    
    func testErrorMessage() {
        
        do {
            
            let originalMessage = try DBusMessage(type: .methodCall)
            
            #if swift(>=4.2)
            originalMessage.serial = .random(in: 1 ..< .max)
            #else
            originalMessage.serial = 1 // fake it till you make it
            #endif
            
            let error = DBusError(name: .failed, message: "Test Error")
            
            let errorMessage = try DBusMessage(error: DBusMessage.Error(replyTo: originalMessage, error: error))
            
            XCTAssertEqual(DBusError(message: errorMessage), error)
            XCTAssertEqual(errorMessage.replySerial, originalMessage.serial)
        }
        catch { XCTFail("\(error)") }
    }
}
