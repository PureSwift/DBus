//
//  DBusMatchRule.swift
//  DBus
//

/// A rule describing which messages a connection wants the bus to deliver to it.
///
/// A connection receives no broadcast signals until it installs at least one match rule with
/// `AddMatch`. Every non-nil field must match for a message to be delivered; fields left `nil`
/// match anything.
///
/// Reference: https://dbus.freedesktop.org/doc/dbus-specification.html#message-bus-routing-match-rules
public struct DBusMatchRule: Equatable, Hashable, Sendable {

    /// The type of message to match.
    public var type: DBusMessageType?

    /// The name of the connection that sent the message.
    ///
    /// - Note: The bus rewrites the `sender` header field to the unique name of the sender, so a
    /// rule naming a well-known name is resolved by the bus at match time. Local matching
    /// therefore cannot reproduce it; see `matches(_:)`.
    public var sender: DBusBusName?

    /// The interface of the message.
    public var interface: DBusInterface?

    /// The member (method or signal name) of the message.
    public var member: DBusMember?

    /// The object path of the message.
    public var path: DBusObjectPath?

    /// Matches messages whose path is this path or a child of it.
    ///
    /// - Note: Mutually exclusive with `path`.
    public var pathNamespace: DBusObjectPath?

    /// The destination the message is addressed to.
    public var destination: DBusBusName?

    /// String arguments to match, by position.
    ///
    /// Only the first 64 arguments can be matched, and only string-like arguments.
    public var arguments: [Int: String]

    /// Matches when argument 0 is this namespace or a name within it.
    public var argument0Namespace: String?

    /// Matches when argument 0 is an object path equal to, or a child of, this path.
    public var argument0Path: String?

    /// Whether to receive messages not addressed to this connection.
    ///
    /// - Note: Requires the bus to be configured to permit eavesdropping, and is refused on a
    /// stock system bus.
    public var eavesdrop: Bool?

    public init(type: DBusMessageType? = nil,
                sender: DBusBusName? = nil,
                interface: DBusInterface? = nil,
                member: DBusMember? = nil,
                path: DBusObjectPath? = nil,
                pathNamespace: DBusObjectPath? = nil,
                destination: DBusBusName? = nil,
                arguments: [Int: String] = [:],
                argument0Namespace: String? = nil,
                argument0Path: String? = nil,
                eavesdrop: Bool? = nil) {

        self.type = type
        self.sender = sender
        self.interface = interface
        self.member = member
        self.path = path
        self.pathNamespace = pathNamespace
        self.destination = destination
        self.arguments = arguments
        self.argument0Namespace = argument0Namespace
        self.argument0Path = argument0Path
        self.eavesdrop = eavesdrop
    }
}

// MARK: - Constants

public extension DBusMatchRule {

    /// The highest argument index a match rule can reference.
    static let maximumArgumentIndex = 63
}

// MARK: - Convenience

public extension DBusMatchRule {

    /// A rule matching signals, optionally narrowed by interface, member and path.
    static func signal(interface: DBusInterface? = nil,
                       member: DBusMember? = nil,
                       path: DBusObjectPath? = nil,
                       sender: DBusBusName? = nil) -> DBusMatchRule {

        return DBusMatchRule(type: .signal,
                             sender: sender,
                             interface: interface,
                             member: member,
                             path: path)
    }

    /// A rule matching `org.freedesktop.DBus.NameOwnerChanged` for a particular name.
    ///
    /// Argument 0 of that signal is the name whose ownership changed.
    static func nameOwnerChanged(name: DBusBusName? = nil) -> DBusMatchRule {

        var rule = DBusMatchRule.signal(
            interface: DBusInterface(rawValue: "org.freedesktop.DBus")!,
            member: DBusMember(rawValue: "NameOwnerChanged")!,
            path: DBusObjectPath(rawValue: "/org/freedesktop/DBus")!,
            sender: DBusBusName(rawValue: "org.freedesktop.DBus")!
        )

        if let name = name {
            rule.arguments[0] = name.rawValue
        }

        return rule
    }

    /// A rule matching `org.freedesktop.DBus.Properties.PropertiesChanged`.
    static func propertiesChanged(interface: DBusInterface? = nil,
                                  path: DBusObjectPath? = nil,
                                  sender: DBusBusName? = nil) -> DBusMatchRule {

        var rule = DBusMatchRule.signal(
            interface: DBusInterface(rawValue: "org.freedesktop.DBus.Properties")!,
            member: DBusMember(rawValue: "PropertiesChanged")!,
            path: path,
            sender: sender
        )

        // Argument 0 of PropertiesChanged is the interface whose properties changed.
        if let interface = interface {
            rule.arguments[0] = interface.rawValue
        }

        return rule
    }
}

// MARK: - String Encoding

extension DBusMatchRule: RawRepresentable {

    /// The rule in the comma-separated `key='value'` form `AddMatch` expects.
    public var rawValue: String {

        var components = [String]()

        if let type = type {
            components.append("type=\(DBusMatchRule.escape(type.matchRuleName))")
        }

        if let sender = sender {
            components.append("sender=\(DBusMatchRule.escape(sender.rawValue))")
        }

        if let interface = interface {
            components.append("interface=\(DBusMatchRule.escape(interface.rawValue))")
        }

        if let member = member {
            components.append("member=\(DBusMatchRule.escape(member.rawValue))")
        }

        if let path = path {
            components.append("path=\(DBusMatchRule.escape(path.rawValue))")
        }

        if let pathNamespace = pathNamespace {
            components.append("path_namespace=\(DBusMatchRule.escape(pathNamespace.rawValue))")
        }

        if let destination = destination {
            components.append("destination=\(DBusMatchRule.escape(destination.rawValue))")
        }

        // Sorted so that the encoding is deterministic, which matters because the rule string
        // is the key used to reference count `AddMatch` and `RemoveMatch`.
        for index in arguments.keys.sorted() {
            components.append("arg\(index)=\(DBusMatchRule.escape(arguments[index]!))")
        }

        if let argument0Namespace = argument0Namespace {
            components.append("arg0namespace=\(DBusMatchRule.escape(argument0Namespace))")
        }

        if let argument0Path = argument0Path {
            components.append("arg0path=\(DBusMatchRule.escape(argument0Path))")
        }

        if let eavesdrop = eavesdrop {
            components.append("eavesdrop=\(DBusMatchRule.escape(eavesdrop ? "true" : "false"))")
        }

        return components.joined(separator: ",")
    }

    /// - Note: Parsing a rule back from its string form is not implemented; rules are built
    /// from their fields. This initializer exists only to satisfy `RawRepresentable` and
    /// always returns `nil`.
    public init?(rawValue: String) {

        return nil
    }
}

internal extension DBusMatchRule {

    /// Quote a value for inclusion in a match rule.
    ///
    /// Values are single quoted. A literal apostrophe cannot appear inside single quotes, so it
    /// is written by closing the quote, emitting an escaped apostrophe, and reopening:
    /// `it's` becomes `'it'\''s'`.
    static func escape(_ value: String) -> String {

        var result = "'"

        for character in value {
            if character == "'" {
                result += "'\\''"
            } else {
                result.append(character)
            }
        }

        result += "'"

        return result
    }
}

internal extension DBusMessageType {

    /// The name used for this type in a match rule.
    var matchRuleName: String {

        switch self {
        case .methodCall: return "method_call"
        case .methodReturn: return "method_return"
        case .error: return "error"
        case .signal: return "signal"
        }
    }
}

// MARK: - Local Matching

public extension DBusMatchRule {

    /// Whether a message satisfies this rule.
    ///
    /// The bus delivers the union of every rule a connection has installed, so a connection
    /// with several subscriptions must decide locally which one each message belongs to.
    ///
    /// - Note: `sender` is compared literally. The bus resolves a well-known name in a rule to
    /// the unique name that owns it, but a received message carries only the unique name, so a
    /// rule written with a well-known sender will not match here. Match on `interface` and
    /// `member` instead when routing locally.
    func matches(_ message: DBusMessage) -> Bool {

        if let type = type, message.type != type {
            return false
        }

        if let sender = sender, message.sender != sender {
            return false
        }

        if let interface = interface, message.interface != interface {
            return false
        }

        if let member = member, message.member != member {
            return false
        }

        if let path = path, message.path != path {
            return false
        }

        if let pathNamespace = pathNamespace {

            guard let messagePath = message.path,
                messagePath.isEqualToOrDescendant(of: pathNamespace)
                else { return false }
        }

        if let destination = destination, message.destination != destination {
            return false
        }

        for (index, value) in arguments {

            guard index < message.arguments.count,
                let argument = message.arguments[index].matchableString,
                argument == value
                else { return false }
        }

        if let namespace = argument0Namespace {

            guard let argument = message.arguments.first?.matchableString,
                argument == namespace || argument.hasPrefix(namespace + ".")
                else { return false }
        }

        if let value = argument0Path {

            // Matches when the argument equals the value, or when either is a path prefix of
            // the other and the shorter of the two ends in '/'.
            guard let argument = message.arguments.first?.matchableString,
                argument == value
                    || (value.hasSuffix("/") && argument.hasPrefix(value))
                    || (argument.hasSuffix("/") && value.hasPrefix(argument))
                else { return false }
        }

        return true
    }
}

internal extension DBusMessageArgument {

    /// The value as a string, for argument matching.
    ///
    /// Only `STRING`, `OBJECT_PATH` and `SIGNATURE` arguments can be matched.
    var matchableString: String? {

        switch self {
        case let .string(value): return value
        case let .objectPath(value): return value.rawValue
        case let .signature(value): return value.rawValue
        default: return nil
        }
    }
}

internal extension DBusObjectPath {

    /// Whether this path is `other`, or nested beneath it.
    func isEqualToOrDescendant(of other: DBusObjectPath) -> Bool {

        guard count >= other.count
            else { return false }

        return zip(self, other).allSatisfy { $0 == $1 }
    }
}

// MARK: - Description

extension DBusMatchRule: CustomStringConvertible {

    public var description: String {

        return rawValue
    }
}
