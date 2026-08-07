//
//  Memory.swift
//  DBus
//
//  `dbus_malloc` and friends.
//
//  The reference routes every allocation it hands to a caller through these,
//  so that a caller can free one with `dbus_free` regardless of which
//  allocator the library was built against. They are plain wrappers here,
//  which is all they need to be: every pointer this library returns comes
//  from the same C allocator these use.
//

import Foundation
import CDBusABI

/// `void *dbus_malloc(size_t bytes)`
///
/// Returns NULL for a zero byte request, as the reference does, so that
/// `dbus_free` on the result is always valid.
@_cdecl("dbus_malloc")
public func abi_dbus_malloc(_ bytes: Int) -> UnsafeMutableRawPointer? {

    guard bytes > 0
        else { return nil }

    return malloc(bytes)
}

/// `void *dbus_malloc0(size_t bytes)`
@_cdecl("dbus_malloc0")
public func abi_dbus_malloc0(_ bytes: Int) -> UnsafeMutableRawPointer? {

    guard bytes > 0
        else { return nil }

    return calloc(1, bytes)
}

/// `void dbus_free(void *memory)`
@_cdecl("dbus_free")
public func abi_dbus_free(_ memory: UnsafeMutableRawPointer?) {

    free(memory)
}

/// `void dbus_free_string_array(char **string_array)`
///
/// Frees a NULL terminated array of strings and the array itself.
@_cdecl("dbus_free_string_array")
public func abi_dbus_free_string_array(_ array: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) {

    guard let array = array
        else { return }

    var index = 0
    while let element = array[index] {
        free(element)
        index += 1
    }

    free(array)
}

/// `dbus_bool_t dbus_threads_init_default(void)`
///
/// A no-op returning TRUE. The reference needs an explicit opt-in before it is
/// safe to use from more than one thread; this implementation is thread safe
/// by construction, so there is nothing to switch on, and callers that
/// dutifully call it keep working.
@_cdecl("dbus_threads_init_default")
public func abi_dbus_threads_init_default() -> dbus_bool_t {

    return true.cBool
}

/// `void dbus_shutdown(void)`
///
/// A no-op. The reference frees global state that this implementation does not
/// keep; the shared connections are released by their own reference counts.
@_cdecl("dbus_shutdown")
public func abi_dbus_shutdown() {

    // Deliberately empty.
}
