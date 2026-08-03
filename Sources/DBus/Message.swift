//
//  Message.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 2/25/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

/// Message to be sent or received over a `DBusConnection`.
///
/// A `DBusMessage` is the most basic unit of communication over a `DBusConnection`.
/// A `DBusConnection` represents a stream of messages received from a remote application,
/// and a stream of messages sent to a remote application.
///
/// A message has header fields such as the sender, destination, method or signal name, and so forth.
///
/// - Note: This is a value type. It owns no external resource and can be freely copied and sent
/// across concurrency domains.
public struct DBusMessage: Equatable, Hashable, Sendable {

    /// The message type.
    public var type: DBusMessageType

    /// Message flags.
    public var flags: Flags

    /// The serial of a message, or `0` if none has been assigned.
    ///
    /// The message's serial number is provided by the application sending the message and
    /// is used to identify replies to this message.
    ///
    /// - Note: All messages received on a connection will have a serial provided by the remote
    /// application. For messages you send, `DBusConnection.send()` assigns a serial.
    public var serial: UInt32

    /// The object path this message is being sent to (for method call type)
    /// or the one a signal is being emitted from (for signal call type).
    public var path: DBusObjectPath?

    /// The interface this message is being sent to (for method call type)
    /// or the interface a signal is being emitted from (for signal call type).
    public var interface: DBusInterface?

    /// The interface member being invoked (for method call type) or emitted (for signal type).
    public var member: DBusMember?

    /// The name of the error (for `error` message type).
    public var errorName: DBusError.Name?

    /// The serial of the message this is a reply to.
    public var replySerial: UInt32?

    /// The name of another connection on the bus this message is addressed to.
    public var destination: DBusBusName?

    /// The message sender.
    ///
    /// - Note: Usually you don't set this. The message bus daemon sets the origin of each message.
    public var sender: DBusBusName?

    /// The number of Unix file descriptors that accompany this message.
    ///
    /// - Note: File descriptor passing is not yet implemented; this field is decoded and
    /// preserved so that a message round-trips, but the descriptors themselves are not
    /// transferred.
    public var unixFileDescriptorCount: UInt32?

    /// The message body.
    public var arguments: [DBusMessageArgument]

    public init(type: DBusMessageType,
                flags: Flags = [],
                serial: UInt32 = 0,
                path: DBusObjectPath? = nil,
                interface: DBusInterface? = nil,
                member: DBusMember? = nil,
                errorName: DBusError.Name? = nil,
                replySerial: UInt32? = nil,
                destination: DBusBusName? = nil,
                sender: DBusBusName? = nil,
                unixFileDescriptorCount: UInt32? = nil,
                arguments: [DBusMessageArgument] = []) {

        self.type = type
        self.flags = flags
        self.serial = serial
        self.path = path
        self.interface = interface
        self.member = member
        self.errorName = errorName
        self.replySerial = replySerial
        self.destination = destination
        self.sender = sender
        self.unixFileDescriptorCount = unixFileDescriptorCount
        self.arguments = arguments
    }
}

// MARK: - Computed Properties

public extension DBusMessage {

    /// The signature of the message body.
    var signature: DBusSignature {

        return arguments.signature
    }

    /// Whether the message contains Unix file descriptors.
    var containsFileDescriptors: Bool {

        return (unixFileDescriptorCount ?? 0) > 0
    }
}

// MARK: - Flags

public extension DBusMessage {

    /// Message header flags.
    struct Flags: OptionSet, Equatable, Hashable, Sendable {

        public var rawValue: UInt8

        public init(rawValue: UInt8) {

            self.rawValue = rawValue
        }

        /// This message does not expect method return messages or error messages,
        /// even if it is of a type that can have a reply; the reply should be omitted.
        ///
        /// - Note: If this flag is set, there is no way to know whether the message successfully
        /// arrived at the remote end.
        public static let noReplyExpected = Flags(rawValue: 0x01)

        /// The bus must not launch an owner for the destination name in response to this message.
        public static let noAutoStart = Flags(rawValue: 0x02)

        /// This message may prompt the user for interactive authorization
        /// (for instance via Polkit) before the actual method is processed.
        ///
        /// The flag is unset by default; that is, by default the other end is expected to make
        /// any authorization decisions non-interactively and promptly.
        public static let allowInteractiveAuthorization = Flags(rawValue: 0x04)
    }
}

// MARK: - Supporting Types

public extension DBusMessage {

    /// A method call to invoke on a remote object.
    struct MethodCall: Equatable, Hashable, Sendable {

        /// The name of the connection the call is addressed to.
        public var destination: DBusBusName?

        /// The object to invoke the method on.
        public var path: DBusObjectPath

        /// The interface the method belongs to.
        public var interface: DBusInterface?

        /// The method to invoke.
        public var method: DBusMember

        public init(destination: DBusBusName? = nil,
                    path: DBusObjectPath,
                    interface: DBusInterface? = nil,
                    method: DBusMember) {

            self.destination = destination
            self.path = path
            self.interface = interface
            self.method = method
        }
    }
}

public extension DBusMessage {

    /// A signal is identified by its originating object path, interface, and the name of the signal.
    struct Signal: Equatable, Hashable, Sendable {

        /// The object the signal is emitted from.
        public var path: DBusObjectPath

        /// The interface the signal belongs to.
        public var interface: DBusInterface

        /// The name of the signal.
        public var name: DBusMember

        public init(path: DBusObjectPath,
                    interface: DBusInterface,
                    name: DBusMember) {

            self.path = path
            self.interface = interface
            self.name = name
        }
    }
}

// MARK: - Initializers

public extension DBusMessage {

    /// Constructs a new message to invoke a method on a remote object.
    init(methodCall: MethodCall, arguments: [DBusMessageArgument] = []) {

        self.init(type: .methodCall,
                  path: methodCall.path,
                  interface: methodCall.interface,
                  member: methodCall.method,
                  destination: methodCall.destination,
                  arguments: arguments)
    }

    /// Constructs a message that is a reply to a method call.
    init(methodReturn replyTo: DBusMessage, arguments: [DBusMessageArgument] = []) {

        self.init(type: .methodReturn,
                  replySerial: replyTo.serial,
                  destination: replyTo.sender,
                  arguments: arguments)
    }

    /// Constructs a new message representing a signal emission.
    init(signal: Signal, arguments: [DBusMessageArgument] = []) {

        self.init(type: .signal,
                  path: signal.path,
                  interface: signal.interface,
                  member: signal.name,
                  arguments: arguments)
    }

    /// Creates a new message that is an error reply to another message.
    ///
    /// Error replies are most common in response to method calls, but can be returned in reply
    /// to any message. If you don't want to make up an error name just use
    /// `org.freedesktop.DBus.Error.Failed`.
    init(replyTo: DBusMessage, error: DBusError) {

        self.init(type: .error,
                  errorName: error.name,
                  replySerial: replyTo.serial,
                  destination: replyTo.sender,
                  arguments: [.string(error.message)])
    }
}

// MARK: - Error Extraction

public extension DBusError {

    /// Extract the error carried by an error-reply message.
    ///
    /// The name of the error is taken from the message's `errorName` header field, and the
    /// message text from the first argument if it exists and is a string.
    ///
    /// - Returns: `nil` if the message is not of type `error`.
    init?(message: DBusMessage) {

        guard message.type == .error,
            let name = message.errorName
            else { return nil }

        let text = message.arguments.first?.stringValue ?? ""

        self.init(name: name, message: text)
    }
}
