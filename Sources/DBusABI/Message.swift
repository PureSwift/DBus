//
//  Message.swift
//  DBus
//
//  `dbus_message_*` — construction, reference counting and header accessors.
//

import Foundation
import CDBusABI
import DBus

// MARK: - Storage

/// The object a `DBusMessage *` points at.
///
/// `DBus.DBusMessage` is a value type, so the box supplies the reference
/// identity the C ABI is built around. It also owns the strings returned by
/// the `dbus_message_get_*` accessors: those return a borrowed `const char *`
/// that the reference keeps alive as long as the message, so each is cached
/// here rather than freshly allocated and leaked.
internal final class MessageBox: Box {

    var message: DBus.DBusMessage

    /// Iterator states created from this message, kept alive until it dies.
    ///
    /// A `DBusMessageIter` is a stack value with no destructor, so its state
    /// cannot be freed by the caller. The reference stores the state inline;
    /// here it lives out of line and is tied to the message's lifetime, which
    /// matches the documented rule that an iterator is valid only while its
    /// message is.
    var iterators: [IteratorState] = []

    private var strings: [String: UnsafeMutablePointer<CChar>] = [:]

    /// Copies handed out by `dbus_message_iter_get_basic` for string values.
    ///
    /// That entry point yields a borrowed pointer the caller must not free, so
    /// each copy lives as long as the message, exactly as in the reference.
    private var temporaries: [UnsafeMutablePointer<CChar>] = []

    init(_ message: DBus.DBusMessage) {

        self.message = message
    }

    deinit {

        strings.values.forEach { free($0) }
        temporaries.forEach { free($0) }
    }

    /// A borrowed C string valid while the message is.
    func borrowedCopy(_ value: String) -> UnsafePointer<CChar>? {

        guard let copy = strdup(value)
            else { return nil }

        temporaries.append(copy)
        return UnsafePointer(copy)
    }

    /// A borrowed C string for a header field, valid while the message is.
    func borrowedString(_ key: String, _ value: String?) -> UnsafePointer<CChar>? {

        guard let value = value else {
            if let existing = strings.removeValue(forKey: key) { free(existing) }
            return nil
        }

        if let existing = strings[key], strcmp(existing, value) == 0 {
            return UnsafePointer(existing)
        }

        if let existing = strings.removeValue(forKey: key) { free(existing) }

        guard let copy = strdup(value)
            else { return nil }

        strings[key] = copy
        return UnsafePointer(copy)
    }
}

internal func message(_ pointer: OpaquePointer?) -> MessageBox? {

    guard let pointer = pointer
        else { return nil }

    return Box.unretained(pointer)
}

// MARK: - Construction

/// `DBusMessage *dbus_message_new(int message_type)`
@_cdecl("dbus_message_new")
public func abi_dbus_message_new(_ messageType: Int32) -> OpaquePointer? {

    guard let type = DBusMessageType(rawValue: UInt8(truncatingIfNeeded: messageType))
        else { return nil }

    return MessageBox(DBus.DBusMessage(type: type)).retainedPointer()
}

/// `DBusMessage *dbus_message_new_method_call(const char *, const char *, const char *, const char *)`
///
/// Returns NULL if any argument is not valid for its field, which is what the
/// reference does for a malformed path, interface or member.
@_cdecl("dbus_message_new_method_call")
public func abi_dbus_message_new_method_call(_ destination: UnsafePointer<CChar>?,
                                         _ path: UnsafePointer<CChar>?,
                                         _ interface: UnsafePointer<CChar>?,
                                         _ method: UnsafePointer<CChar>?) -> OpaquePointer? {

    guard let pathString = string(path),
          let objectPath = DBusObjectPath(rawValue: pathString),
          let methodString = string(method),
          let member = DBusMember(rawValue: methodString)
        else { return nil }

    var busName: DBusBusName?
    if let destinationString = string(destination) {
        guard let name = DBusBusName(rawValue: destinationString)
            else { return nil }
        busName = name
    }

    var interfaceName: DBusInterface?
    if let interfaceString = string(interface) {
        guard let name = DBusInterface(rawValue: interfaceString)
            else { return nil }
        interfaceName = name
    }

    let call = DBus.DBusMessage.MethodCall(destination: busName,
                                           path: objectPath,
                                           interface: interfaceName,
                                           method: member)

    return MessageBox(DBus.DBusMessage(methodCall: call)).retainedPointer()
}

/// `DBusMessage *dbus_message_new_method_return(DBusMessage *method_call)`
@_cdecl("dbus_message_new_method_return")
public func abi_dbus_message_new_method_return(_ methodCall: OpaquePointer?) -> OpaquePointer? {

    guard let call = message(methodCall)
        else { return nil }

    var reply = DBus.DBusMessage(type: .methodReturn)
    reply.replySerial = call.message.serial
    reply.destination = call.message.sender

    return MessageBox(reply).retainedPointer()
}

/// `DBusMessage *dbus_message_new_signal(const char *, const char *, const char *)`
@_cdecl("dbus_message_new_signal")
public func abi_dbus_message_new_signal(_ path: UnsafePointer<CChar>?,
                                    _ interface: UnsafePointer<CChar>?,
                                    _ name: UnsafePointer<CChar>?) -> OpaquePointer? {

    guard let pathString = string(path),
          let objectPath = DBusObjectPath(rawValue: pathString),
          let interfaceString = string(interface),
          let interfaceName = DBusInterface(rawValue: interfaceString),
          let memberString = string(name),
          let member = DBusMember(rawValue: memberString)
        else { return nil }

    let signal = DBus.DBusMessage.Signal(path: objectPath,
                                         interface: interfaceName,
                                         name: member)

    return MessageBox(DBus.DBusMessage(signal: signal)).retainedPointer()
}

/// `DBusMessage *dbus_message_new_error(DBusMessage *, const char *, const char *)`
@_cdecl("dbus_message_new_error")
public func abi_dbus_message_new_error(_ replyTo: OpaquePointer?,
                                   _ errorName: UnsafePointer<CChar>?,
                                   _ errorMessage: UnsafePointer<CChar>?) -> OpaquePointer? {

    guard let original = message(replyTo),
          let nameString = string(errorName),
          let name = DBus.DBusError.Name(rawValue: nameString)
        else { return nil }

    var reply = DBus.DBusMessage(type: .error)
    reply.errorName = name
    reply.replySerial = original.message.serial
    reply.destination = original.message.sender

    if let text = string(errorMessage) {
        reply.arguments = [.string(text)]
    }

    return MessageBox(reply).retainedPointer()
}

// MARK: - Reference counting

/// `DBusMessage *dbus_message_ref(DBusMessage *message)`
@_cdecl("dbus_message_ref")
public func abi_dbus_message_ref(_ message: OpaquePointer?) -> OpaquePointer? {

    guard let message = message
        else { return nil }

    Box.retain(message)
    return message
}

/// `void dbus_message_unref(DBusMessage *message)`
@_cdecl("dbus_message_unref")
public func abi_dbus_message_unref(_ message: OpaquePointer?) {

    guard let message = message
        else { return }

    Box.release(message)
}

/// `DBusMessage *dbus_message_copy(const DBusMessage *message)`
@_cdecl("dbus_message_copy")
public func abi_dbus_message_copy(_ original: OpaquePointer?) -> OpaquePointer? {

    guard let box = message(original)
        else { return nil }

    return MessageBox(box.message).retainedPointer()
}

// MARK: - Header fields

/// `int dbus_message_get_type(DBusMessage *message)`
@_cdecl("dbus_message_get_type")
public func abi_dbus_message_get_type(_ message: OpaquePointer?) -> Int32 {

    guard let box = DBusABI.message(message)
        else { return Int32(DBUS_MESSAGE_TYPE_INVALID) }

    return Int32(box.message.type.rawValue)
}

/// `dbus_uint32_t dbus_message_get_serial(DBusMessage *message)`
@_cdecl("dbus_message_get_serial")
public func abi_dbus_message_get_serial(_ message: OpaquePointer?) -> dbus_uint32_t {

    return DBusABI.message(message)?.message.serial ?? 0
}

/// `dbus_uint32_t dbus_message_get_reply_serial(DBusMessage *message)`
@_cdecl("dbus_message_get_reply_serial")
public func abi_dbus_message_get_reply_serial(_ message: OpaquePointer?) -> dbus_uint32_t {

    return DBusABI.message(message)?.message.replySerial ?? 0
}

/// `dbus_bool_t dbus_message_set_path(DBusMessage *message, const char *path)`
@_cdecl("dbus_message_set_path")
public func abi_dbus_message_set_path(_ message: OpaquePointer?,
                                  _ path: UnsafePointer<CChar>?) -> dbus_bool_t {

    guard let box = DBusABI.message(message)
        else { return false.cBool }

    guard let value = string(path) else {
        box.message.path = nil
        return true.cBool
    }

    guard let objectPath = DBusObjectPath(rawValue: value)
        else { return false.cBool }

    box.message.path = objectPath
    return true.cBool
}

/// `const char *dbus_message_get_path(DBusMessage *message)`
@_cdecl("dbus_message_get_path")
public func abi_dbus_message_get_path(_ message: OpaquePointer?) -> UnsafePointer<CChar>? {

    guard let box = DBusABI.message(message)
        else { return nil }

    return box.borrowedString("path", box.message.path?.rawValue)
}

/// `dbus_bool_t dbus_message_set_interface(DBusMessage *message, const char *interface)`
@_cdecl("dbus_message_set_interface")
public func abi_dbus_message_set_interface(_ message: OpaquePointer?,
                                       _ interface: UnsafePointer<CChar>?) -> dbus_bool_t {

    guard let box = DBusABI.message(message)
        else { return false.cBool }

    guard let value = string(interface) else {
        box.message.interface = nil
        return true.cBool
    }

    guard let name = DBusInterface(rawValue: value)
        else { return false.cBool }

    box.message.interface = name
    return true.cBool
}

/// `const char *dbus_message_get_interface(DBusMessage *message)`
@_cdecl("dbus_message_get_interface")
public func abi_dbus_message_get_interface(_ message: OpaquePointer?) -> UnsafePointer<CChar>? {

    guard let box = DBusABI.message(message)
        else { return nil }

    return box.borrowedString("interface", box.message.interface?.rawValue)
}

/// `dbus_bool_t dbus_message_set_member(DBusMessage *message, const char *member)`
@_cdecl("dbus_message_set_member")
public func abi_dbus_message_set_member(_ message: OpaquePointer?,
                                    _ member: UnsafePointer<CChar>?) -> dbus_bool_t {

    guard let box = DBusABI.message(message)
        else { return false.cBool }

    guard let value = string(member) else {
        box.message.member = nil
        return true.cBool
    }

    guard let name = DBusMember(rawValue: value)
        else { return false.cBool }

    box.message.member = name
    return true.cBool
}

/// `const char *dbus_message_get_member(DBusMessage *message)`
@_cdecl("dbus_message_get_member")
public func abi_dbus_message_get_member(_ message: OpaquePointer?) -> UnsafePointer<CChar>? {

    guard let box = DBusABI.message(message)
        else { return nil }

    return box.borrowedString("member", box.message.member?.rawValue)
}

/// `dbus_bool_t dbus_message_set_destination(DBusMessage *message, const char *destination)`
@_cdecl("dbus_message_set_destination")
public func abi_dbus_message_set_destination(_ message: OpaquePointer?,
                                         _ destination: UnsafePointer<CChar>?) -> dbus_bool_t {

    guard let box = DBusABI.message(message)
        else { return false.cBool }

    guard let value = string(destination) else {
        box.message.destination = nil
        return true.cBool
    }

    guard let name = DBusBusName(rawValue: value)
        else { return false.cBool }

    box.message.destination = name
    return true.cBool
}

/// `const char *dbus_message_get_destination(DBusMessage *message)`
@_cdecl("dbus_message_get_destination")
public func abi_dbus_message_get_destination(_ message: OpaquePointer?) -> UnsafePointer<CChar>? {

    guard let box = DBusABI.message(message)
        else { return nil }

    return box.borrowedString("destination", box.message.destination?.rawValue)
}

/// `dbus_bool_t dbus_message_set_sender(DBusMessage *message, const char *sender)`
@_cdecl("dbus_message_set_sender")
public func abi_dbus_message_set_sender(_ message: OpaquePointer?,
                                    _ sender: UnsafePointer<CChar>?) -> dbus_bool_t {

    guard let box = DBusABI.message(message)
        else { return false.cBool }

    guard let value = string(sender) else {
        box.message.sender = nil
        return true.cBool
    }

    guard let name = DBusBusName(rawValue: value)
        else { return false.cBool }

    box.message.sender = name
    return true.cBool
}

/// `const char *dbus_message_get_sender(DBusMessage *message)`
@_cdecl("dbus_message_get_sender")
public func abi_dbus_message_get_sender(_ message: OpaquePointer?) -> UnsafePointer<CChar>? {

    guard let box = DBusABI.message(message)
        else { return nil }

    return box.borrowedString("sender", box.message.sender?.rawValue)
}

/// `dbus_bool_t dbus_message_set_error_name(DBusMessage *message, const char *name)`
@_cdecl("dbus_message_set_error_name")
public func abi_dbus_message_set_error_name(_ message: OpaquePointer?,
                                        _ name: UnsafePointer<CChar>?) -> dbus_bool_t {

    guard let box = DBusABI.message(message)
        else { return false.cBool }

    guard let value = string(name) else {
        box.message.errorName = nil
        return true.cBool
    }

    guard let errorName = DBus.DBusError.Name(rawValue: value)
        else { return false.cBool }

    box.message.errorName = errorName
    return true.cBool
}

/// `const char *dbus_message_get_error_name(DBusMessage *message)`
@_cdecl("dbus_message_get_error_name")
public func abi_dbus_message_get_error_name(_ message: OpaquePointer?) -> UnsafePointer<CChar>? {

    guard let box = DBusABI.message(message)
        else { return nil }

    return box.borrowedString("errorName", box.message.errorName?.rawValue)
}

/// `const char *dbus_message_get_signature(DBusMessage *message)`
@_cdecl("dbus_message_get_signature")
public func abi_dbus_message_get_signature(_ message: OpaquePointer?) -> UnsafePointer<CChar>? {

    guard let box = DBusABI.message(message)
        else { return nil }

    return box.borrowedString("signature", box.message.signature.rawValue)
}

/// `void dbus_message_set_no_reply(DBusMessage *message, dbus_bool_t no_reply)`
@_cdecl("dbus_message_set_no_reply")
public func abi_dbus_message_set_no_reply(_ message: OpaquePointer?, _ noReply: dbus_bool_t) {

    guard let box = DBusABI.message(message)
        else { return }

    if noReply != 0 {
        box.message.flags.insert(.noReplyExpected)
    } else {
        box.message.flags.remove(.noReplyExpected)
    }
}

/// `dbus_bool_t dbus_message_get_no_reply(DBusMessage *message)`
@_cdecl("dbus_message_get_no_reply")
public func abi_dbus_message_get_no_reply(_ message: OpaquePointer?) -> dbus_bool_t {

    guard let box = DBusABI.message(message)
        else { return false.cBool }

    return box.message.flags.contains(.noReplyExpected).cBool
}

// MARK: - Predicates

private func matches(_ actual: String?, _ expected: UnsafePointer<CChar>?) -> Bool {

    guard let expected = string(expected)
        else { return actual == nil }

    return actual == expected
}

/// `dbus_bool_t dbus_message_is_method_call(DBusMessage *, const char *, const char *)`
@_cdecl("dbus_message_is_method_call")
public func abi_dbus_message_is_method_call(_ message: OpaquePointer?,
                                        _ interface: UnsafePointer<CChar>?,
                                        _ method: UnsafePointer<CChar>?) -> dbus_bool_t {

    guard let box = DBusABI.message(message), box.message.type == .methodCall
        else { return false.cBool }

    return (matches(box.message.interface?.rawValue, interface)
            && matches(box.message.member?.rawValue, method)).cBool
}

/// `dbus_bool_t dbus_message_is_signal(DBusMessage *, const char *, const char *)`
@_cdecl("dbus_message_is_signal")
public func abi_dbus_message_is_signal(_ message: OpaquePointer?,
                                   _ interface: UnsafePointer<CChar>?,
                                   _ signalName: UnsafePointer<CChar>?) -> dbus_bool_t {

    guard let box = DBusABI.message(message), box.message.type == .signal
        else { return false.cBool }

    return (matches(box.message.interface?.rawValue, interface)
            && matches(box.message.member?.rawValue, signalName)).cBool
}

/// `dbus_bool_t dbus_message_is_error(DBusMessage *message, const char *error_name)`
@_cdecl("dbus_message_is_error")
public func abi_dbus_message_is_error(_ message: OpaquePointer?,
                                  _ errorName: UnsafePointer<CChar>?) -> dbus_bool_t {

    guard let box = DBusABI.message(message), box.message.type == .error
        else { return false.cBool }

    return matches(box.message.errorName?.rawValue, errorName).cBool
}

/// `dbus_bool_t dbus_message_has_path(DBusMessage *message, const char *path)`
@_cdecl("dbus_message_has_path")
public func abi_dbus_message_has_path(_ message: OpaquePointer?,
                                  _ path: UnsafePointer<CChar>?) -> dbus_bool_t {

    guard let box = DBusABI.message(message)
        else { return false.cBool }

    return matches(box.message.path?.rawValue, path).cBool
}

/// `dbus_bool_t dbus_message_has_member(DBusMessage *message, const char *member)`
@_cdecl("dbus_message_has_member")
public func abi_dbus_message_has_member(_ message: OpaquePointer?,
                                    _ member: UnsafePointer<CChar>?) -> dbus_bool_t {

    guard let box = DBusABI.message(message)
        else { return false.cBool }

    return matches(box.message.member?.rawValue, member).cBool
}

/// `dbus_bool_t dbus_message_has_interface(DBusMessage *message, const char *interface)`
@_cdecl("dbus_message_has_interface")
public func abi_dbus_message_has_interface(_ message: OpaquePointer?,
                                       _ interface: UnsafePointer<CChar>?) -> dbus_bool_t {

    guard let box = DBusABI.message(message)
        else { return false.cBool }

    return matches(box.message.interface?.rawValue, interface).cBool
}

/// `dbus_bool_t dbus_message_has_destination(DBusMessage *message, const char *name)`
@_cdecl("dbus_message_has_destination")
public func abi_dbus_message_has_destination(_ message: OpaquePointer?,
                                         _ name: UnsafePointer<CChar>?) -> dbus_bool_t {

    guard let box = DBusABI.message(message)
        else { return false.cBool }

    return matches(box.message.destination?.rawValue, name).cBool
}

/// `dbus_bool_t dbus_message_has_sender(DBusMessage *message, const char *name)`
@_cdecl("dbus_message_has_sender")
public func abi_dbus_message_has_sender(_ message: OpaquePointer?,
                                    _ name: UnsafePointer<CChar>?) -> dbus_bool_t {

    guard let box = DBusABI.message(message)
        else { return false.cBool }

    return matches(box.message.sender?.rawValue, name).cBool
}
