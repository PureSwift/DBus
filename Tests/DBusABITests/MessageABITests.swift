//
//  MessageABITests.swift
//  DBusABITests
//
//  Exercises the C entry points the way a C caller would: through the
//  declarations in `dbus.h`, with stack allocated `DBusError` and
//  `DBusMessageIter` values, and with every returned object released by its
//  matching `unref` or `dbus_free`.
//

import Testing
import Foundation
import CDBusABI
@testable import DBusABI

@Suite struct MessageABITests {

    // MARK: Construction

    @Test func createsAndReleasesAMethodCall() throws {

        let message = try #require(dbus_message_new_method_call("org.freedesktop.DBus",
                                                               "/org/freedesktop/DBus",
                                                               "org.freedesktop.DBus",
                                                               "ListNames"))
        defer { dbus_message_unref(message) }

        #expect(dbus_message_get_type(message) == Int32(DBUS_MESSAGE_TYPE_METHOD_CALL))
        #expect(String(cString: dbus_message_get_destination(message)!) == "org.freedesktop.DBus")
        #expect(String(cString: dbus_message_get_path(message)!) == "/org/freedesktop/DBus")
        #expect(String(cString: dbus_message_get_interface(message)!) == "org.freedesktop.DBus")
        #expect(String(cString: dbus_message_get_member(message)!) == "ListNames")
    }

    /// A malformed path, interface or member yields NULL, as in the reference.
    @Test(arguments: [
        ("org.freedesktop.DBus", "not-a-path", "org.example.Thing", "Method"),
        ("org.freedesktop.DBus", "/valid/path", "0bad.interface", "Method"),
        ("org.freedesktop.DBus", "/valid/path", "org.example.Thing", "not.a.member"),
        ("not a bus name", "/valid/path", "org.example.Thing", "Method")
    ])
    func rejectsMalformedFields(destination: String,
                                path: String,
                                interface: String,
                                member: String) {

        let message = dbus_message_new_method_call(destination, path, interface, member)

        #expect(message == nil)

        if let message = message { dbus_message_unref(message) }
    }

    @Test func createsASignal() throws {

        let message = try #require(dbus_message_new_signal("/com/example/Object",
                                                           "com.example.Interface",
                                                           "Changed"))
        defer { dbus_message_unref(message) }

        #expect(dbus_message_get_type(message) == Int32(DBUS_MESSAGE_TYPE_SIGNAL))
        #expect(dbus_message_is_signal(message, "com.example.Interface", "Changed") != 0)
        #expect(dbus_message_is_signal(message, "com.example.Interface", "Other") == 0)
    }

    /// A reply must carry the serial of the call it answers.
    @Test func createsAMethodReturn() throws {

        let call = try #require(dbus_message_new_method_call(nil,
                                                             "/com/example/Object",
                                                             "com.example.Interface",
                                                             "Method"))
        defer { dbus_message_unref(call) }

        message(call)?.message.serial = 42

        let reply = try #require(dbus_message_new_method_return(call))
        defer { dbus_message_unref(reply) }

        #expect(dbus_message_get_type(reply) == Int32(DBUS_MESSAGE_TYPE_METHOD_RETURN))
        #expect(dbus_message_get_reply_serial(reply) == 42)
    }

    @Test func createsAnError() throws {

        let call = try #require(dbus_message_new_method_call(nil,
                                                             "/com/example/Object",
                                                             "com.example.Interface",
                                                             "Method"))
        defer { dbus_message_unref(call) }

        let reply = try #require(dbus_message_new_error(call,
                                                        DBUS_ERROR_FAILED,
                                                        "It did not work"))
        defer { dbus_message_unref(reply) }

        #expect(dbus_message_is_error(reply, DBUS_ERROR_FAILED) != 0)
        #expect(String(cString: dbus_message_get_error_name(reply)!) == DBUS_ERROR_FAILED)
    }

    // MARK: Reference counting

    /// `ref` and `unref` must balance: the object survives the first release
    /// and dies on the second.
    @Test func referenceCountingKeepsTheMessageAlive() throws {

        let message = try #require(dbus_message_new(Int32(DBUS_MESSAGE_TYPE_METHOD_CALL)))

        #expect(dbus_message_ref(message) == message)

        dbus_message_unref(message)

        // Still valid: the extra reference is still held.
        #expect(dbus_message_get_type(message) == Int32(DBUS_MESSAGE_TYPE_METHOD_CALL))

        dbus_message_unref(message)
    }

    // MARK: Header accessors

    /// The reference returns a borrowed pointer that stays valid, so a second
    /// read of an unchanged field must not hand back freed memory.
    @Test func headerStringsRemainValid() throws {

        let message = try #require(dbus_message_new(Int32(DBUS_MESSAGE_TYPE_SIGNAL)))
        defer { dbus_message_unref(message) }

        #expect(dbus_message_set_path(message, "/com/example/One") != 0)

        let first = try #require(dbus_message_get_path(message))
        let second = try #require(dbus_message_get_path(message))

        #expect(first == second, "An unchanged field should not be reallocated")
        #expect(String(cString: second) == "/com/example/One")

        // Changing it must be reflected, and the old copy released.
        #expect(dbus_message_set_path(message, "/com/example/Two") != 0)
        #expect(String(cString: dbus_message_get_path(message)!) == "/com/example/Two")

        // An invalid value is refused and leaves the field alone.
        #expect(dbus_message_set_path(message, "not a path") == 0)
        #expect(String(cString: dbus_message_get_path(message)!) == "/com/example/Two")
    }

    @Test func noReplyFlagRoundTrips() throws {

        let message = try #require(dbus_message_new(Int32(DBUS_MESSAGE_TYPE_METHOD_CALL)))
        defer { dbus_message_unref(message) }

        #expect(dbus_message_get_no_reply(message) == 0)

        dbus_message_set_no_reply(message, 1)
        #expect(dbus_message_get_no_reply(message) != 0)

        dbus_message_set_no_reply(message, 0)
        #expect(dbus_message_get_no_reply(message) == 0)
    }

    // MARK: Arguments

    @Test func appendsAndReadsBasicTypes() throws {

        let message = try #require(dbus_message_new(Int32(DBUS_MESSAGE_TYPE_METHOD_CALL)))
        defer { dbus_message_unref(message) }

        var iterator = DBusMessageIter()
        dbus_message_iter_init_append(message, &iterator)

        var byte: UInt8 = 7
        var boolean: dbus_bool_t = 1
        var int32: Int32 = -12345
        var uint64: UInt64 = 0xDEAD_BEEF
        var double: Double = 2.5
        let text = strdup("hello")
        defer { free(text) }
        var textPointer = UnsafePointer(text)

        #expect(dbus_message_iter_append_basic(&iterator, Int32(DBUS_TYPE_BYTE), &byte) != 0)
        #expect(dbus_message_iter_append_basic(&iterator, Int32(DBUS_TYPE_BOOLEAN), &boolean) != 0)
        #expect(dbus_message_iter_append_basic(&iterator, Int32(DBUS_TYPE_INT32), &int32) != 0)
        #expect(dbus_message_iter_append_basic(&iterator, Int32(DBUS_TYPE_UINT64), &uint64) != 0)
        #expect(dbus_message_iter_append_basic(&iterator, Int32(DBUS_TYPE_DOUBLE), &double) != 0)
        #expect(dbus_message_iter_append_basic(&iterator, Int32(DBUS_TYPE_STRING), &textPointer) != 0)

        #expect(String(cString: dbus_message_get_signature(message)!) == "ybitds")

        var reader = DBusMessageIter()
        #expect(dbus_message_iter_init(message, &reader) != 0)

        #expect(dbus_message_iter_get_arg_type(&reader) == Int32(DBUS_TYPE_BYTE))
        var readByte: UInt8 = 0
        dbus_message_iter_get_basic(&reader, &readByte)
        #expect(readByte == 7)

        #expect(dbus_message_iter_next(&reader) != 0)
        var readBoolean: dbus_bool_t = 0
        dbus_message_iter_get_basic(&reader, &readBoolean)
        #expect(readBoolean != 0)

        #expect(dbus_message_iter_next(&reader) != 0)
        var readInt32: Int32 = 0
        dbus_message_iter_get_basic(&reader, &readInt32)
        #expect(readInt32 == -12345)

        #expect(dbus_message_iter_next(&reader) != 0)
        var readUInt64: UInt64 = 0
        dbus_message_iter_get_basic(&reader, &readUInt64)
        #expect(readUInt64 == 0xDEAD_BEEF)

        #expect(dbus_message_iter_next(&reader) != 0)
        var readDouble: Double = 0
        dbus_message_iter_get_basic(&reader, &readDouble)
        #expect(readDouble == 2.5)

        #expect(dbus_message_iter_next(&reader) != 0)
        var readText: UnsafePointer<CChar>?
        dbus_message_iter_get_basic(&reader, &readText)
        #expect(String(cString: try #require(readText)) == "hello")

        // Past the last argument.
        #expect(dbus_message_iter_next(&reader) == 0)
        #expect(dbus_message_iter_get_arg_type(&reader) == Int32(DBUS_TYPE_INVALID))
    }

    /// An empty array must keep its declared element type, which is the case a
    /// marshaller that infers the type from the elements gets wrong.
    @Test func appendsAnEmptyArray() throws {

        let message = try #require(dbus_message_new(Int32(DBUS_MESSAGE_TYPE_METHOD_CALL)))
        defer { dbus_message_unref(message) }

        var iterator = DBusMessageIter()
        dbus_message_iter_init_append(message, &iterator)

        var sub = DBusMessageIter()
        #expect(dbus_message_iter_open_container(&iterator, Int32(DBUS_TYPE_ARRAY), "s", &sub) != 0)
        #expect(dbus_message_iter_close_container(&iterator, &sub) != 0)

        #expect(String(cString: dbus_message_get_signature(message)!) == "as")
    }

    @Test func appendsAndReadsAnArrayOfStrings() throws {

        let message = try #require(dbus_message_new(Int32(DBUS_MESSAGE_TYPE_METHOD_CALL)))
        defer { dbus_message_unref(message) }

        var iterator = DBusMessageIter()
        dbus_message_iter_init_append(message, &iterator)

        var sub = DBusMessageIter()
        #expect(dbus_message_iter_open_container(&iterator, Int32(DBUS_TYPE_ARRAY), "s", &sub) != 0)

        for value in ["one", "two", "three"] {
            let copy = strdup(value)
            defer { free(copy) }
            var pointer = UnsafePointer(copy)
            #expect(dbus_message_iter_append_basic(&sub, Int32(DBUS_TYPE_STRING), &pointer) != 0)
        }

        #expect(dbus_message_iter_close_container(&iterator, &sub) != 0)
        #expect(String(cString: dbus_message_get_signature(message)!) == "as")

        var reader = DBusMessageIter()
        #expect(dbus_message_iter_init(message, &reader) != 0)
        #expect(dbus_message_iter_get_arg_type(&reader) == Int32(DBUS_TYPE_ARRAY))
        #expect(dbus_message_iter_get_element_type(&reader) == Int32(DBUS_TYPE_STRING))

        var element = DBusMessageIter()
        dbus_message_iter_recurse(&reader, &element)

        var values = [String]()
        while dbus_message_iter_get_arg_type(&element) != Int32(DBUS_TYPE_INVALID) {
            var pointer: UnsafePointer<CChar>?
            dbus_message_iter_get_basic(&element, &pointer)
            values.append(String(cString: try #require(pointer)))
            _ = dbus_message_iter_next(&element)
        }

        #expect(values == ["one", "two", "three"])
    }

    /// `a{sv}` is the shape every service uses through `org.freedesktop.DBus.Properties`.
    @Test func appendsAndReadsADictionaryOfVariants() throws {

        let message = try #require(dbus_message_new(Int32(DBUS_MESSAGE_TYPE_METHOD_CALL)))
        defer { dbus_message_unref(message) }

        var iterator = DBusMessageIter()
        dbus_message_iter_init_append(message, &iterator)

        var dictionary = DBusMessageIter()
        #expect(dbus_message_iter_open_container(&iterator, Int32(DBUS_TYPE_ARRAY), "{sv}", &dictionary) != 0)

        var entry = DBusMessageIter()
        #expect(dbus_message_iter_open_container(&dictionary, Int32(DBUS_TYPE_DICT_ENTRY), nil, &entry) != 0)

        let key = strdup("Count")
        defer { free(key) }
        var keyPointer = UnsafePointer(key)
        #expect(dbus_message_iter_append_basic(&entry, Int32(DBUS_TYPE_STRING), &keyPointer) != 0)

        var variant = DBusMessageIter()
        #expect(dbus_message_iter_open_container(&entry, Int32(DBUS_TYPE_VARIANT), "u", &variant) != 0)
        var count: UInt32 = 99
        #expect(dbus_message_iter_append_basic(&variant, Int32(DBUS_TYPE_UINT32), &count) != 0)
        #expect(dbus_message_iter_close_container(&entry, &variant) != 0)

        #expect(dbus_message_iter_close_container(&dictionary, &entry) != 0)
        #expect(dbus_message_iter_close_container(&iterator, &dictionary) != 0)

        #expect(String(cString: dbus_message_get_signature(message)!) == "a{sv}")

        // Read it back the way a C caller would.
        var reader = DBusMessageIter()
        #expect(dbus_message_iter_init(message, &reader) != 0)
        #expect(dbus_message_iter_get_arg_type(&reader) == Int32(DBUS_TYPE_ARRAY))
        #expect(dbus_message_iter_get_element_type(&reader) == Int32(DBUS_TYPE_DICT_ENTRY))

        var entries = DBusMessageIter()
        dbus_message_iter_recurse(&reader, &entries)
        #expect(dbus_message_iter_get_arg_type(&entries) == Int32(DBUS_TYPE_DICT_ENTRY))

        var pair = DBusMessageIter()
        dbus_message_iter_recurse(&entries, &pair)

        var readKey: UnsafePointer<CChar>?
        dbus_message_iter_get_basic(&pair, &readKey)
        #expect(String(cString: try #require(readKey)) == "Count")

        #expect(dbus_message_iter_next(&pair) != 0)
        #expect(dbus_message_iter_get_arg_type(&pair) == Int32(DBUS_TYPE_VARIANT))

        var contained = DBusMessageIter()
        dbus_message_iter_recurse(&pair, &contained)
        #expect(dbus_message_iter_get_arg_type(&contained) == Int32(DBUS_TYPE_UINT32))

        var readCount: UInt32 = 0
        dbus_message_iter_get_basic(&contained, &readCount)
        #expect(readCount == 99)
    }

    @Test func appendsAStructure() throws {

        let message = try #require(dbus_message_new(Int32(DBUS_MESSAGE_TYPE_METHOD_CALL)))
        defer { dbus_message_unref(message) }

        var iterator = DBusMessageIter()
        dbus_message_iter_init_append(message, &iterator)

        var structure = DBusMessageIter()
        #expect(dbus_message_iter_open_container(&iterator, Int32(DBUS_TYPE_STRUCT), nil, &structure) != 0)

        var number: Int32 = 5
        #expect(dbus_message_iter_append_basic(&structure, Int32(DBUS_TYPE_INT32), &number) != 0)

        let text = strdup("inner")
        defer { free(text) }
        var pointer = UnsafePointer(text)
        #expect(dbus_message_iter_append_basic(&structure, Int32(DBUS_TYPE_STRING), &pointer) != 0)

        #expect(dbus_message_iter_close_container(&iterator, &structure) != 0)

        #expect(String(cString: dbus_message_get_signature(message)!) == "(is)")
    }

    /// Abandoning a container must leave the message as it was.
    @Test func abandonsAContainer() throws {

        let message = try #require(dbus_message_new(Int32(DBUS_MESSAGE_TYPE_METHOD_CALL)))
        defer { dbus_message_unref(message) }

        var iterator = DBusMessageIter()
        dbus_message_iter_init_append(message, &iterator)

        var sub = DBusMessageIter()
        #expect(dbus_message_iter_open_container(&iterator, Int32(DBUS_TYPE_ARRAY), "s", &sub) != 0)

        let text = strdup("discarded")
        defer { free(text) }
        var pointer = UnsafePointer(text)
        #expect(dbus_message_iter_append_basic(&sub, Int32(DBUS_TYPE_STRING), &pointer) != 0)

        dbus_message_iter_abandon_container(&iterator, &sub)

        #expect(String(cString: dbus_message_get_signature(message)!) == "")
    }

    /// An uninitialized iterator must be refused rather than read as garbage.
    @Test func rejectsAnUninitializedIterator() {

        var iterator = DBusMessageIter()

        #expect(dbus_message_iter_get_arg_type(&iterator) == Int32(DBUS_TYPE_INVALID))
        #expect(dbus_message_iter_next(&iterator) == 0)
        #expect(dbus_message_iter_has_next(&iterator) == 0)
    }

    // MARK: Variadic helpers
    //
    // `dbus_message_append_args` and `dbus_message_get_args` are C variadics,
    // which Swift cannot call at all. They are covered instead by the C smoke
    // test that CMake builds and runs against the installed shared library —
    // a real C caller, which is the only thing that can exercise them.
}
