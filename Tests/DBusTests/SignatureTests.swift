//
//  SignatureTests.swift
//  DBusTests
//
//  Created by Alsey Coleman Miller on 10/22/18.
//

import Testing
@testable import DBus

@Suite struct SignatureTests {

    @Test(arguments: [
        "aa",
        "(ii",
        "ii)",
        "()",
        "a",
        "test",
        "(ii)(ii) (ii)",
        "{si}",
        "a{i}",
        "v{i}",
        "a{s}",
        "a{(i)a}",
        "a{vs}", // a variant is not a basic type, so it cannot be a dictionary key
        "a{av}",
        "}",
        ")"
    ])
    func invalid(string: String) throws {

        #expect(DBusSignature(rawValue: string) == nil, "\(string) should be invalid")

        let error = try #require(throws: DBusError.self) {
            try DBusSignature.validate(string)
        }

        #expect(error.name == .invalidSignature)
    }

    /// Declared as an explicitly typed property: as an inline `arguments:` literal the array
    /// literals for each signature overwhelm the type checker.
    static let validSignatures: [(String, DBusSignature)] = [
        ("", DBusSignature([])),
        ("s", DBusSignature([.string])),
        ("v", DBusSignature([.variant])),
        ("i", DBusSignature([.int32])),
        ("ii", DBusSignature([.int32, .int32])),
        ("aiai", DBusSignature([.array(.int32), .array(.int32)])),
        ("(i)", DBusSignature([.struct([.int32])])),
        ("(ii)", DBusSignature([.struct([.int32, .int32])])),
        ("(aii)", DBusSignature([.struct([.array(.int32), .int32])])),
        ("ai(i)", DBusSignature([.array(.int32), .struct([.int32])])),
        ("a(i)", DBusSignature([.array(.struct([.int32]))])),
        ("(ii)(ii)", DBusSignature([.struct([.int32, .int32]), .struct([.int32, .int32])])),
        ("a{si}", DBusSignature([.dictionary(DBusSignature.DictionaryType(key: .string, value: .int32)!)])),
        ("a{is}", DBusSignature([.dictionary(DBusSignature.DictionaryType(key: .int32, value: .string)!)])),
        ("a{s(ai)}", DBusSignature([.dictionary(DBusSignature.DictionaryType(key: .string, value: .struct([.array(.int32)]))!)])),
        ("a{sai}", DBusSignature([.dictionary(DBusSignature.DictionaryType(key: .string, value: .array(.int32))!)])),
        ("a{sv}", DBusSignature([.dictionary(DBusSignature.DictionaryType(key: .string, value: .variant)!)]))
    ]

    @Test(arguments: SignatureTests.validSignatures)
    func valid(string: String, expected: DBusSignature) throws {

        #expect(throws: Never.self) { try DBusSignature.validate(string) }

        let signature = try #require(DBusSignature(rawValue: string), "Could not parse \(string)")

        #expect(signature == expected)
        #expect(signature.rawValue == string)
        #expect(signature.string == string)
        #expect(signature.elements == expected.elements)
        #expect(Array(signature) == Array(expected))

        // Mutating clears the cached string, so `rawValue` has to rebuild it.
        var mutable = signature
        mutable.append(.double)
        #expect(mutable.string == nil)
        #expect(mutable != signature)
        #expect(mutable.rawValue != signature.rawValue)
        #expect(mutable.elements != signature.elements)
    }

    /// The specification caps container nesting at 32 levels for arrays and structs alike.
    @Test func rejectsExcessiveNesting() {

        #expect(DBusSignature(rawValue: String(repeating: "a", count: 32) + "i") != nil)
        #expect(DBusSignature(rawValue: String(repeating: "a", count: 33) + "i") == nil)

        let deepStruct = String(repeating: "(", count: 33) + "i" + String(repeating: ")", count: 33)
        #expect(DBusSignature(rawValue: deepStruct) == nil)
    }

    /// The length limit is 255 bytes, not 255 characters.
    @Test func rejectsOverlongSignature() {

        #expect(DBusSignature(rawValue: String(repeating: "i", count: 255)) != nil)
        #expect(DBusSignature(rawValue: String(repeating: "i", count: 256)) == nil)
    }

    @Test func basicAndContainerTypes() {

        let basic: [DBusSignature.ValueType] = [
            .byte, .boolean, .int16, .uint16, .int32, .uint32,
            .int64, .uint64, .double, .fileDescriptor, .string, .objectPath, .signature
        ]

        for type in basic {
            #expect(type.isBasic, "\(type) should be basic")
            #expect(!type.isContainer, "\(type) should not be a container")
        }

        // A variant is written as a single type code but is not basic: its contained type is
        // part of the value, which is why it cannot be a dictionary key.
        #expect(!DBusSignature.ValueType.variant.isBasic)
        #expect(!DBusSignature.ValueType.variant.isContainer)

        for type: DBusSignature.ValueType in [.array(.int32), .struct([.int32])] {
            #expect(!type.isBasic)
            #expect(type.isContainer)
        }
    }

    @Test func dictionaryKeyMustBeBasic() {

        #expect(DBusSignature.DictionaryType(key: .string, value: .variant) != nil)
        #expect(DBusSignature.DictionaryType(key: .variant, value: .string) == nil)
        #expect(DBusSignature.DictionaryType(key: .array(.int32), value: .string) == nil)
        #expect(DBusSignature.DictionaryType(key: .struct([.int32]), value: .string) == nil)
    }

    @Test func structureAndDictionaryRawValues() throws {

        let structure = try #require(DBusSignature.StructureType(rawValue: "(is)"))
        #expect(structure.rawValue == "(is)")

        let dictionary = try #require(DBusSignature.DictionaryType(rawValue: "a{sv}"))
        #expect(dictionary.rawValue == "a{sv}")

        // Not a single complete value of the expected kind.
        #expect(DBusSignature.StructureType(rawValue: "is") == nil)
        #expect(DBusSignature.DictionaryType(rawValue: "(is)") == nil)
    }

    @Test func emptyStructureIsRejected() {

        #expect(DBusSignature.StructureType([]) == nil)
    }
}
