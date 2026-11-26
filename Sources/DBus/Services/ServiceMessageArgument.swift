// MIT License
//
// Copyright (c) 2026 Miller Technology
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

public typealias DBusValue = DBusMessageArgument
public typealias DBusVariant = DBusMessageArgument.Variant

public extension DBusMessageArgument {
    var unwrapped: DBusValue {
        if case .variant(let variant) = self { return variant.element.unwrapped }
        return self
    }

    /// An object path's text, or a string's.
    var pathValue: String? {
        if case .objectPath(let path) = unwrapped { return path.rawValue }
        return stringValue
    }

    var boolValue: Bool? {
        if case .boolean(let value) = unwrapped { return value }
        return nil
    }

    var intValue: Int? {
        switch unwrapped {
        case .byte(let value): Int(exactly: value)
        case .int16(let value): Int(exactly: value)
        case .uint16(let value): Int(exactly: value)
        case .int32(let value): Int(exactly: value)
        case .uint32(let value): Int(exactly: value)
        case .int64(let value): Int(exactly: value)
        case .uint64(let value): Int(exactly: value)
        default: nil
        }
    }

    /// ay.
    var bytes: [UInt8]? {
        guard case .array(let elements) = unwrapped else { return nil }
        return elements.compactMap { if case .byte(let byte) = $0 { byte } else { nil } }
    }

    var stringArray: [String] {
        guard case .array(let elements) = unwrapped else { return [] }
        return elements.compactMap(\.stringValue)
    }

    /// ay.
    static func byteArray(_ bytes: [UInt8]) -> DBusValue {
        .array(Array(type: .byte, bytes.map { .byte($0) })!)
    }

    /// as.
    static func strings(_ strings: [String]) -> DBusValue {
        .array(Array(type: .string, strings.map { .string($0) })!)
    }

    /// a{sv}, each value in a variant.
    static func options(_ entries: [String: DBusValue] = [:]) -> DBusValue {
        .dictionary(Dictionary(keyType: .string, valueType: .variant,
                               entries.sorted { $0.key < $1.key }.map { .init(key: .string($0.key), value: .variant(DBusVariant($0.value))) })!)
    }
}
