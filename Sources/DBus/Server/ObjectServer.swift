//
//  ObjectServer.swift
//  DBus
//

// MARK: - Exporting

public extension DBusConnection {

    /// Make an object available to other connections at the given path.
    ///
    /// The standard interfaces `org.freedesktop.DBus.Peer`, `.Introspectable` and `.Properties`
    /// are answered automatically and do not need to be part of `object`.
    func export(_ object: DBusExportedObject, at path: DBusObjectPath) {

        exportedObjects[path] = object
    }

    /// Remove a previously exported object.
    @discardableResult
    func unexport(at path: DBusObjectPath) -> DBusExportedObject? {

        return exportedObjects.removeValue(forKey: path)
    }

    /// The object exported at the given path, if any.
    func exportedObject(at path: DBusObjectPath) -> DBusExportedObject? {

        return exportedObjects[path]
    }

    /// Every path this connection has exported an object at.
    var exportedPaths: [DBusObjectPath] {

        return Array(exportedObjects.keys)
    }

    /// Emit a signal from an exported object.
    func emit(_ signal: DBusMessage.Signal,
              arguments: [DBusMessageArgument] = [],
              destination: DBusBusName? = nil) async throws {

        var message = DBusMessage(signal: signal, arguments: arguments)
        message.destination = destination

        try await send(oneWay: message)
    }

    /// Emit `org.freedesktop.DBus.Properties.PropertiesChanged` for an object.
    ///
    /// - Parameters:
    ///   - changed: Property names and their new values.
    ///   - invalidated: Names of properties whose value changed but is not being broadcast.
    func emitPropertiesChanged(at path: DBusObjectPath,
                               interface: DBusInterface,
                               changed: [String: DBusMessageArgument] = [:],
                               invalidated: [String] = []) async throws {

        let entries = changed.keys.sorted().map { key in
            DBusMessageArgument.Dictionary.Entry(
                key: .string(key),
                value: .variant(DBusMessageArgument.Variant(changed[key]!))
            )
        }

        guard let dictionary = DBusMessageArgument.Dictionary(keyType: .string,
                                                              valueType: .variant,
                                                              entries)
            else { throw DBusProtocolError.invalidValue("Could not build the changed properties dictionary") }

        guard let invalidatedArray = DBusMessageArgument.Array(type: .string,
                                                               invalidated.map { .string($0) })
            else { throw DBusProtocolError.invalidValue("Could not build the invalidated properties array") }

        let signal = DBusMessage.Signal(path: path,
                                        interface: DBusWellKnown.propertiesInterface,
                                        name: DBusMember("PropertiesChanged"))

        try await emit(signal, arguments: [
            .string(interface.rawValue),
            .dictionary(dictionary),
            .array(invalidatedArray)
        ])
    }
}

// MARK: - Dispatch

internal extension DBusConnection {

    /// Route an incoming method call to an exported object.
    ///
    /// Runs the handler on a detached task so a slow implementation cannot stall the read loop,
    /// and replies with the result or with an error.
    func handleMethodCall(_ message: DBusMessage) {

        guard let path = message.path, let member = message.member else {
            Task { await self.replyWithError(to: message,
                                             DBusError(name: .invalidArguments,
                                                       message: "Method call is missing a path or member")) }
            return
        }

        let call = DBusMethodCall(message: message,
                                  path: path,
                                  interface: message.interface,
                                  member: member)

        // Resolve while on the actor, so the handler closure is all the task needs.
        let resolution = resolve(call)

        switch resolution {

        case let .handler(handler):
            Task {
                do {
                    let results = try await handler(call)
                    await self.reply(to: message, arguments: results)
                }
                catch let error as DBusError {
                    await self.replyWithError(to: message, error)
                }
                catch {
                    await self.replyWithError(to: message,
                                              DBusError(name: .failed, message: "\(error)"))
                }
            }

        case let .error(error):
            Task { await self.replyWithError(to: message, error) }

        case .unhandled:
            // Nothing claims it; hand it to the catch-all so a caller can implement its own
            // routing, and only error if there is no handler either.
            if let messageHandler = messageHandler {
                messageHandler(message)
            } else {
                Task { await self.replyWithError(to: message,
                                                 DBusError(name: .unknownObject,
                                                           message: "No object is exported at \(path)")) }
            }
        }
    }

    /// What should happen to an incoming call.
    enum CallResolution {

        case handler(@Sendable (DBusMethodCall) async throws -> [DBusMessageArgument])
        case error(DBusError)
        case unhandled
    }

    func resolve(_ call: DBusMethodCall) -> CallResolution {

        // The standard interfaces are answered for any exported path.
        if let interface = call.interface, interface == DBusWellKnown.peerInterface {
            return resolvePeer(call)
        }

        guard let object = exportedObjects[call.path] else {

            // Peer.Ping is answered even at an unexported path, which is how callers check
            // that a connection is alive.
            return .unhandled
        }

        if let interface = call.interface {

            if interface == DBusWellKnown.introspectableInterface {
                return resolveIntrospectable(call)
            }

            if interface == DBusWellKnown.propertiesInterface {
                return resolveProperties(call, object: object)
            }

            guard let implementation = object.interfaces[interface] else {
                return .error(DBusError(name: .unknownInterface,
                                        message: "\(call.path) does not implement \(interface)"))
            }

            guard let method = implementation.methods[call.member] else {
                return .error(DBusError(name: .unknownMethod,
                                        message: "\(interface) has no method \(call.member)"))
            }

            return validated(method, call: call)
        }

        // Without an interface field the member must be unambiguous across the object.
        let candidates = object.interfaces.values.compactMap { $0.methods[call.member] }

        guard let method = candidates.first else {
            return .error(DBusError(name: .unknownMethod,
                                    message: "\(call.path) has no method \(call.member)"))
        }

        guard candidates.count == 1 else {
            return .error(DBusError(name: .unknownMethod,
                                    message: "\(call.member) is ambiguous on \(call.path); specify an interface"))
        }

        return validated(method, call: call)
    }

    /// Check the call's signature before invoking the handler.
    private func validated(_ method: DBusInterfaceImplementation.Method,
                           call: DBusMethodCall) -> CallResolution {

        let actual = call.arguments.signature

        guard actual == method.inputSignature else {
            return .error(DBusError(
                name: .invalidArguments,
                message: "\(method.name) expects '\(method.inputSignature.rawValue)' but got '\(actual.rawValue)'"))
        }

        return .handler(method.handler)
    }
}

// MARK: - Replying

internal extension DBusConnection {

    func reply(to message: DBusMessage, arguments: [DBusMessageArgument]) async {

        guard message.flags.contains(.noReplyExpected) == false
            else { return }

        let reply = DBusMessage(methodReturn: message, arguments: arguments)

        // There is no one to report a send failure to; the connection's own error handling
        // covers a dead socket.
        _ = try? await send(oneWay: reply)
    }

    func replyWithError(to message: DBusMessage, _ error: DBusError) async {

        guard message.flags.contains(.noReplyExpected) == false
            else { return }

        _ = try? await send(oneWay: DBusMessage(replyTo: message, error: error))
    }
}
