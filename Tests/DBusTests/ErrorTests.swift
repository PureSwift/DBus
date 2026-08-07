//
//  ErrorTests.swift
//  DBus
//
//  Created by Tabor Kelly on 1/28/19.
//  Copyright © 2019 PureSwift. All rights reserved.
//

import Foundation
import XCTest
@testable import DBus

final class ErrorTests: XCTestCase {

    static let allTests = [
        ("testNewGoodError", testNewGoodError),
        ("testBadErrorThrows", testBadErrorThrows),
    ]

    func testNewGoodError() {
        do {
            let name = "org.freedesktop.DBus.Error.InvalidArgs"
            let message = "Foo!"
            let e = try DBusError(name: name, message: message)
            XCTAssertEqual(name, e.name)
            XCTAssertEqual(message, e.message)
            // let r = e.Reference()
        } catch {
            XCTFail("\(error)")
        }
    }

    func testBadErrorThrows() {
        XCTAssertThrowsError(try DBusError(name: ".foo", message: "nobody loves buggy code"))
    }
}
