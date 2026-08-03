//
//  MarshalTests.swift
//  DBusTests
//

import Testing
@testable import DBus

/// Tests for the wire format: alignment, padding, length prefixes and byte order.
///
/// Round-trip tests alone cannot catch a marshaller that is self-consistently wrong, so the
/// byte-level tests here assert exact output computed by hand from the specification.
///
/// Reference: https://dbus.freedesktop.org/doc/dbus-specification.html#message-protocol-marshaling
@Suite struct MarshalTests {

    // MARK: - Helpers

    private func encode(_ arguments: [DBusMessageArgument],
                        endianness: DBusEndianness = .little) throws -> [UInt8] {

        return try DBusMarshaller.marshal(arguments, endianness: endianness)
    }

    private func decode(_ bytes: [UInt8],
                        _ signature: DBusSignature,
                        endianness: DBusEndianness = .little) throws -> [DBusMessageArgument] {

        var unmarshaller = DBusUnmarshaller(bytes: bytes, endianness: endianness)
        let arguments = try unmarshaller.read(signature: signature)
        #expect(unmarshaller.isAtEnd, "\(unmarshaller.remaining) trailing bytes")
        return arguments
    }

    /// Encode and decode in both byte orders and check the value survives.
    private func assertRoundTrip(_ arguments: [DBusMessageArgument],
                                 sourceLocation: SourceLocation = #_sourceLocation) throws {

        for endianness in DBusEndianness.allCases {

            let bytes = try encode(arguments, endianness: endianness)
            let decoded = try decode(bytes, arguments.signature, endianness: endianness)

            #expect(decoded == arguments, "\(endianness)", sourceLocation: sourceLocation)
        }
    }

    // MARK: - Byte level

    @Test func stringBytes() throws {

        // A STRING is a UINT32 length, the UTF-8 bytes, then a NUL. The length excludes the NUL.
        #expect(try encode([.string("foo")]) == [0x03, 0x00, 0x00, 0x00, 0x66, 0x6F, 0x6F, 0x00])
        #expect(try encode([.string("")]) == [0x00, 0x00, 0x00, 0x00, 0x00])

        // Big endian differs only in the length prefix.
        #expect(try encode([.string("foo")], endianness: .big)
                == [0x00, 0x00, 0x00, 0x03, 0x66, 0x6F, 0x6F, 0x00])
    }

    @Test func signatureBytes() throws {

        // A SIGNATURE has a single byte length, so it needs no alignment padding.
        #expect(try encode([.signature(DBusSignature(rawValue: "ai")!)]) == [0x02, 0x61, 0x69, 0x00])
    }

    @Test func alignmentPadding() throws {

        // An INT64 aligns to 8, so a leading BYTE forces seven padding bytes.
        #expect(try encode([.byte(1), .int64(2)]) == [
            0x01,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        ])

        // An INT16 aligns to 2.
        #expect(try encode([.byte(1), .int16(2)]) == [0x01, 0x00, 0x02, 0x00])
    }

    @Test func booleanBytes() throws {

        // BOOLEAN is marshalled as a UINT32 and aligns to 4.
        #expect(try encode([.boolean(true)]) == [0x01, 0x00, 0x00, 0x00])
        #expect(try encode([.boolean(false)]) == [0x00, 0x00, 0x00, 0x00])
    }

    @Test func emptyArrayBytes() throws {

        // An empty array still writes the padding needed to reach its element alignment, and
        // that padding is not counted in the length.
        #expect(try encode([.array(DBusMessageArgument.Array(type: .int64))]) == [
            0x00, 0x00, 0x00, 0x00,  // length 0
            0x00, 0x00, 0x00, 0x00   // padding to the 8 byte element alignment
        ])

        // A byte array needs no such padding.
        #expect(try encode([.array(DBusMessageArgument.Array(type: .byte))]) == [0x00, 0x00, 0x00, 0x00])
    }

    @Test func arrayLengthExcludesPadding() throws {

        // The length counts element data only: 8 bytes for the single INT64, not 12.
        let array = DBusMessageArgument.Array(type: .int64, [.int64(1)])!

        #expect(try encode([.array(array)]) == [
            0x08, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        ])
    }

    @Test func structBytes() throws {

        let structure = DBusMessageArgument.Structure([.byte(1), .int32(2)])!

        // A struct aligns to 8 even when its first field is a byte.
        #expect(try encode([.struct(structure)]) == [
            0x01,
            0x00, 0x00, 0x00,        // padding to the INT32's 4 byte alignment
            0x02, 0x00, 0x00, 0x00
        ])

        // Preceded by a byte, the struct itself is padded to 8.
        #expect(try encode([.byte(0xFF), .struct(structure)]) == [
            0xFF,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x01,
            0x00, 0x00, 0x00,
            0x02, 0x00, 0x00, 0x00
        ])
    }

    @Test func variantBytes() throws {

        // A variant is its contained signature followed by the value, aligned to the contained
        // type.
        #expect(try encode([.variant(DBusMessageArgument.Variant(.int32(5)))]) == [
            0x01, 0x69, 0x00,        // signature "i"
            0x00,                    // padding to 4
            0x05, 0x00, 0x00, 0x00
        ])
    }

    @Test func dictionaryBytes() throws {

        // a{sv} with a single entry {"a": <5>}. Dict entries align to 8 like structs.
        let entry = DBusMessageArgument.Dictionary.Entry(
            key: .string("a"),
            value: .variant(DBusMessageArgument.Variant(.int32(5)))
        )
        let dictionary = DBusMessageArgument.Dictionary(keyType: .string, valueType: .variant, [entry])!

        #expect(try encode([.dictionary(dictionary)]) == [
            0x10, 0x00, 0x00, 0x00,  // length 16
            0x00, 0x00, 0x00, 0x00,  // padding to the dict entry's 8 byte alignment
            0x01, 0x00, 0x00, 0x00,  // key length 1          (offset  8)
            0x61, 0x00,              // "a" NUL               (offset 12)
            0x01, 0x69, 0x00,        // variant signature "i" (offset 14)
            0x00, 0x00, 0x00,        // padding 17 -> 20
            0x05, 0x00, 0x00, 0x00   // 5                     (offset 20)
        ])
    }

    // MARK: - Round trip

    @Test func basicRoundTrip() throws {

        try assertRoundTrip([
            .byte(.min), .byte(.max), .byte(0x42),
            .boolean(true), .boolean(false),
            .int16(.min), .int16(.max),
            .uint16(.min), .uint16(.max),
            .int32(.min), .int32(.max),
            .uint32(.min), .uint32(.max),
            .int64(.min), .int64(.max),
            .uint64(.min), .uint64(.max),
            .double(0.1111), .double(-0.0), .double(.pi),
            .string("Test String"),
            .string(""),
            .string("unicode: ñ 😀 中文"),
            .objectPath(DBusObjectPath(rawValue: "/com/example/bus1")!),
            .objectPath(DBusObjectPath()),
            .signature(DBusSignature(rawValue: "a{s(ai)}")!),
            .signature(DBusSignature()),
            .fileDescriptor(DBusMessageArgument.FileDescriptor(rawValue: 3))
        ])
    }

    @Test func doubleSpecialValues() throws {

        try assertRoundTrip([.double(.infinity), .double(-.infinity), .double(.greatestFiniteMagnitude)])

        // NaN never compares equal, so check the bit pattern survived instead.
        let bytes = try encode([.double(.nan)])
        let decoded = try decode(bytes, [.double])

        guard case let .double(value) = decoded[0]
            else { Issue.record("Wrong type"); return }

        #expect(value.isNaN)
    }

    @Test func arrayRoundTrip() throws {

        try assertRoundTrip([
            .array(DBusMessageArgument.Array([.int16(1), .int16(2), .int16(3)])!),
            .array(DBusMessageArgument.Array(type: .int16)),
            .array(DBusMessageArgument.Array(type: .int32, [.int32(1), .int32(2), .int32(3)])!),
            .array(DBusMessageArgument.Array(type: .string, [.string("1"), .string("2")])!),
            .array(DBusMessageArgument.Array(type: .string)),
            .array(DBusMessageArgument.Array(type: .byte, [.byte(1), .byte(2)])!),
            .array(DBusMessageArgument.Array(type: .double, [.double(1.5)])!),
            .array(DBusMessageArgument.Array(type: .objectPath, [
                .objectPath(DBusObjectPath(rawValue: "/com/example/bus1")!),
                .objectPath(DBusObjectPath(rawValue: "/com/example/bus2")!)
            ])!),
            .array(DBusMessageArgument.Array(type: .array(.string), [
                .array(DBusMessageArgument.Array(type: .string, [.string("A1"), .string("A2")])!),
                .array(DBusMessageArgument.Array(type: .string, [.string("B1"), .string("B2")])!)
            ])!)
        ])
    }

    /// An empty array must preserve its element type rather than fall back to a byte array.
    @Test(arguments: [
        DBusSignature.ValueType.byte, .boolean, .int16, .uint16, .int32, .uint32,
        .int64, .uint64, .double, .string, .objectPath, .signature, .variant,
        .array(.string), .struct([.int32, .string])
    ])
    func emptyArrayPreservesElementType(type: DBusSignature.ValueType) throws {

        let argument = DBusMessageArgument.array(DBusMessageArgument.Array(type: type))

        #expect(argument.type == .array(type))

        let bytes = try encode([argument])
        let decoded = try decode(bytes, [.array(type)])

        guard case let .array(decodedArray) = decoded[0]
            else { Issue.record("Wrong type for \(type)"); return }

        #expect(decodedArray.isEmpty)
        #expect(decodedArray.type == type, "Element type lost for \(type)")
    }

    @Test func structRoundTrip() throws {

        try assertRoundTrip([
            .struct(DBusMessageArgument.Structure([.int32(1), .string("Test String")])!),
            .struct(DBusMessageArgument.Structure([
                .int32(1),
                .string("Test String 1"),
                .objectPath(DBusObjectPath(rawValue: "/com/example/bus1")!),
                .struct(DBusMessageArgument.Structure([
                    .int32(2),
                    .string("Test String 2")
                ])!)
            ])!),
            .struct(DBusMessageArgument.Structure([.byte(1)])!)
        ])
    }

    @Test func variantRoundTrip() throws {

        try assertRoundTrip([
            .variant(DBusMessageArgument.Variant(.string("hello"))),
            .variant(DBusMessageArgument.Variant(.int32(42))),
            .variant(DBusMessageArgument.Variant(.byte(7))),
            .variant(DBusMessageArgument.Variant(.double(1.5))),
            .variant(DBusMessageArgument.Variant(
                .array(DBusMessageArgument.Array(type: .string, [.string("a")])!))),
            .variant(DBusMessageArgument.Variant(
                .struct(DBusMessageArgument.Structure([.int32(1), .string("x")])!))),
            // a variant containing a variant
            .variant(DBusMessageArgument.Variant(
                .variant(DBusMessageArgument.Variant(.int32(9)))))
        ])
    }

    @Test func dictionaryRoundTrip() throws {

        let stringToVariant = DBusMessageArgument.Dictionary(keyType: .string, valueType: .variant, [
            .init(key: .string("Name"), value: .variant(DBusMessageArgument.Variant(.string("Test")))),
            .init(key: .string("Count"), value: .variant(DBusMessageArgument.Variant(.uint32(3)))),
            .init(key: .string("Enabled"), value: .variant(DBusMessageArgument.Variant(.boolean(true))))
        ])!

        let intToString = DBusMessageArgument.Dictionary(keyType: .int32, valueType: .string, [
            .init(key: .int32(1), value: .string("one")),
            .init(key: .int32(2), value: .string("two"))
        ])!

        let empty = DBusMessageArgument.Dictionary(keyType: .string, valueType: .variant)!

        try assertRoundTrip([.dictionary(stringToVariant), .dictionary(intToString), .dictionary(empty)])
    }

    /// `a{sv}` is what `org.freedesktop.DBus.Properties.GetAll` returns, so it has to work.
    @Test func propertiesGetAllShape() throws {

        let properties = DBusMessageArgument.Dictionary(keyType: .string, valueType: .variant, [
            .init(key: .string("Path"),
                  value: .variant(DBusMessageArgument.Variant(
                    .objectPath(DBusObjectPath(rawValue: "/org/example")!)))),
            .init(key: .string("Interfaces"),
                  value: .variant(DBusMessageArgument.Variant(
                    .array(DBusMessageArgument.Array(type: .string, [.string("org.example.A")])!)))),
            .init(key: .string("Nested"),
                  value: .variant(DBusMessageArgument.Variant(
                    .dictionary(DBusMessageArgument.Dictionary(keyType: .string, valueType: .uint32, [
                        .init(key: .string("inner"), value: .uint32(1))
                    ])!))))
        ])!

        #expect(String(DBusMessageArgument.dictionary(properties).type) == "a{sv}")

        try assertRoundTrip([.dictionary(properties)])
    }

    // MARK: - Rejection

    @Test func rejectsNonZeroPadding() throws {

        // [.byte(1), .int16(2)] is 01 00 02 00; corrupt the padding byte.
        var bytes = try encode([.byte(1), .int16(2)])
        bytes[1] = 0xFF

        #expect(throws: DBusProtocolError.invalidPadding) {
            try decode(bytes, [.byte, .int16])
        }
    }

    @Test func rejectsInvalidBoolean() throws {

        var bytes = try encode([.boolean(true)])
        bytes[0] = 2

        #expect(throws: (any Error).self) { try decode(bytes, [.boolean]) }
    }

    @Test func rejectsTruncatedInput() throws {

        let bytes = try encode([.string("hello")])

        for length in 0 ..< bytes.count {
            #expect(throws: (any Error).self, "Should reject \(length) of \(bytes.count) bytes") {
                try decode(Array(bytes.prefix(length)), [.string])
            }
        }
    }

    @Test func rejectsUnterminatedString() throws {

        var bytes = try encode([.string("foo")])
        bytes[bytes.count - 1] = 0x21 // replace the NUL

        #expect(throws: DBusProtocolError.invalidString) { try decode(bytes, [.string]) }
    }

    @Test func rejectsInvalidUTF8() {

        // Length 2, then an invalid UTF-8 sequence, then NUL.
        let bytes: [UInt8] = [0x02, 0x00, 0x00, 0x00, 0xC3, 0x28, 0x00]

        #expect(throws: DBusProtocolError.invalidString) { try decode(bytes, [.string]) }
    }

    @Test func rejectsInvalidObjectPath() throws {

        // A syntactically valid string that is not a valid object path.
        let bytes = try encode([.string("/com//example")])

        #expect(throws: (any Error).self) { try decode(bytes, [.objectPath]) }
    }

    @Test func rejectsOverlongArray() throws {

        // Declare a length longer than the data that follows.
        var bytes = try encode([.array(DBusMessageArgument.Array(type: .byte, [.byte(1)])!)])
        bytes[0] = 0xFF

        #expect(throws: (any Error).self) { try decode(bytes, [.array(.byte)]) }
    }
}
