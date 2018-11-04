import XCTest
@testable import DBusTests

XCTMain([
    testCase(InterfaceTests.allTests),
    testCase(MessageTests.allTests),
    testCase(ObjectPathTests.allTests),
    testCase(SignatureTests.allTests)
    ])
