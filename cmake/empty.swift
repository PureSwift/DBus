//
//  empty.swift
//  DBus
//
//  Placeholder translation unit.
//
//  CMake requires a shared library target to have at least one source of its
//  own; every exported symbol actually arrives from the Swift and C static
//  archives, linked whole (see CMakeLists.txt).
//
//  It is Swift rather than C, and it imports, because swiftc decides which
//  runtime libraries to record as dependencies of the output from the modules
//  it sees imported while linking. Whole-archive input does not count: with a
//  C placeholder the library came out referencing Foundation, Dispatch and the
//  concurrency runtime without declaring a dependency on any of them, and
//  every consumer failed to link.
//

import Foundation
import Dispatch
