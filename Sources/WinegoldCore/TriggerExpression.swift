import Foundation

public indirect enum TriggerExpression: Codable, Equatable {
    case condition(field: String, operator: TriggerOperator, value: TriggerLiteral?)
    case and([TriggerExpression])
    case or([TriggerExpression])
    case not(TriggerExpression)
}


public extension TriggerExpression {
    var referencedFields: Set<String> {
        switch self {
        case let .condition(field, _, _): return [field]
        case let .and(children), let .or(children):
            return children.reduce(into: Set<String>()) { $0.formUnion($1.referencedFields) }
        case let .not(child): return child.referencedFields
        }
    }
}

public enum TriggerOperator: String, Codable, CaseIterable {
    case equals, contains, startsWith, endsWith, matches, `in`, notIn, exists
    case greaterThan, greaterThanOrEqual, lessThan, lessThanOrEqual
    case equalsCase, containsCase, startsWithCase, endsWithCase
}

public enum TriggerLiteral: Codable, Equatable {
    case string(String), number(Double), collection([String]), regex(String, String)
}

public enum TriggerValue: Equatable {
    case string(String), number(Double), bool(Bool), collection([String])
}

public struct TriggerParser {
    public init() {}

    public func parse(_ source: String) throws -> TriggerExpression {
        var lexer = Lexer(source)
        var parser = Parser(tokens: try lexer.tokens())
        let expression = try parser.parseExpression()
        guard parser.isAtEnd else { throw TriggerError.unexpected(parser.current.description) }
        return expression
    }
}

public struct TriggerSerializer {
    public init() {}

    public func serialize(_ expression: TriggerExpression) -> String { render(expression, parentPrecedence: 0) }

    private func render(_ expression: TriggerExpression, parentPrecedence: Int) -> String {
        let precedence: Int
        let value: String
        switch expression {
        case let .condition(field, op, literal):
            precedence = 4
            if let literal { value = "\(field) \(op.rawValue) \(render(literal))" } else { value = op == .exists ? "\(field) exists" : field }
        case let .not(child):
            precedence = 3
            value = "not \(render(child, parentPrecedence: precedence))"
        case let .and(children):
            precedence = 2
            value = children.map { render($0, parentPrecedence: precedence) }.joined(separator: " and ")
        case let .or(children):
            precedence = 1
            value = children.map { render($0, parentPrecedence: precedence) }.joined(separator: " or ")
        }
        return precedence < parentPrecedence ? "(\(value))" : value
    }

    private func render(_ literal: TriggerLiteral) -> String {
        switch literal {
        case let .string(value): return "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
        case let .number(value): return value.rounded() == value ? String(Int(value)) : String(value)
        case let .collection(values): return "{" + values.map { render(.string($0)) }.joined(separator: " ") + "}"
        case let .regex(pattern, flags): return "/\(pattern)/\(flags)"
        }
    }
}

public struct TriggerEvaluator {
    public init() {}

    public func evaluate(_ expression: TriggerExpression, values: [String: TriggerValue]) -> Bool {
        switch expression {
        case let .and(children): return children.allSatisfy { evaluate($0, values: values) }
        case let .or(children): return children.contains { evaluate($0, values: values) }
        case let .not(child): return !evaluate(child, values: values)
        case let .condition(field, op, literal):
            guard let value = values[field] else { return false }
            if op == .exists { return true }
            guard let literal else {
                if case let .bool(flag) = value { return flag }
                return false
            }
            return compare(value, op: op, literal: literal)
        }
    }

    private func compare(_ value: TriggerValue, op: TriggerOperator, literal: TriggerLiteral) -> Bool {
        if case let .number(lhs) = value, case let .number(rhs) = literal {
            switch op { case .equals: return lhs == rhs; case .greaterThan: return lhs > rhs; case .greaterThanOrEqual: return lhs >= rhs; case .lessThan: return lhs < rhs; case .lessThanOrEqual: return lhs <= rhs; default: return false }
        }
        if case let .collection(values) = value, case let .string(needle) = literal {
            return values.contains { $0.caseInsensitiveCompare(needle) == .orderedSame }
        }
        guard case let .string(lhs) = value else { return false }
        switch literal {
        case let .collection(values):
            if values.contains("*") { return op != .notIn }
            let found = values.contains { $0.caseInsensitiveCompare(lhs) == .orderedSame }
            return op == .notIn ? !found : found
        case let .regex(pattern, flags):
            let options: NSRegularExpression.Options = flags.contains("i") ? [.caseInsensitive] : []
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
            return regex.firstMatch(in: lhs, range: NSRange(lhs.startIndex..., in: lhs)) != nil
        case let .number(rhs): return compare(.number(Double(lhs) ?? .nan), op: op, literal: .number(rhs))
        case let .string(rhs):
            let sensitive = [.equalsCase, .containsCase, .startsWithCase, .endsWithCase].contains(op)
            let a = sensitive ? lhs : lhs.lowercased(), b = sensitive ? rhs : rhs.lowercased()
            switch op { case .equals, .equalsCase: return a == b; case .contains, .containsCase: return a.contains(b); case .startsWith, .startsWithCase: return a.hasPrefix(b); case .endsWith, .endsWithCase: return a.hasSuffix(b); case .in: return a == b; case .notIn: return a != b; default: return false }
        }
    }
}

public struct TriggerValidator {
    public init() {}
    public func issues(in expression: TriggerExpression) -> [String] {
        switch expression {
        case let .and(children), let .or(children): return children.flatMap(issues)
        case let .not(child): return issues(in: child)
        case let .condition(field, op, literal):
            let known = Set(["input", "parent", "parentName", "filename", "basename", "extension", "dotExtension", "inside", "desktop", "downloads", "timestamp", "kind", "mimeType", "uti", "size", "finderTags", "url", "scheme", "host", "urlPath", "query", "fragment", "text", "isFile", "isDirectory", "isURL", "isText"])
            if !known.contains(field) { return ["Unknown field: \(field)"] }
            let numeric = Set([TriggerOperator.greaterThan, .greaterThanOrEqual, .lessThan, .lessThanOrEqual])
            if numeric.contains(op), field != "size" { return ["\(op.rawValue) requires the numeric size field"] }
            if field == "size", !numeric.contains(op) && op != .equals && op != .exists { return ["\(op.rawValue) is not valid for size"] }
            let booleans = Set(["isFile", "isDirectory", "isURL", "isText"])
            if booleans.contains(field), literal != nil || op != .equals { return ["\(field) is a boolean shortcut and takes no operator"] }
            if numeric.contains(op), { if case .some(.number) = literal { return false }; return true }() { return ["\(op.rawValue) requires a number"] }
            return []
        }
    }
}

public enum TriggerError: LocalizedError, Equatable {
    case unexpected(String), unterminated(String), expected(String)
    public var errorDescription: String? { switch self { case let .unexpected(v): return "Unexpected token: \(v)"; case let .unterminated(v): return "Unterminated \(v)"; case let .expected(v): return "Expected \(v)" } }
}

private enum Token: Equatable, CustomStringConvertible {
    case word(String), string(String), number(Double), regex(String, String), leftParen, rightParen, leftBrace, rightBrace, end
    var description: String { switch self { case let .word(v): return v; case let .string(v): return "\"\(v)\""; case let .number(v): return String(v); case let .regex(v, f): return "/\(v)/\(f)"; case .leftParen: return "("; case .rightParen: return ")"; case .leftBrace: return "{"; case .rightBrace: return "}"; case .end: return "end of expression" } }
}

private struct Lexer {
    let chars: [Character]; var index = 0
    init(_ source: String) { chars = Array(source) }
    mutating func tokens() throws -> [Token] { var result: [Token] = []; while let token = try next() { result.append(token) }; result.append(.end); return result }
    mutating func next() throws -> Token? {
        while index < chars.count && chars[index].isWhitespace { index += 1 }; guard index < chars.count else { return nil }
        let char = chars[index]; index += 1
        if char == "(" { return .leftParen }; if char == ")" { return .rightParen }; if char == "{" { return .leftBrace }; if char == "}" { return .rightBrace }
        if char == "\"" { var value = ""; while index < chars.count { let c = chars[index]; index += 1; if c == "\"" { return .string(value) }; if c == "\\", index < chars.count { value.append(chars[index]); index += 1 } else { value.append(c) } }; throw TriggerError.unterminated("string") }
        if char == "/" { var value = "", escaped = false; while index < chars.count { let c = chars[index]; index += 1; if c == "/" && !escaped { var flags = ""; while index < chars.count && chars[index].isLetter { flags.append(chars[index]); index += 1 }; return .regex(value, flags) }; escaped = c == "\\" && !escaped; value.append(c) }; throw TriggerError.unterminated("regular expression") }
        var word = String(char); while index < chars.count && !chars[index].isWhitespace && !"(){}".contains(chars[index]) { word.append(chars[index]); index += 1 }
        if let number = Double(word) { return .number(number) }; return .word(word)
    }
}

private struct Parser {
    let tokens: [Token]; var index = 0; var current: Token { tokens[index] }; var isAtEnd: Bool { current == .end }
    mutating func advance() { if index < tokens.count - 1 { index += 1 } }
    mutating func parseExpression() throws -> TriggerExpression { try parseOr() }
    mutating func parseOr() throws -> TriggerExpression { var nodes = [try parseAnd()]; while current == .word("or") { advance(); nodes.append(try parseAnd()) }; return nodes.count == 1 ? nodes[0] : .or(nodes) }
    mutating func parseAnd() throws -> TriggerExpression { var nodes = [try parseUnary()]; while current == .word("and") { advance(); nodes.append(try parseUnary()) }; return nodes.count == 1 ? nodes[0] : .and(nodes) }
    mutating func parseUnary() throws -> TriggerExpression { if current == .word("not") { advance(); return .not(try parseUnary()) }; if current == .leftParen { advance(); let value = try parseExpression(); guard current == .rightParen else { throw TriggerError.expected(")") }; advance(); return value }; return try parseCondition() }
    mutating func parseCondition() throws -> TriggerExpression {
        guard case let .word(field) = current else { throw TriggerError.expected("field") }; advance()
        guard case let .word(raw) = current else { return .condition(field: field, operator: .equals, value: nil) }
        guard let op = TriggerOperator(rawValue: raw) else { return .condition(field: field, operator: .equals, value: nil) }; advance()
        if op == .exists { return .condition(field: field, operator: op, value: nil) }
        return .condition(field: field, operator: op, value: try parseLiteral())
    }
    mutating func parseLiteral() throws -> TriggerLiteral {
        switch current {
        case let .string(v): advance(); return .string(v)
        case let .number(v): advance(); return .number(v)
        case let .regex(v, f): advance(); return .regex(v, f)
        case .leftBrace:
            advance(); var values: [String] = []; while current != .rightBrace { guard case let .string(v) = current else { throw TriggerError.expected("quoted collection value") }; values.append(v); advance() }; advance(); return .collection(values)
        default: throw TriggerError.expected("value")
        }
    }
}
