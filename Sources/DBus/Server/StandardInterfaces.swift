//
//  StandardInterfaces.swift
//  DBus
//

import SystemPackage

// MARK: - Peer

internal extension DBusConnection {

    /// `org.freedesktop.DBus.Peer`: `Ping` and `GetMachineId`.
    ///
    /// Answered for any path, exported or not, because callers use `Ping` to test whether a
    /// connection is alive without knowing its object tree.
    func resolvePeer(_ call: DBusMethodCall) -> CallResolution {

        switch call.member.rawValue {

        case "Ping":
            guard call.arguments.isEmpty else {
                return .error(DBusError(name: .invalidArguments, message: "Ping takes no arguments"))
            }
            return .handler { _ in [] }

        case "GetMachineId":
            guard call.arguments.isEmpty else {
                return .error(DBusError(name: .invalidArguments, message: "GetMachineId takes no arguments"))
            }
            return .handler { _ in
                guard let machineID = MachineID.current
                    else { throw DBusError(name: .failed, message: "Could not read the machine ID") }
                return [.string(machineID)]
            }

        default:
            return .error(DBusError(name: .unknownMethod,
                                    message: "org.freedesktop.DBus.Peer has no method \(call.member)"))
        }
    }
}

/// The machine's D-Bus UUID.
internal enum MachineID {

    /// Locations the machine ID is read from, in the order the reference implementation uses.
    static let paths = ["/var/lib/dbus/machine-id", "/etc/machine-id"]

    /// The machine ID, read once.
    static let current: String? = {

        for path in paths {
            if let value = read(path) {
                return value
            }
        }

        return nil
    }()

    private static func read(_ path: String) -> String? {

        guard let descriptor = try? FileDescriptor.open(FilePath(path), .readOnly)
            else { return nil }

        defer { try? descriptor.close() }

        // The file holds a 32 character hex UUID and a newline.
        var buffer = [UInt8](repeating: 0, count: 64)

        guard let count = try? buffer.withUnsafeMutableBytes({ try descriptor.read(into: $0) }),
            count > 0
            else { return nil }

        let bytes = buffer[0 ..< count].prefix { $0 != 0x0A && $0 != 0x00 } // stop at newline or NUL

        guard bytes.isEmpty == false,
            let string = String(validating: Array(bytes), as: UTF8.self)
            else { return nil }

        return string
    }
}

// MARK: - Introspectable

internal extension DBusConnection {

    /// `org.freedesktop.DBus.Introspectable.Introspect`.
    func resolveIntrospectable(_ call: DBusMethodCall) -> CallResolution {

        guard call.member.rawValue == "Introspect" else {
            return .error(DBusError(name: .unknownMethod,
                                    message: "org.freedesktop.DBus.Introspectable has no method \(call.member)"))
        }

        guard call.arguments.isEmpty else {
            return .error(DBusError(name: .invalidArguments, message: "Introspect takes no arguments"))
        }

        // Snapshot on the actor so the handler closure needs no further isolation.
        let object = exportedObjects[call.path]
        let children = childNodeNames(of: call.path)

        return .handler { _ in
            [.string(DBusIntrospection.xml(for: object, children: children))]
        }
    }

    /// The names of exported objects directly beneath `path`.
    func childNodeNames(of path: DBusObjectPath) -> [String] {

        var names = Set<String>()

        for exported in exportedObjects.keys {

            guard exported != path,
                exported.count == path.count + 1,
                exported.isEqualToOrDescendant(of: path),
                let last = exported.last
                else { continue }

            names.insert(last.rawValue)
        }

        return names.sorted()
    }
}

/// Generates `org.freedesktop.DBus.Introspectable` XML.
public enum DBusIntrospection {

    /// The DTD declaration every introspection document begins with.
    public static let documentType = """
        <!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"
         "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
        """

    /// The introspection XML for an object and the child nodes beneath it.
    public static func xml(for object: DBusExportedObject?, children: [String] = []) -> String {

        var lines = [documentType, "<node>"]

        // The standard interfaces are always present, so advertise them.
        lines.append(contentsOf: standardInterfaceElements(includeProperties: object != nil))

        if let object = object {

            // Sorted so the output is stable between calls.
            for name in object.interfaces.keys.map({ $0.rawValue }).sorted() {

                guard let interface = object.interfaces[DBusInterface(rawValue: name)!]
                    else { continue }

                lines.append(contentsOf: elements(for: interface))
            }
        }

        for child in children {
            lines.append("  <node name=\"\(escape(child))\"/>")
        }

        lines.append("</node>")

        return lines.joined(separator: "\n") + "\n"
    }

    private static func elements(for interface: DBusInterfaceImplementation) -> [String] {

        var lines = ["  <interface name=\"\(escape(interface.name.rawValue))\">"]

        for name in interface.methods.keys.map({ $0.rawValue }).sorted() {

            guard let method = interface.methods[DBusMember(rawValue: name)!]
                else { continue }

            let arguments = argumentElements(method.inputSignature, method.inputNames, direction: "in")
                + argumentElements(method.outputSignature, method.outputNames, direction: "out")

            if arguments.isEmpty {
                lines.append("    <method name=\"\(escape(name))\"/>")
            } else {
                lines.append("    <method name=\"\(escape(name))\">")
                lines.append(contentsOf: arguments)
                lines.append("    </method>")
            }
        }

        for name in interface.signals.keys.map({ $0.rawValue }).sorted() {

            guard let signal = interface.signals[DBusMember(rawValue: name)!]
                else { continue }

            // Signal arguments carry no direction attribute.
            let arguments = argumentElements(signal.signature, signal.argumentNames, direction: nil)

            if arguments.isEmpty {
                lines.append("    <signal name=\"\(escape(name))\"/>")
            } else {
                lines.append("    <signal name=\"\(escape(name))\">")
                lines.append(contentsOf: arguments)
                lines.append("    </signal>")
            }
        }

        for name in interface.properties.keys.sorted() {

            guard let property = interface.properties[name]
                else { continue }

            lines.append("    <property name=\"\(escape(name))\" type=\"\(String(property.type))\" access=\"\(property.access.rawValue)\"/>")
        }

        lines.append("  </interface>")

        return lines
    }

    private static func argumentElements(_ signature: DBusSignature,
                                         _ names: [String],
                                         direction: String?) -> [String] {

        return signature.enumerated().map { index, type in

            var attributes = ""

            if index < names.count {
                attributes += " name=\"\(escape(names[index]))\""
            }

            attributes += " type=\"\(String(type))\""

            if let direction = direction {
                attributes += " direction=\"\(direction)\""
            }

            return "      <arg\(attributes)/>"
        }
    }

    private static func standardInterfaceElements(includeProperties: Bool) -> [String] {

        var lines = [
            "  <interface name=\"org.freedesktop.DBus.Peer\">",
            "    <method name=\"Ping\"/>",
            "    <method name=\"GetMachineId\">",
            "      <arg name=\"machine_uuid\" type=\"s\" direction=\"out\"/>",
            "    </method>",
            "  </interface>",
            "  <interface name=\"org.freedesktop.DBus.Introspectable\">",
            "    <method name=\"Introspect\">",
            "      <arg name=\"xml_data\" type=\"s\" direction=\"out\"/>",
            "    </method>",
            "  </interface>"
        ]

        guard includeProperties else { return lines }

        lines.append(contentsOf: [
            "  <interface name=\"org.freedesktop.DBus.Properties\">",
            "    <method name=\"Get\">",
            "      <arg name=\"interface_name\" type=\"s\" direction=\"in\"/>",
            "      <arg name=\"property_name\" type=\"s\" direction=\"in\"/>",
            "      <arg name=\"value\" type=\"v\" direction=\"out\"/>",
            "    </method>",
            "    <method name=\"Set\">",
            "      <arg name=\"interface_name\" type=\"s\" direction=\"in\"/>",
            "      <arg name=\"property_name\" type=\"s\" direction=\"in\"/>",
            "      <arg name=\"value\" type=\"v\" direction=\"in\"/>",
            "    </method>",
            "    <method name=\"GetAll\">",
            "      <arg name=\"interface_name\" type=\"s\" direction=\"in\"/>",
            "      <arg name=\"properties\" type=\"a{sv}\" direction=\"out\"/>",
            "    </method>",
            "    <signal name=\"PropertiesChanged\">",
            "      <arg name=\"interface_name\" type=\"s\"/>",
            "      <arg name=\"changed_properties\" type=\"a{sv}\"/>",
            "      <arg name=\"invalidated_properties\" type=\"as\"/>",
            "    </signal>",
            "  </interface>"
        ])

        return lines
    }

    /// Escape the five XML predefined entities.
    ///
    /// - Note: Validated names cannot contain any of these, but property and argument names
    /// are free-form strings supplied by the caller.
    internal static func escape(_ string: String) -> String {

        var result = ""
        result.reserveCapacity(string.count)

        for character in string {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default: result.append(character)
            }
        }

        return result
    }
}

// MARK: - Properties

internal extension DBusConnection {

    /// `org.freedesktop.DBus.Properties`: `Get`, `Set` and `GetAll`.
    func resolveProperties(_ call: DBusMethodCall, object: DBusExportedObject) -> CallResolution {

        switch call.member.rawValue {

        case "Get":
            guard case let .string(interfaceName)? = call.arguments.first,
                call.arguments.count == 2,
                case let .string(propertyName) = call.arguments[1]
                else { return .error(signatureError("Get", "ss")) }

            guard let property = property(named: propertyName, interface: interfaceName, object: object)
                else { return .error(unknownProperty(propertyName, interfaceName)) }

            guard property.access != .write, let get = property.get
                else { return .error(DBusError(name: .unknownProperty,
                                               message: "\(propertyName) is not readable")) }

            return .handler { _ in
                [.variant(DBusMessageArgument.Variant(try await get()))]
            }

        case "Set":
            guard case let .string(interfaceName)? = call.arguments.first,
                call.arguments.count == 3,
                case let .string(propertyName) = call.arguments[1],
                case let .variant(variant) = call.arguments[2]
                else { return .error(signatureError("Set", "ssv")) }

            guard let property = property(named: propertyName, interface: interfaceName, object: object)
                else { return .error(unknownProperty(propertyName, interfaceName)) }

            guard property.access != .read, let set = property.set
                else { return .error(DBusError(name: .propertyReadOnly,
                                               message: "\(propertyName) is read-only")) }

            let value = variant.element

            guard value.type == property.type
                else { return .error(DBusError(
                    name: .invalidArguments,
                    message: "\(propertyName) is '\(String(property.type))' but got '\(String(value.type))'")) }

            return .handler { _ in
                try await set(value)
                return []
            }

        case "GetAll":
            guard call.arguments.count == 1,
                case let .string(interfaceName)? = call.arguments.first
                else { return .error(signatureError("GetAll", "s")) }

            // An empty interface name means every interface on the object.
            let implementations: [DBusInterfaceImplementation]

            if interfaceName.isEmpty {
                implementations = Array(object.interfaces.values)
            } else {
                guard let interface = DBusInterface(rawValue: interfaceName),
                    let implementation = object.interfaces[interface]
                    else { return .error(DBusError(name: .unknownInterface,
                                                   message: "No such interface \(interfaceName)")) }
                implementations = [implementation]
            }

            // Collect the readable properties while on the actor; the getters run in the task.
            let readable = implementations
                .flatMap { $0.properties.values }
                .filter { $0.access != .write && $0.get != nil }
                .sorted { $0.name < $1.name }

            return .handler { _ in

                var entries = [DBusMessageArgument.Dictionary.Entry]()

                for property in readable {
                    let value = try await property.get!()
                    entries.append(.init(key: .string(property.name),
                                         value: .variant(DBusMessageArgument.Variant(value))))
                }

                guard let dictionary = DBusMessageArgument.Dictionary(keyType: .string,
                                                                      valueType: .variant,
                                                                      entries)
                    else { throw DBusError(name: .failed, message: "Could not build the property dictionary") }

                return [.dictionary(dictionary)]
            }

        default:
            return .error(DBusError(name: .unknownMethod,
                                    message: "org.freedesktop.DBus.Properties has no method \(call.member)"))
        }
    }

    private func property(named name: String,
                          interface interfaceName: String,
                          object: DBusExportedObject) -> DBusInterfaceImplementation.Property? {

        // An empty interface name means "search every interface", which the specification
        // permits when the property name is unambiguous.
        guard interfaceName.isEmpty == false else {
            return object.interfaces.values.compactMap { $0.properties[name] }.first
        }

        guard let interface = DBusInterface(rawValue: interfaceName)
            else { return nil }

        return object.interfaces[interface]?.properties[name]
    }

    private func signatureError(_ method: String, _ signature: String) -> DBusError {

        return DBusError(name: .invalidArguments,
                         message: "\(method) expects '\(signature)'")
    }

    private func unknownProperty(_ name: String, _ interface: String) -> DBusError {

        return DBusError(name: .unknownProperty,
                         message: "No property \(name) on \(interface.isEmpty ? "any interface" : interface)")
    }
}
