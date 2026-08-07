//
//  MessageIterator.swift
//  DBus
//
//  `dbus_message_iter_*` — reading and writing message arguments.
//
//  A `DBusMessageIter` is a stack value with no destructor, so its state
//  cannot live in an allocation the caller is expected to release. The state
//  is instead owned by the message it was created from and reached through a
//  pointer parked in one of the struct's opaque fields. That matches the
//  reference's rule that an iterator is valid only while its message is.
//

import Foundation
import CDBusABI
import DBus

// MARK: - State

/// One element of a container being read.
///
/// A dictionary entry is not a `DBusMessageArgument` — this package models a
/// dictionary as entries rather than as an array of two-field structures — but
/// the C ABI presents one as a `DBUS_TYPE_DICT_ENTRY` container, so reading
/// needs a representation for it.
internal enum IteratorItem {

    case argument(DBusMessageArgument)
    case dictionaryEntry(DBusMessageArgument.Dictionary.Entry)
}

/// What an append iterator is currently building.
internal enum IteratorContainer {

    case array(DBusSignature.ValueType)
    case dictionary(key: DBusSignature.ValueType, value: DBusSignature.ValueType)
    case dictionaryEntry
    case structure
    case variant
}

internal final class IteratorState {

    /// The message the iterator reads from or writes to.
    ///
    /// `unowned` because the message owns the state, and an owning reference
    /// back would keep both alive forever.
    unowned let box: MessageBox

    let isAppend: Bool

    /// Reading: the contents of this container. Appending: what has been
    /// written to it so far.
    var items: [IteratorItem] = []

    var index: Int = 0

    /// Entries accumulated by an append iterator over a dictionary.
    var entries: [DBusMessageArgument.Dictionary.Entry] = []

    /// What this append iterator is building, or `nil` at the top level.
    var container: IteratorContainer?

    var parent: IteratorState?

    init(box: MessageBox, isAppend: Bool) {

        self.box = box
        self.isAppend = isAppend
    }

    /// The arguments written to an append iterator, in order.
    var writtenArguments: [DBusMessageArgument] {

        return items.compactMap {
            guard case let .argument(argument) = $0 else { return nil }
            return argument
        }
    }

    /// Record an argument, either into the message or into this container.
    func emit(_ argument: DBusMessageArgument) {

        if container == nil, parent == nil {
            box.message.arguments.append(argument)
        } else {
            items.append(.argument(argument))
        }
    }
}

// MARK: - Attaching state to the C struct

/// Marks a `DBusMessageIter` as initialized by this implementation.
///
/// The reference leaves the fields undefined until an `init` call; a caller
/// that reads an uninitialized iterator gets undefined behavior there and a
/// safe refusal here.
private let iteratorMagic: dbus_uint32_t = 0x44_42_49_54

private func attach(_ state: IteratorState, to iterator: UnsafeMutablePointer<DBusMessageIter>) {

    // Unretained: `box.iterators` is what keeps the state alive.
    iterator.pointee.dummy1 = Unmanaged.passUnretained(state).toOpaque()
    iterator.pointee.dummy3 = iteratorMagic
    state.box.iterators.append(state)
}

private func state(_ iterator: UnsafeMutablePointer<DBusMessageIter>?) -> IteratorState? {

    guard let iterator = iterator,
          iterator.pointee.dummy3 == iteratorMagic,
          let raw = iterator.pointee.dummy1
        else { return nil }

    return Unmanaged<IteratorState>.fromOpaque(raw).takeUnretainedValue()
}

// MARK: - Type codes

internal extension DBusSignature.ValueType {

    /// The single character type code, as the C ABI reports it.
    var typeCode: Int32 {

        switch self {
        case .byte: return Int32(DBUS_TYPE_BYTE)
        case .boolean: return Int32(DBUS_TYPE_BOOLEAN)
        case .int16: return Int32(DBUS_TYPE_INT16)
        case .uint16: return Int32(DBUS_TYPE_UINT16)
        case .int32: return Int32(DBUS_TYPE_INT32)
        case .uint32: return Int32(DBUS_TYPE_UINT32)
        case .int64: return Int32(DBUS_TYPE_INT64)
        case .uint64: return Int32(DBUS_TYPE_UINT64)
        case .double: return Int32(DBUS_TYPE_DOUBLE)
        case .fileDescriptor: return Int32(DBUS_TYPE_UNIX_FD)
        case .string: return Int32(DBUS_TYPE_STRING)
        case .objectPath: return Int32(DBUS_TYPE_OBJECT_PATH)
        case .signature: return Int32(DBUS_TYPE_SIGNATURE)
        case .variant: return Int32(DBUS_TYPE_VARIANT)
        case .array: return Int32(DBUS_TYPE_ARRAY)
        case .struct: return Int32(DBUS_TYPE_STRUCT)
        case .dictionary: return Int32(DBUS_TYPE_ARRAY)
        }
    }
}

private extension IteratorItem {

    var typeCode: Int32 {

        switch self {
        case let .argument(argument): return argument.type.typeCode
        case .dictionaryEntry: return Int32(DBUS_TYPE_DICT_ENTRY)
        }
    }
}

/// The single value type a signature string denotes, if it denotes exactly one.
private func valueType(_ signature: String) -> DBusSignature.ValueType? {

    let parsed = DBusSignature(rawValue: signature).map { Array($0) }

    guard let types = parsed, types.count == 1
        else { return nil }

    return types[0]
}

// MARK: - Reading

/// `dbus_bool_t dbus_message_iter_init(DBusMessage *message, DBusMessageIter *iter)`
///
/// Returns FALSE, and leaves an iterator that reports `DBUS_TYPE_INVALID`, when
/// the message has no arguments.
@_cdecl("dbus_message_iter_init")
public func abi_dbus_message_iter_init(_ message: OpaquePointer?,
                                   _ iterator: UnsafeMutablePointer<DBusMessageIter>?) -> dbus_bool_t {

    guard let box = DBusABI.message(message), let iterator = iterator
        else { return false.cBool }

    let state = IteratorState(box: box, isAppend: false)
    state.items = box.message.arguments.map { .argument($0) }
    attach(state, to: iterator)

    return (state.items.isEmpty == false).cBool
}

/// `int dbus_message_iter_get_arg_type(DBusMessageIter *iter)`
@_cdecl("dbus_message_iter_get_arg_type")
public func abi_dbus_message_iter_get_arg_type(_ iterator: UnsafeMutablePointer<DBusMessageIter>?) -> Int32 {

    guard let state = state(iterator), state.index < state.items.count
        else { return Int32(DBUS_TYPE_INVALID) }

    return state.items[state.index].typeCode
}

/// `int dbus_message_iter_get_element_type(DBusMessageIter *iter)`
@_cdecl("dbus_message_iter_get_element_type")
public func abi_dbus_message_iter_get_element_type(_ iterator: UnsafeMutablePointer<DBusMessageIter>?) -> Int32 {

    guard let state = state(iterator), state.index < state.items.count,
          case let .argument(argument) = state.items[state.index]
        else { return Int32(DBUS_TYPE_INVALID) }

    switch argument {
    case let .array(array): return array.type.typeCode
    case .dictionary: return Int32(DBUS_TYPE_DICT_ENTRY)
    default: return Int32(DBUS_TYPE_INVALID)
    }
}

/// `dbus_bool_t dbus_message_iter_has_next(DBusMessageIter *iter)`
@_cdecl("dbus_message_iter_has_next")
public func abi_dbus_message_iter_has_next(_ iterator: UnsafeMutablePointer<DBusMessageIter>?) -> dbus_bool_t {

    guard let state = state(iterator)
        else { return false.cBool }

    return (state.index + 1 < state.items.count).cBool
}

/// `dbus_bool_t dbus_message_iter_next(DBusMessageIter *iter)`
@_cdecl("dbus_message_iter_next")
public func abi_dbus_message_iter_next(_ iterator: UnsafeMutablePointer<DBusMessageIter>?) -> dbus_bool_t {

    guard let state = state(iterator), state.index < state.items.count
        else { return false.cBool }

    state.index += 1
    return (state.index < state.items.count).cBool
}

/// `void dbus_message_iter_recurse(DBusMessageIter *iter, DBusMessageIter *sub)`
@_cdecl("dbus_message_iter_recurse")
public func abi_dbus_message_iter_recurse(_ iterator: UnsafeMutablePointer<DBusMessageIter>?,
                                      _ sub: UnsafeMutablePointer<DBusMessageIter>?) {

    guard let state = state(iterator), let sub = sub, state.index < state.items.count
        else { return }

    let child = IteratorState(box: state.box, isAppend: false)

    switch state.items[state.index] {

    case let .dictionaryEntry(entry):
        child.items = [.argument(entry.key), .argument(entry.value)]

    case let .argument(argument):
        switch argument {
        case let .array(array):
            child.items = array.map { .argument($0) }
        case let .struct(structure):
            child.items = structure.map { .argument($0) }
        case let .variant(variant):
            child.items = [.argument(variant.element)]
        case let .dictionary(dictionary):
            child.items = dictionary.map { .dictionaryEntry($0) }
        default:
            child.items = []
        }
    }

    attach(child, to: sub)
}

/// `char *dbus_message_iter_get_signature(DBusMessageIter *iter)`
///
/// The caller releases the result with `dbus_free`.
@_cdecl("dbus_message_iter_get_signature")
public func abi_dbus_message_iter_get_signature(_ iterator: UnsafeMutablePointer<DBusMessageIter>?) -> UnsafeMutablePointer<CChar>? {

    guard let state = state(iterator)
        else { return nil }

    var signature = ""

    for item in state.items[state.index...] {
        guard case let .argument(argument) = item else { continue }
        signature += DBusSignature([argument.type]).rawValue
    }

    return signature.copiedCString()
}

/// `void dbus_message_iter_get_basic(DBusMessageIter *iter, void *value)`
///
/// Writing through an untyped pointer, so the caller must have checked
/// `dbus_message_iter_get_arg_type` first — as the reference requires. A
/// mismatch writes nothing rather than reinterpreting the value.
@_cdecl("dbus_message_iter_get_basic")
public func abi_dbus_message_iter_get_basic(_ iterator: UnsafeMutablePointer<DBusMessageIter>?,
                                        _ value: UnsafeMutableRawPointer?) {

    guard let state = state(iterator), let value = value, state.index < state.items.count,
          case let .argument(argument) = state.items[state.index]
        else { return }

    switch argument {

    case let .byte(byte):
        value.assumingMemoryBound(to: UInt8.self).pointee = byte

    case let .boolean(boolean):
        value.assumingMemoryBound(to: dbus_bool_t.self).pointee = boolean.cBool

    case let .int16(number):
        value.assumingMemoryBound(to: Int16.self).pointee = number

    case let .uint16(number):
        value.assumingMemoryBound(to: UInt16.self).pointee = number

    case let .int32(number):
        value.assumingMemoryBound(to: Int32.self).pointee = number

    case let .uint32(number):
        value.assumingMemoryBound(to: UInt32.self).pointee = number

    case let .int64(number):
        value.assumingMemoryBound(to: Int64.self).pointee = number

    case let .uint64(number):
        value.assumingMemoryBound(to: UInt64.self).pointee = number

    case let .double(number):
        value.assumingMemoryBound(to: Double.self).pointee = number

    case let .fileDescriptor(descriptor):
        value.assumingMemoryBound(to: Int32.self).pointee = descriptor.rawValue

    case let .string(text):
        value.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee = state.box.borrowedCopy(text)

    case let .objectPath(path):
        value.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee = state.box.borrowedCopy(path.rawValue)

    case let .signature(signature):
        value.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee = state.box.borrowedCopy(signature.rawValue)

    case .array, .struct, .dictionary, .variant:
        break // not a basic type; the caller must recurse
    }
}

// MARK: - Appending

/// `void dbus_message_iter_init_append(DBusMessage *message, DBusMessageIter *iter)`
@_cdecl("dbus_message_iter_init_append")
public func abi_dbus_message_iter_init_append(_ message: OpaquePointer?,
                                          _ iterator: UnsafeMutablePointer<DBusMessageIter>?) {

    guard let box = DBusABI.message(message), let iterator = iterator
        else { return }

    attach(IteratorState(box: box, isAppend: true), to: iterator)
}

/// Build an argument of the given type code from a caller supplied pointer.
private func argument(type: Int32, value: UnsafeRawPointer) -> DBusMessageArgument? {

    switch Int(type) {

    case Int(DBUS_TYPE_BYTE):
        return .byte(value.assumingMemoryBound(to: UInt8.self).pointee)

    case Int(DBUS_TYPE_BOOLEAN):
        return .boolean(value.assumingMemoryBound(to: dbus_bool_t.self).pointee != 0)

    case Int(DBUS_TYPE_INT16):
        return .int16(value.assumingMemoryBound(to: Int16.self).pointee)

    case Int(DBUS_TYPE_UINT16):
        return .uint16(value.assumingMemoryBound(to: UInt16.self).pointee)

    case Int(DBUS_TYPE_INT32):
        return .int32(value.assumingMemoryBound(to: Int32.self).pointee)

    case Int(DBUS_TYPE_UINT32):
        return .uint32(value.assumingMemoryBound(to: UInt32.self).pointee)

    case Int(DBUS_TYPE_INT64):
        return .int64(value.assumingMemoryBound(to: Int64.self).pointee)

    case Int(DBUS_TYPE_UINT64):
        return .uint64(value.assumingMemoryBound(to: UInt64.self).pointee)

    case Int(DBUS_TYPE_DOUBLE):
        return .double(value.assumingMemoryBound(to: Double.self).pointee)

    case Int(DBUS_TYPE_UNIX_FD):
        return .fileDescriptor(.init(rawValue: value.assumingMemoryBound(to: Int32.self).pointee))

    case Int(DBUS_TYPE_STRING):
        guard let text = string(value.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee)
            else { return nil }
        return .string(text)

    case Int(DBUS_TYPE_OBJECT_PATH):
        guard let text = string(value.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee),
              let path = DBusObjectPath(rawValue: text)
            else { return nil }
        return .objectPath(path)

    case Int(DBUS_TYPE_SIGNATURE):
        guard let text = string(value.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee),
              let signature = DBusSignature(rawValue: text)
            else { return nil }
        return .signature(signature)

    default:
        return nil
    }
}

/// `dbus_bool_t dbus_message_iter_append_basic(DBusMessageIter *iter, int type, const void *value)`
@_cdecl("dbus_message_iter_append_basic")
public func abi_dbus_message_iter_append_basic(_ iterator: UnsafeMutablePointer<DBusMessageIter>?,
                                           _ type: Int32,
                                           _ value: UnsafeRawPointer?) -> dbus_bool_t {

    guard let state = state(iterator), state.isAppend, let value = value,
          let argument = argument(type: type, value: value)
        else { return false.cBool }

    state.emit(argument)
    return true.cBool
}

/// `dbus_bool_t dbus_message_iter_open_container(DBusMessageIter *, int, const char *, DBusMessageIter *)`
@_cdecl("dbus_message_iter_open_container")
public func abi_dbus_message_iter_open_container(_ iterator: UnsafeMutablePointer<DBusMessageIter>?,
                                             _ type: Int32,
                                             _ containedSignature: UnsafePointer<CChar>?,
                                             _ sub: UnsafeMutablePointer<DBusMessageIter>?) -> dbus_bool_t {

    guard let state = state(iterator), state.isAppend, let sub = sub
        else { return false.cBool }

    let signature = string(containedSignature)
    let container: IteratorContainer

    switch Int(type) {

    case Int(DBUS_TYPE_ARRAY):
        guard let signature = signature
            else { return false.cBool }

        // A dictionary is opened as an array whose element signature is a
        // dictionary entry, which is not itself a complete type.
        if signature.hasPrefix("{"), signature.hasSuffix("}") {

            let inner = String(signature.dropFirst().dropLast())

            guard let parsed = DBusSignature(rawValue: inner).map({ Array($0) }),
                  parsed.count == 2
                else { return false.cBool }

            container = .dictionary(key: parsed[0], value: parsed[1])
        }
        else {
            guard let element = valueType(signature)
                else { return false.cBool }

            container = .array(element)
        }

    case Int(DBUS_TYPE_STRUCT):
        container = .structure

    case Int(DBUS_TYPE_DICT_ENTRY):
        container = .dictionaryEntry

    case Int(DBUS_TYPE_VARIANT):
        container = .variant

    default:
        return false.cBool
    }

    let child = IteratorState(box: state.box, isAppend: true)
    child.container = container
    child.parent = state
    attach(child, to: sub)

    return true.cBool
}

/// `dbus_bool_t dbus_message_iter_close_container(DBusMessageIter *iter, DBusMessageIter *sub)`
@_cdecl("dbus_message_iter_close_container")
public func abi_dbus_message_iter_close_container(_ iterator: UnsafeMutablePointer<DBusMessageIter>?,
                                              _ sub: UnsafeMutablePointer<DBusMessageIter>?) -> dbus_bool_t {

    guard let parent = state(iterator),
          let child = state(sub),
          let container = child.container,
          child.parent === parent
        else { return false.cBool }

    let written = child.writtenArguments

    switch container {

    case let .array(element):
        guard let array = DBusMessageArgument.Array(type: element, written)
            else { return false.cBool }
        parent.emit(.array(array))

    case let .dictionary(key, value):
        guard let dictionary = DBusMessageArgument.Dictionary(keyType: key,
                                                              valueType: value,
                                                              child.entries)
            else { return false.cBool }
        parent.emit(.dictionary(dictionary))

    case .dictionaryEntry:
        guard written.count == 2
            else { return false.cBool }
        parent.entries.append(.init(key: written[0], value: written[1]))

    case .structure:
        guard let structure = DBusMessageArgument.Structure(written)
            else { return false.cBool }
        parent.emit(.struct(structure))

    case .variant:
        guard written.count == 1
            else { return false.cBool }
        parent.emit(.variant(.init(written[0])))
    }

    return true.cBool
}

/// `void dbus_message_iter_abandon_container(DBusMessageIter *iter, DBusMessageIter *sub)`
///
/// Discards whatever was written to the sub-iterator, leaving the parent as it
/// was before the container was opened.
@_cdecl("dbus_message_iter_abandon_container")
public func abi_dbus_message_iter_abandon_container(_ iterator: UnsafeMutablePointer<DBusMessageIter>?,
                                                _ sub: UnsafeMutablePointer<DBusMessageIter>?) {

    guard let child = state(sub)
        else { return }

    child.items.removeAll()
    child.entries.removeAll()
    child.container = nil
    child.parent = nil
}
