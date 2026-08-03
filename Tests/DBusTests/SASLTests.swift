//
//  SASLTests.swift
//  DBusTests
//

import Testing
@testable import DBus

/// The SASL handshake is a pure state machine, so it is driven here without a socket.
@Suite struct SASLTests {

    private func string(_ bytes: [UInt8]) -> String {

        return String(decoding: bytes, as: UTF8.self)
    }

    @Test func hexEncoding() {

        // The EXTERNAL credential is the uid as ASCII decimal, hex encoded.
        #expect("1000".hexEncodedASCII == "31303030")
        #expect("0".hexEncodedASCII == "30")
        #expect("".hexEncodedASCII == "")
    }

    @Test func externalSuccess() throws {

        var client = DBusSASLClient(userID: 1000)

        let start = client.start()

        // The handshake opens with a single NUL byte before the first command.
        #expect(start.first == 0x00)
        #expect(string(Array(start.dropFirst())) == "AUTH EXTERNAL 31303030\r\n")

        let afterOK = try client.handle(.ok("1234deadbeef"))
        #expect(string(afterOK ?? []) == "NEGOTIATE_UNIX_FD\r\n")
        #expect(client.serverGUID == "1234deadbeef")
        #expect(!client.isReady)

        let afterAgree = try client.handle(.agreeUnixFD)
        #expect(string(afterAgree ?? []) == "BEGIN\r\n")
        #expect(client.unixFileDescriptorsSupported)
        #expect(client.isReady)
    }

    @Test func unixFileDescriptorRefusalIsNotFatal() throws {

        var client = DBusSASLClient(userID: 1000)
        _ = client.start()
        _ = try client.handle(.ok("guid"))

        // A server without fd support answers ERROR; the handshake still completes.
        let afterError = try client.handle(.error("not supported"))
        #expect(string(afterError ?? []) == "BEGIN\r\n")
        #expect(!client.unixFileDescriptorsSupported)
        #expect(client.isReady)
    }

    @Test func fallsBackToAnonymous() throws {

        var client = DBusSASLClient(mechanisms: [.external, .anonymous], userID: 1000)
        _ = client.start()

        let next = try client.handle(.rejected(["ANONYMOUS", "DBUS_COOKIE_SHA1"]))
        #expect(string(next ?? []).hasPrefix("AUTH ANONYMOUS "))

        _ = try client.handle(.ok("guid"))
        _ = try client.handle(.agreeUnixFD)
        #expect(client.isReady)
    }

    @Test func rejectsWhenNoMechanismIsShared() throws {

        var client = DBusSASLClient(mechanisms: [.external], userID: 1000)
        _ = client.start()

        let error = try #require(throws: DBusProtocolError.self) {
            try client.handle(.rejected(["DBUS_COOKIE_SHA1"]))
        }

        guard case .authenticationRejected = error
            else { Issue.record("Wrong error \(error)"); return }

        #expect(client.state == .failed)
    }

    @Test func skipsMechanismTheServerDoesNotOffer() throws {

        var client = DBusSASLClient(mechanisms: [.external, .anonymous], userID: 0)
        _ = client.start()

        // The server offers only EXTERNAL, which just failed, so there is nothing left.
        #expect(throws: (any Error).self) { try client.handle(.rejected(["EXTERNAL"])) }
    }

    @Test func errorDuringAuthenticationFails() throws {

        var client = DBusSASLClient(userID: 1000)
        _ = client.start()

        #expect(throws: (any Error).self) { try client.handle(.error("go away")) }
        #expect(client.state == .failed)
    }

    @Test func withoutFileDescriptorNegotiation() throws {

        var client = DBusSASLClient(userID: 1000, negotiateUnixFileDescriptors: false)
        _ = client.start()

        let afterOK = try client.handle(.ok("guid"))
        #expect(string(afterOK ?? []) == "BEGIN\r\n")
        #expect(client.isReady)
    }

    // MARK: - Response parsing

    @Test func responseParsing() throws {

        #expect(try DBusSASLResponse(line: "OK 1234") == .ok("1234"))
        #expect(try DBusSASLResponse(line: "AGREE_UNIX_FD") == .agreeUnixFD)
        #expect(try DBusSASLResponse(line: "REJECTED EXTERNAL ANONYMOUS")
                == .rejected(["EXTERNAL", "ANONYMOUS"]))
        #expect(try DBusSASLResponse(line: "ERROR some text here") == .error("some text here"))
        #expect(try DBusSASLResponse(line: "DATA cafe") == .data("cafe"))

        #expect(throws: (any Error).self) { try DBusSASLResponse(line: "") }
        #expect(throws: (any Error).self) { try DBusSASLResponse(line: "NONSENSE") }
    }

    // MARK: - Line buffer

    @Test func lineBuffer() throws {

        var buffer = DBusSASLLineBuffer()

        // A line split across two reads.
        buffer.append(Array("OK 12".utf8))
        #expect(try buffer.next() == nil)

        buffer.append(Array("34\r\nAGREE_UNIX_FD\r\n".utf8))
        #expect(try buffer.next() == "OK 1234")
        #expect(try buffer.next() == "AGREE_UNIX_FD")
        #expect(try buffer.next() == nil)
        #expect(buffer.remainder.isEmpty)
    }

    /// Bytes after the final CRLF are the start of the message stream, not part of the handshake.
    @Test func lineBufferKeepsRemainder() throws {

        var buffer = DBusSASLLineBuffer()
        buffer.append(Array("OK 1234\r\n".utf8) + [0x6C, 0x01, 0x00, 0x01])

        #expect(try buffer.next() == "OK 1234")
        #expect(try buffer.next() == nil)
        #expect(buffer.remainder == [0x6C, 0x01, 0x00, 0x01])
    }

    @Test func lineBufferRejectsOverlongLine() {

        var buffer = DBusSASLLineBuffer()
        buffer.append(Array(repeating: 0x41, count: DBusSASLLineBuffer.maximumLineLength + 1))

        #expect(throws: (any Error).self) { try buffer.next() }
    }
}
