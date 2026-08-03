//
//  XMLParser.swift
//  DBus
//

/// A minimal XML reader for introspection documents.
///
/// Introspection XML is a small, fixed subset: elements, attributes, comments, an optional
/// declaration and doctype, and no meaningful text content. Parsing it here keeps the package
/// free of `FoundationXML`, which on Linux drags in libxml2.
///
/// - Note: Deliberately not a general XML parser. It rejects what it does not understand rather
/// than guessing.
internal struct XMLElement: Equatable {

    /// The element name.
    let name: String

    /// Attributes, in document order.
    let attributes: [String: String]

    /// Child elements.
    let children: [XMLElement]

    init(name: String, attributes: [String: String] = [:], children: [XMLElement] = []) {

        self.name = name
        self.attributes = attributes
        self.children = children
    }
}

internal extension XMLElement {

    /// Child elements with the given name.
    func children(named name: String) -> [XMLElement] {

        return children.filter { $0.name == name }
    }
}

// MARK: - Parsing

internal struct XMLReader {

    private let characters: [Character]
    private var position = 0

    private init(_ string: String) {

        self.characters = Array(string)
    }

    /// Parse a document and return its root element.
    static func parse(_ string: String) throws -> XMLElement {

        var reader = XMLReader(string)
        return try reader.parseDocument()
    }
}

private extension XMLReader {

    var isAtEnd: Bool { position >= characters.count }

    var current: Character? { isAtEnd ? nil : characters[position] }

    mutating func parseDocument() throws -> XMLElement {

        skipProlog()

        guard isAtEnd == false
            else { throw DBusProtocolError.invalidValue("XML document has no root element") }

        let root = try parseElement()

        skipProlog() // trailing comments and whitespace

        guard isAtEnd
            else { throw DBusProtocolError.invalidValue("Trailing content after the root element") }

        return root
    }

    /// Skip whitespace, comments, the XML declaration and the doctype.
    mutating func skipProlog() {

        while isAtEnd == false {

            skipWhitespace()

            guard match("<!--") || match("<?") || match("<!DOCTYPE")
                else { return }

            if consume("<!--") {
                skipUntil("-->")
            } else if consume("<?") {
                skipUntil("?>")
            } else if consume("<!DOCTYPE") {
                skipDoctype()
            }
        }
    }

    mutating func skipWhitespace() {

        while let character = current, character.isWhitespace {
            position += 1
        }
    }

    /// Whether the upcoming characters are `text`.
    func match(_ text: String) -> Bool {

        let expected = Array(text)

        guard position + expected.count <= characters.count
            else { return false }

        for (offset, character) in expected.enumerated() where characters[position + offset] != character {
            return false
        }

        return true
    }

    mutating func consume(_ text: String) -> Bool {

        guard match(text) else { return false }

        position += text.count
        return true
    }

    mutating func skipUntil(_ text: String) {

        while isAtEnd == false {

            if consume(text) { return }

            position += 1
        }
    }

    /// Skip a doctype, including any internal subset in brackets.
    mutating func skipDoctype() {

        var depth = 0

        while let character = current {

            position += 1

            switch character {
            case "\"", "'":
                // Skip a quoted literal, which may contain '>'.
                skipQuoted(character)
            case "[":
                depth += 1
            case "]":
                depth -= 1
            case ">" where depth <= 0:
                return
            default:
                break
            }
        }
    }

    mutating func skipQuoted(_ quote: Character) {

        while let character = current {
            position += 1
            if character == quote { return }
        }
    }

    mutating func parseElement() throws -> XMLElement {

        guard consume("<")
            else { throw DBusProtocolError.invalidValue("Expected an element") }

        let name = try parseName()

        var attributes = [String: String]()

        while true {

            skipWhitespace()

            if consume("/>") {
                return XMLElement(name: name, attributes: attributes)
            }

            if consume(">") {
                break
            }

            let (key, value) = try parseAttribute()

            guard attributes[key] == nil
                else { throw DBusProtocolError.invalidValue("Duplicate attribute '\(key)' on <\(name)>") }

            attributes[key] = value
        }

        var children = [XMLElement]()

        while true {

            skipWhitespace()

            if consume("<!--") {
                skipUntil("-->")
                continue
            }

            if consume("</") {

                let closing = try parseName()

                guard closing == name
                    else { throw DBusProtocolError.invalidValue("</\(closing)> closes <\(name)>") }

                skipWhitespace()

                guard consume(">")
                    else { throw DBusProtocolError.invalidValue("Unterminated closing tag for <\(name)>") }

                return XMLElement(name: name, attributes: attributes, children: children)
            }

            guard current == "<" else {

                // Character content, which introspection documents do not use meaningfully.
                guard isAtEnd == false
                    else { throw DBusProtocolError.invalidValue("Unterminated element <\(name)>") }

                position += 1
                continue
            }

            children.append(try parseElement())
        }
    }

    mutating func parseName() throws -> String {

        var name = ""

        while let character = current,
              character.isLetter || character.isNumber || character == "_" || character == "-"
                || character == ":" || character == "." {

            name.append(character)
            position += 1
        }

        guard name.isEmpty == false
            else { throw DBusProtocolError.invalidValue("Expected a name at offset \(position)") }

        return name
    }

    mutating func parseAttribute() throws -> (name: String, value: String) {

        let name = try parseName()

        skipWhitespace()

        guard consume("=")
            else { throw DBusProtocolError.invalidValue("Expected '=' after attribute '\(name)'") }

        skipWhitespace()

        guard let quote = current, quote == "\"" || quote == "'"
            else { throw DBusProtocolError.invalidValue("Attribute '\(name)' is not quoted") }

        position += 1

        var value = ""

        while let character = current, character != quote {

            position += 1

            guard character == "&" else {
                value.append(character)
                continue
            }

            value.append(try parseEntity())
        }

        guard consume(String(quote))
            else { throw DBusProtocolError.invalidValue("Unterminated value for attribute '\(name)'") }

        return (name, value)
    }

    /// Decode an entity reference, the `&` already consumed.
    mutating func parseEntity() throws -> Character {

        var reference = ""

        while let character = current, character != ";" {
            reference.append(character)
            position += 1
        }

        guard consume(";")
            else { throw DBusProtocolError.invalidValue("Unterminated entity reference '&\(reference)'") }

        switch reference {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        default:
            break
        }

        // Numeric character references.
        if reference.hasPrefix("#") {

            let digits = reference.dropFirst()

            let scalarValue: UInt32?

            if digits.hasPrefix("x") || digits.hasPrefix("X") {
                scalarValue = UInt32(digits.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(digits, radix: 10)
            }

            if let scalarValue = scalarValue, let scalar = Unicode.Scalar(scalarValue) {
                return Character(scalar)
            }
        }

        throw DBusProtocolError.invalidValue("Unknown entity reference '&\(reference);'")
    }
}
