//
//  DBusExportedObject.swift
//  DBus
//

/// An object made available to other connections at an object path.
///
/// Build one from ``DBusInterfaceImplementation`` values and register it with
/// ``DBusConnection/export(_:at:)``. The standard interfaces `Peer`, `Introspectable` and
/// `Properties` are supplied automatically.
public struct DBusExportedObject: Sendable {

    /// The interfaces this object implements, keyed by name.
    public private(set) var interfaces: [DBusInterface: DBusInterfaceImplementation]

    public init(_ interfaces: [DBusInterfaceImplementation] = []) {

        self.interfaces = [:]

        for implementation in interfaces {
            self.interfaces[implementation.name] = implementation
        }
    }

    /// Add or replace an interface.
    public mutating func add(_ implementation: DBusInterfaceImplementation) {

        interfaces[implementation.name] = implementation
    }
}

// MARK: - Interface

/// The implementation of a single interface on an exported object.
public struct DBusInterfaceImplementation: Sendable {

    /// The interface name.
    public let name: DBusInterface

    /// The methods the interface exposes, keyed by member name.
    public private(set) var methods: [DBusMember: Method]

    /// The properties the interface exposes, keyed by property name.
    public private(set) var properties: [String: Property]

    /// The signals the interface may emit, for introspection only.
    public private(set) var signals: [DBusMember: Signal]

    public init(name: DBusInterface,
                methods: [Method] = [],
                properties: [Property] = [],
                signals: [Signal] = []) {

        self.name = name
        self.methods = [:]
        self.properties = [:]
        self.signals = [:]

        for method in methods {
            self.methods[method.name] = method
        }

        for property in properties {
            self.properties[property.name] = property
        }

        for signal in signals {
            self.signals[signal.name] = signal
        }
    }
}

// MARK: - Method

public extension DBusInterfaceImplementation {

    /// A method that can be invoked on the interface.
    struct Method: Sendable {

        /// The method name.
        public let name: DBusMember

        /// The signature of the arguments the method accepts.
        public let inputSignature: DBusSignature

        /// The signature of the values the method returns.
        public let outputSignature: DBusSignature

        /// Names for the input arguments, for introspection. May be shorter than the signature.
        public let inputNames: [String]

        /// Names for the output arguments, for introspection.
        public let outputNames: [String]

        /// The implementation.
        ///
        /// - Throws: A `DBusError` to send an error reply; anything else becomes
        /// `org.freedesktop.DBus.Error.Failed`.
        public let handler: @Sendable (DBusMethodCall) async throws -> [DBusMessageArgument]

        public init(name: DBusMember,
                    inputSignature: DBusSignature = DBusSignature(),
                    outputSignature: DBusSignature = DBusSignature(),
                    inputNames: [String] = [],
                    outputNames: [String] = [],
                    handler: @escaping @Sendable (DBusMethodCall) async throws -> [DBusMessageArgument]) {

            self.name = name
            self.inputSignature = inputSignature
            self.outputSignature = outputSignature
            self.inputNames = inputNames
            self.outputNames = outputNames
            self.handler = handler
        }
    }
}

// MARK: - Property

public extension DBusInterfaceImplementation {

    /// A property exposed through `org.freedesktop.DBus.Properties`.
    struct Property: Sendable {

        /// Whether a property may be read, written, or both.
        public enum Access: String, Sendable {

            case read
            case write
            case readwrite
        }

        /// The property name.
        public let name: String

        /// The type of the property's value.
        public let type: DBusSignature.ValueType

        /// Whether the property is readable, writable or both.
        public let access: Access

        /// Reads the current value. Required unless the property is write-only.
        public let get: (@Sendable () async throws -> DBusMessageArgument)?

        /// Writes a new value. Required unless the property is read-only.
        public let set: (@Sendable (DBusMessageArgument) async throws -> Void)?

        public init(name: String,
                    type: DBusSignature.ValueType,
                    access: Access = .read,
                    get: (@Sendable () async throws -> DBusMessageArgument)? = nil,
                    set: (@Sendable (DBusMessageArgument) async throws -> Void)? = nil) {

            self.name = name
            self.type = type
            self.access = access
            self.get = get
            self.set = set
        }
    }
}

// MARK: - Signal

public extension DBusInterfaceImplementation {

    /// A signal the interface may emit. Declared for introspection; emitting is done with
    /// ``DBusConnection/emit(_:arguments:)``.
    struct Signal: Sendable {

        public let name: DBusMember

        public let signature: DBusSignature

        public let argumentNames: [String]

        public init(name: DBusMember,
                    signature: DBusSignature = DBusSignature(),
                    argumentNames: [String] = []) {

            self.name = name
            self.signature = signature
            self.argumentNames = argumentNames
        }
    }
}

// MARK: - Method Call

/// An incoming method call handed to a ``DBusInterfaceImplementation/Method`` handler.
public struct DBusMethodCall: Sendable {

    /// The full message, for handlers that need the header fields.
    public let message: DBusMessage

    /// The object path the call was addressed to.
    public let path: DBusObjectPath

    /// The interface the call named, if any.
    public let interface: DBusInterface?

    /// The method being invoked.
    public let member: DBusMember

    /// The call's arguments.
    public var arguments: [DBusMessageArgument] { message.arguments }

    /// The unique name of the caller, as stamped by the bus.
    public var sender: DBusBusName? { message.sender }

    /// Whether the caller wants a reply.
    public var expectsReply: Bool { message.flags.contains(.noReplyExpected) == false }

    internal init(message: DBusMessage,
                  path: DBusObjectPath,
                  interface: DBusInterface?,
                  member: DBusMember) {

        self.message = message
        self.path = path
        self.interface = interface
        self.member = member
    }
}
