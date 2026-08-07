//
//  CookieAuthTests.swift
//  DBusTests
//

import Testing
@testable import DBus

@Suite struct SHA1Tests {

    /// Vectors from RFC 3174 and the usual reference set.
    @Test(arguments: [
        ("", "da39a3ee5e6b4b0d3255bfef95601890afd80709"),
        ("abc", "a9993e364706816aba3e25717850c26c9cd0d89d"),
        ("a", "86f7e437faa5a7fce15d1ddcb9eaeaea377667b8"),
        ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
         "84983e441c3bd26ebaae4aa1f95129e5e54670f1"),
        ("The quick brown fox jumps over the lazy dog",
         "2fd4e1c67a2d28fced849ee1bb76e7391b93eb12"),
        ("The quick brown fox jumps over the lazy cog",
         "de9f2c7fd25e1b3afad3e85a0bd17d9b100db4b3")
    ])
    func knownVectors(input: String, expected: String) {

        #expect(SHA1.hexDigest(input) == expected)
    }

    /// One million 'a' characters, the RFC's long test case, which exercises multi-block
    /// processing and the 64 bit length field.
    @Test func millionCharacters() {

        let digest = SHA1.hash(repeatElement(UInt8(ascii: "a"), count: 1_000_000))

        #expect(digest.hexEncoded == "34aa973cd4c4daa4f61eeb2bdbad27316534016f")
    }

    /// A message whose length lands exactly on a block boundary forces an extra padding block.
    @Test(arguments: [55, 56, 57, 63, 64, 65, 119, 120, 128])
    func paddingBoundaries(length: Int) {

        let input = String(repeating: "a", count: length)

        // Incremental and one-shot hashing must agree.
        var incremental = SHA1()
        for byte in input.utf8 {
            incremental.update([byte])
        }

        #expect(incremental.finalize().hexEncoded == SHA1.hexDigest(input))
    }

    @Test func hexRoundTrip() {

        #expect([0x00, 0x0F, 0xFF].hexEncoded == "000fff")
        #expect("000fff".hexDecoded == [0x00, 0x0F, 0xFF])
        #expect("DEADBEEF".hexDecoded == [0xDE, 0xAD, 0xBE, 0xEF]) // uppercase accepted
        #expect("1234".hexDecodedString == "\u{12}\u{34}")

        #expect("abc".hexDecoded == nil) // odd length
        #expect("zz".hexDecoded == nil) // not hex
    }
}

// MARK: - Keyring

@Suite struct KeyringTests {

    @Test func parsesCookieLines() {

        let keyring = DBusKeyring(cookies: DBusKeyring.parse("""
            1234 1700000000 deadbeef
            5678 1700000001 cafebabe
            """))

        #expect(keyring.cookies.count == 2)
        #expect(keyring.cookie(for: "1234")?.value == "deadbeef")
        #expect(keyring.cookie(for: "5678")?.creationTime == 1_700_000_001)
        #expect(keyring.cookie(for: "9999") == nil)
    }

    /// A malformed line must be skipped rather than discarding the whole keyring.
    @Test func skipsMalformedLines() {

        let keyring = DBusKeyring(cookies: DBusKeyring.parse("""
            garbage
            1234 notanumber deadbeef
            5678 1700000001 cafebabe

            """))

        #expect(keyring.cookies.count == 1)
        #expect(keyring.cookie(for: "5678")?.value == "cafebabe")
    }

    /// The context names a file under the keyring directory and arrives from the peer, so it
    /// must not be able to escape that directory.
    @Test(arguments: [
        "../../etc/passwd",
        "..",
        "a/b",
        "",
        "with space",
        "dot.dot"
    ])
    func rejectsUnsafeContext(context: String) {

        #expect(!DBusKeyring.isValidContext(context), "\(context) should be rejected")

        #expect(throws: (any Error).self) {
            try DBusKeyring.load(context: context, homeDirectory: "/tmp")
        }
    }

    @Test(arguments: ["org_freedesktop_general", "abc", "A-1_b"])
    func acceptsSafeContext(context: String) {

        #expect(DBusKeyring.isValidContext(context))
    }

    @Test func missingHomeDirectoryFails() {

        #expect(throws: (any Error).self) {
            try DBusKeyring.load(context: "general", homeDirectory: nil)
        }
    }
}

// MARK: - Cookie handshake

@Suite struct CookieAuthTests {

    /// A keyring loader that returns a fixed cookie, so the exchange can be driven without
    /// touching the real home directory.
    private static let cookie = DBusKeyring.Cookie(identifier: "3138363234",
                                                   creationTime: 1_700_000_000,
                                                   value: "5150714f6c6c6f6e")

    private func client(mechanisms: [DBusAuthenticationMechanism] = [.cookieSHA1]) -> DBusSASLClient {

        return DBusSASLClient(
            mechanisms: mechanisms,
            userID: 1000,
            userName: "coleman",
            keyringLoader: { context in
                guard context == "org_freedesktop_general"
                    else { throw DBusProtocolError.authenticationFailed("No such context") }
                return DBusKeyring(cookies: [CookieAuthTests.cookie])
            }
        )
    }

    private func string(_ bytes: [UInt8]) -> String {

        return String(decoding: bytes, as: UTF8.self)
    }

    /// The digest is computed over the *textual* hex forms joined with colons, not the decoded
    /// bytes. This vector is checked against an independent SHA-1 of the same string.
    @Test func digestShape() {

        let digest = DBusCookieChallenge.digest(serverChallenge: "aaaa",
                                                clientChallenge: "bbbb",
                                                cookie: "cccc")

        #expect(digest == SHA1.hexDigest("aaaa:bbbb:cccc"))
        #expect(digest.count == 40)
    }

    @Test func challengeParsing() throws {

        let parsed = try DBusCookieChallenge.parse("org_freedesktop_general 3138363234 7ab8f1")

        #expect(parsed.context == "org_freedesktop_general")
        #expect(parsed.identifier == "3138363234")
        #expect(parsed.challenge == "7ab8f1")

        #expect(throws: (any Error).self) { try DBusCookieChallenge.parse("too few") }
        #expect(throws: (any Error).self) { try DBusCookieChallenge.parse("a b c d") }
    }

    @Test func clientChallengeIsRandomHex() {

        let first = DBusCookieChallenge.clientChallenge()
        let second = DBusCookieChallenge.clientChallenge()

        #expect(first.count == 32)
        #expect(first.hexDecoded != nil)
        #expect(first != second, "The challenge must not repeat")
    }

    @Test func authCommandSendsHexUserName() {

        var client = self.client()
        let start = client.start()

        #expect(start.first == 0x00)
        #expect(string(Array(start.dropFirst())) == "AUTH DBUS_COOKIE_SHA1 636f6c656d616e\r\n")
        #expect("coleman".hexEncodedASCII == "636f6c656d616e")
    }

    /// The full exchange: challenge in, response out, then OK.
    @Test func completesCookieExchange() throws {

        var client = self.client()
        _ = client.start()

        let serverChallenge = "7ab8f1c93de0"
        let challengeText = "org_freedesktop_general 3138363234 \(serverChallenge)"

        let response = try #require(try client.handle(.data(challengeText.hexEncodedASCII)))

        let line = string(response)
        #expect(line.hasPrefix("DATA "))
        #expect(line.hasSuffix("\r\n"))

        // Sliced from the bytes rather than the String: CR LF is a single Swift `Character`,
        // so `dropLast(2)` on the string would also drop a hex digit.
        #expect(response.suffix(2) == [0x0D, 0x0A])
        let hex = string(Array(response.dropFirst("DATA ".utf8.count).dropLast(2)))
        let decoded = try #require(hex.hexDecodedString)

        let fields = decoded.split(separator: " ")
        #expect(fields.count == 2)

        let clientChallenge = String(fields[0])
        let digest = String(fields[1])

        #expect(clientChallenge == client.clientChallenge)
        #expect(digest == DBusCookieChallenge.digest(serverChallenge: serverChallenge,
                                                     clientChallenge: clientChallenge,
                                                     cookie: CookieAuthTests.cookie.value))

        // The server accepts, and the handshake proceeds as usual.
        let afterOK = try client.handle(.ok("guid"))
        #expect(string(afterOK ?? []) == "NEGOTIATE_UNIX_FD\r\n")
    }

    /// An unknown cookie must cancel the exchange rather than throw, so the server can offer
    /// another mechanism.
    @Test func unknownCookieCancels() throws {

        var client = self.client()
        _ = client.start()

        let challenge = "org_freedesktop_general 9999 7ab8f1"
        let response = try client.handle(.data(challenge.hexEncodedASCII))

        #expect(string(response ?? []) == "CANCEL\r\n")
        #expect(client.state == .authenticating(.cookieSHA1))
    }

    @Test func unreadableKeyringCancels() throws {

        var client = self.client()
        _ = client.start()

        let challenge = "some_other_context 3138363234 7ab8f1"
        let response = try client.handle(.data(challenge.hexEncodedASCII))

        #expect(string(response ?? []) == "CANCEL\r\n")
    }

    @Test func malformedChallengeCancels() throws {

        var client = self.client()
        _ = client.start()

        #expect(string(try client.handle(.data("not hex!")) ?? []) == "CANCEL\r\n")
        #expect(string(try client.handle(.data("6162".self)) ?? []) == "CANCEL\r\n") // "ab", too few fields
    }

    /// EXTERNAL is still preferred; the cookie mechanism is a fallback.
    @Test func fallsBackFromExternalToCookie() throws {

        var client = self.client(mechanisms: [.external, .cookieSHA1, .anonymous])
        _ = client.start()

        let next = try #require(try client.handle(.rejected(["DBUS_COOKIE_SHA1", "ANONYMOUS"])))
        #expect(string(next).hasPrefix("AUTH DBUS_COOKIE_SHA1 "))
        #expect(client.state == .authenticating(.cookieSHA1))
    }

    /// A DATA challenge for a mechanism that has no challenge/response step is a protocol error.
    @Test func dataForNonCookieMechanismCancels() throws {

        var client = self.client(mechanisms: [.external])
        _ = client.start()

        #expect(string(try client.handle(.data("00")) ?? []) == "CANCEL\r\n")
        #expect(client.state == .failed)
    }
}
