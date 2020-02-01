//
//  Message.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 2/25/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import CDBus

/// Message to be sent or received over a `DBusConnection`.
///
/// A `DBusMessage` is the most basic unit of communication over a `DBusConnection`.
/// A `DBusConnection` represents a stream of messages received from a remote application,
/// and a stream of messages sent to a remote application.
///
/// A message has header fields such as the sender, destination, method or signal name, and so forth.
///
public final class DBusMessage {
    
    // MARK: - Internal Properties
    
    internal let internalPointer: OpaquePointer
    
    // MARK: - Initialization
    
    deinit {
        
        dbus_message_unref(internalPointer)
    }
    
    internal init(_ internalPointer: OpaquePointer) {
        
        self.internalPointer = internalPointer
    }
    
    /// Constructs a new message of the given message type.
    public init(type: DBusMessageType) throws {
        
        guard let internalPointer = dbus_message_new(type.rawValue)
            else { throw DBusError.messageInitializationOutOfMemory }
        
        self.internalPointer = internalPointer
    }
    
    /// Creates a new message that is an error reply to another message.
    ///
    /// Error replies are most common in response to method calls, but can be returned in reply to any message.
    /// The error name must be a valid error name according to the syntax given in the D-Bus specification. 
    /// If you don't want to make up an error name just use `org.freedesktop.DBus.Error.Failed`.
    ///
    /// - Parameter error: A tuple consisting of the message to reply to, the error name, and the error message.
    public init(error: Error) throws {
        
        guard let internalPointer = dbus_message_new_error(error.replyTo.internalPointer, error.name.rawValue, error.message)
            else { throw DBusError.messageInitializationOutOfMemory }
        
        self.internalPointer = internalPointer
    }
    
    /// Constructs a new message to invoke a method on a remote object.
    ///
    /// - Note: Destination, path, interface, and method name can't contain any invalid characters (see the D-Bus specification).
    public init(methodCall: MethodCall) throws {
        
        // Returns NULL if memory can't be allocated for the message.
        guard let internalPointer = dbus_message_new_method_call(methodCall.destination?.rawValue, methodCall.path.rawValue, methodCall.interface?.rawValue, methodCall.method) else {
            throw DBusError.messageInitializationOutOfMemory
        }
        
        self.internalPointer = internalPointer
    }
    
    /// Constructs a message that is a reply to a method call.
    public init(methodReturn: DBusMessage) throws {
        
        guard let internalPointer = dbus_message_new_method_return(methodReturn.internalPointer)
            else { throw DBusError.messageInitializationOutOfMemory }
        
        self.internalPointer = internalPointer
    }
    
    /// Constructs a new message representing a signal emission.
    ///
    /// A signal is identified by its originating object path, interface, and the name of the signal.
    ///
    /// - Note: Path, interface, and signal name must all be valid.
    public init(signal: Signal) throws {
        
        guard let internalPointer = dbus_message_new_signal(signal.path, signal.interface, signal.name)
            else { throw DBusError.messageInitializationOutOfMemory }
        
        self.internalPointer = internalPointer
    }
    
    // MARK: - Methods
    
    /// Append argument.
    public func append(_ argument: DBusMessageArgument) throws {
        
        var iterator = DBusMessageIter(appending: self)
        try iterator.append(argument: argument)
    }
    
    /// Append contents of sequence.
    public func append <S: Sequence> (contentsOf sequence: S) throws where S.Element == DBusMessageArgument {
        
        var iterator = DBusMessageIter(appending: self)
        try sequence.forEach { try iterator.append(argument: $0) }
    }
    
    // MARK: - Properties
    
    /// The message type.
    public lazy var type: DBusMessageType = {
        
        let rawValue = dbus_message_get_type(internalPointer)
        
        guard let type = DBusMessageType(rawValue: rawValue)
            else { fatalError("Invalid DBus Message type: \(rawValue)") }
        
        return type
    }()
    
    /// Checks whether a message contains Unix file descriptors.
    public var containsFileDescriptors: Bool {
        
        return Bool(dbus_message_contains_unix_fds(internalPointer))
    }
    
    /// The serial of a message or `0` if none has been specified.
    ///
    /// The message's serial number is provided by the application sending the message and
    /// is used to identify replies to this message.
    ///
    /// - Note: All messages received on a connection will have a serial provided by the remote application.
    ///
    /// For messages you're sending, `DBusConnection.send()` will assign a serial and return it to you.
    public var serial: UInt32 {
        
        get { return dbus_message_get_serial(internalPointer) }
        
        set { dbus_message_set_serial(internalPointer, newValue) }
    }
    
    /// The reply serial of a message (the serial of the message this is a reply to).
    public var replySerial: UInt32 {
        
        return dbus_message_get_reply_serial(internalPointer)
    }
    
    /// Sets the reply serial of a message (the serial of the message this is a reply to).
    public func setReplySerial(_ newValue: UInt32) throws {
        
        guard Bool(dbus_message_set_reply_serial(internalPointer, newValue))
            else { throw DBusError.messageSetValueOutOfMemory }
    }
    
    /// Flag indicating that the caller of the method is prepared to wait for interactive authorization to take place 
    /// (for instance via Polkit) before the actual method is processed.
    ///
    /// The flag is `false` by default;
    /// that is, by default the other end is expected to make any authorization decisions non-interactively and promptly.
    public var allowInteractiveAuthorization: Bool {
        
        get { return Bool(dbus_message_get_allow_interactive_authorization(internalPointer)) }
        
        set { dbus_message_set_allow_interactive_authorization(internalPointer, dbus_bool_t(newValue)) }
    }
    
    /// Sets a flag indicating that an owner for the destination name will be automatically started before the message is delivered.
    ///
    /// When this flag is set, the message is held until a name owner finishes starting up, 
    /// or fails to start up. In case of failure, the reply will be an error.
    ///
    /// The flag is set to `true` by default, i.e. auto starting is the default.
    public var autoStart: Bool {
        
        get { return Bool(dbus_message_get_auto_start(internalPointer)) }
        
        set { dbus_message_set_auto_start(internalPointer, dbus_bool_t(newValue)) }
    }
    
    /// Flag indicating that the message does not want a reply; 
    /// if this flag is set, the other end of the connection may (but is not required to) 
    /// optimize by not sending method return or error replies.
    ///
    /// The flag is `false` by default, that is by default the other end is required to reply.
    ///
    /// - Note: If this flag is set, there is no way to know whether the message successfully arrived at the remote end. 
    /// Normally you know a message was received when you receive the reply to it.
    public var noReply: Bool {
        
        get { return Bool(dbus_message_get_no_reply(internalPointer)) }
        
        set { dbus_message_set_no_reply(internalPointer, dbus_bool_t(newValue)) }
    }
    
    /// The destination is the name of another connection on the bus 
    /// and may be either the unique name assigned by the bus to each connection,
    /// or a well-known name specified in advance.
    ///
    /// The destination name must contain only valid characters as defined in the D-Bus specification.
    public var destination: DBusBusName? {
        
        guard let string = getString(dbus_message_get_destination)
            else { return nil }
        
        return DBusBusName(string)
    }
    
    /// Sets the message's destination.
    public func setDestination(_ newValue: DBusBusName?) throws {
        
        try setString(dbus_message_set_destination, newValue?.rawValue)
    }
    
    /// The name of the error (for `Error` message type).
    ///
    /// The name is fully-qualified (namespaced). 
    /// The error name must contain only valid characters as defined in the D-Bus specification.
    public var errorName: DBusError.Name? {
        
        guard let string = getString(dbus_message_get_error_name)
            else { return nil }
        
        guard let name = DBusError.Name(rawValue: string)
            else { fatalError("Invalid error name \(string)") }
        
        return name
    }
    
    /// Sets the name of the error (DBUS_MESSAGE_TYPE_ERROR).
    /// The name is fully-qualified (namespaced).
    /// The error name must contain only valid characters as defined in the D-Bus specification.
    public func setErrorName(_ newValue: DBusError.Name?) throws {
        
        try setString(dbus_message_set_error_name, newValue?.rawValue)
    }
    
    /// The interface this message is being sent to (for method call type) 
    /// or the interface a signal is being emitted from (for signal call type).
    ///
    /// The interface name must contain only valid characters as defined in the D-Bus specification.
    public var interface: DBusInterface? {
        
        guard let string = getString(dbus_message_get_interface)
            else { return nil }
        
        guard let interface = DBusInterface(rawValue: string)
            else { fatalError("Invalid interface \(string)") }
        
        return interface
    }
    
    /// Sets the interface this message is being sent to (for `DBusMessageType.MethodCall`)
    /// or the interface a signal is being emitted from (for `DBusMessageType.Signal`).
    public func setInterface(_ newValue: DBusInterface?) throws {
        
        try setString(dbus_message_set_interface, newValue?.rawValue)
    }
    
    /// The object path this message is being sent to (for method call type)
    /// or the one a signal is being emitted from (for signal call type).
    ///
    /// The path must contain only valid characters as defined in the D-Bus specification.
    public var path: DBusObjectPath? {
        
        guard let string = getString(dbus_message_get_path)
            else { return nil }
        
        guard let objectPath = DBusObjectPath(rawValue: string)
            else { fatalError("Invalid object path \(string)") }
        
        return objectPath
    }
    
    /// Sets the object path this message is being sent to (for `DBusMessageType.MethodCall`)
    /// or the one a signal is being emitted from (for `DBusMessageType.Signal`).
    public func setPath(_ newValue: DBusObjectPath?) throws {
        
        try setString(dbus_message_set_path, newValue?.rawValue)
    }
    
    /// The interface member being invoked (for method call type) or emitted (for signal type).
    ///
    /// The member name must contain only valid characters as defined in the D-Bus specification.
    public var member: DBusMember? {
        
        guard let string = getString(dbus_message_get_member)
            else { return nil }
        
        guard let member = DBusMember(rawValue: string)
            else { fatalError("Invalid member \(string)") }
        
        return member
    }
    
    /// Sets the interface member being invoked (`DBusMessageType.MethodCall`)
    /// or emitted (`DBusMessageType.Signal`).
    ///
    /// The member name must contain only valid characters as defined in the D-Bus specification.
    public func setMember(_ newValue: DBusMember?) throws {
        
        try setString(dbus_message_set_member, newValue?.rawValue)
    }
    
    /// The message sender.
    ///
    /// The sender must be a valid bus name as defined in the D-Bus specification.
    ///
    /// - Note: Usually you don't want to call this. 
    /// The message bus daemon will call it to set the origin of each message. 
    /// If you aren't implementing a message bus daemon you shouldn't need to set the sender.
    public var sender: DBusBusName? {
        
        guard let string = getString(dbus_message_get_sender)
            else { return nil }
        
        return DBusBusName(string)
    }
    
    /// Sets the message sender.
    ///
    /// The sender must be a valid bus name as defined in the D-Bus specification.
    ///
    /// - Note: Usually you don't want to call this.
    /// The message bus daemon will call it to set the origin of each message.
    /// If you aren't implementing a message bus daemon you shouldn't need to set the sender.
    public func setSender(_ newValue: DBusBusName?) throws {
        
        try setString(dbus_message_set_sender, newValue?.rawValue)
    }
    
    // MARK: - Private Methods
    
    private func getString(_ function: (OpaquePointer?) -> (UnsafePointer<Int8>?)) -> String? {
        
        // should not be free
        guard let cString = function(internalPointer)
            else { return nil }
        
        return String(cString: cString)
    }
    
    private func setString(_ function: (OpaquePointer?, UnsafePointer<Int8>?) -> (dbus_bool_t), _ newValue: String?) throws {
        
        if let newValue = newValue {
            
            guard Bool(newValue.withCString({ function(internalPointer, $0) }))
                else { throw DBusError.messageSetValueOutOfMemory }
            
        } else {
            
            guard Bool(function(internalPointer, nil))
                else { throw DBusError.messageSetValueOutOfMemory }
        }
    }
}

// MARK: - Copying

public extension DBusMessage {
    
    /**
     Creates a new message that is an exact replica of the message specified, except that its refcount is set to 1, its message serial is reset to 0, and if the original message was "locked" (in the outgoing message queue and thus not modifiable) the new message will not be locked.
    */
    func copy() throws -> DBusMessage {
        
        guard let copyPointer = dbus_message_copy(internalPointer)
            else { throw DBusError(name: .noMemory, message: "Could not copy message") }
        
        let copyMessage = DBusMessage(copyPointer)
        
        return copyMessage
    }
}

// MARK: - Sequence

extension DBusMessage: Sequence {
    
    public typealias Element = DBusMessageArgument
    
    public func makeIterator() -> Iterator {
        
        return Iterator(self)
    }
}

public extension DBusMessage {
    
    /// DBus Message Iterator
    struct Iterator: IteratorProtocol {
        
        public typealias Element = DBusMessageArgument
        
        /// Internal libdbus iterator
        internal private(set) var internalValue: DBusMessageIter
        
        /// Intialize for iterating the specifed message.
        internal init(_ message: DBusMessage) {
            
            // Message doesnt need to be retained becuase this should only be called while the message is still >= 1 ARC.
            self.internalValue = DBusMessageIter(iterating: message)
        }
        
        public mutating func next() -> DBusMessageArgument? {
            
            return internalValue.next()
        }
    }
}

// MARK: - Supporting Types

public extension DBusMessage {
    
    struct Error {
        
        public let replyTo: DBusMessage
        public let name: DBusError.Name
        public let message: String
        
        public init(replyTo: DBusMessage, name: DBusError.Name, message: String) {
            
            self.replyTo = replyTo
            self.name = name
            self.message = message
        }
        
        public init(replyTo: DBusMessage, error: DBusError) {
            
            self.init(replyTo: replyTo, name: error.name, message: error.message)
        }
    }
}

public extension DBusMessage {
    
    struct MethodCall {
        
        public let destination: DBusBusName?
        public let path: DBusObjectPath
        public let interface: DBusInterface?
        public let method: String
    }
}

public extension DBusMessage {
    
    /// A signal is identified by its originating object path, interface, and the name of the signal.
    struct Signal {
        
        public let path: String
        public let interface: String
        public let name: String
    }
}

internal extension DBusError.Reference {
    
    /**
     Sets a DBusError based on the contents of the given message.
     
     The error is only set if the message is an error message, as in `DBusMessageType.error`. The name of the error is set to the name of the message, and the error message is set to the first argument if the argument exists and is a string.
    */
    convenience init?(message: DBusMessage) {
        
        guard message.type == .error
            else { return nil }
        
        self.init()
        guard Bool(dbus_set_error_from_message(&self.internalValue, message.internalPointer))
            else { return nil }
        
        assert(isEmpty == false)
    }
}

public extension DBusError {
    
    /**
     Sets a DBusError based on the contents of the given message.
     
     The error is only set if the message is an error message, as in `DBusMessageType.error`. The name of the error is set to the name of the message, and the error message is set to the first argument if the argument exists and is a string.
     */
    init?(message: DBusMessage) {
        
        guard let reference = Reference(message: message)
            else { return nil }
        
        self.init(reference)
    }
}

// MARK: - Private Extensions

private extension DBusError {
    
    // Could not initialize message due to lack of memory.
    static var messageInitializationOutOfMemory: DBusError {
        
        return DBusError(name: .noMemory, message: "Could not initialize message due to lack of memory.")
    }
    
    // Could not modify message due to lack of memory.
    static var messageSetValueOutOfMemory: DBusError {
        
        // If this fails due to lack of memory, the message is hosed and you have to start over building the whole message.
        // FALSE if not enough memory
        return DBusError(name: .noMemory, message: "Could not modify message due to lack of memory.")
    }
}
