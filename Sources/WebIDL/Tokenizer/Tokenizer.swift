//
//  Created by Manuel Burghard. Licensed unter MIT.
//

import Foundation

///
public typealias Tokens = [Token]

public struct TokenisationResult: CustomStringConvertible {

    public let tokens: Tokens
    public let identifiers: [String]
    public let integers: [Int]
    public let decimals: [Double]
    public let strings: [String]
    public let others: [String]

    func merging(_ other: TokenisationResult) -> TokenisationResult {

        TokenisationResult(tokens: tokens + other.tokens,
                           identifiers: identifiers + other.identifiers,
                           integers: integers + other.integers,
                           decimals: decimals + other.decimals,
                           strings: strings + other.strings,
                           others: others + other.others)
    }

    public var description: String {

        var identifiers = self.identifiers
        var integers = self.integers
        var decimals = self.decimals
        var strings = self.strings
        var others = self.others

        var stringValues = [String]()

        var iterator = tokens.makeIterator()
        while let token = iterator.next() {

            switch token {
            case .terminal(.closingSquareBracket): stringValues.append("]\n")
            case .terminal(.openingCurlyBraces): stringValues.append("{\n")
            case .terminal(.semicolon): stringValues.append(";\n")
            case .terminal(let symbol): stringValues.append(symbol.rawValue)
            case .identifier: stringValues.append(identifiers.removeFirst())
            case .integer: stringValues.append(String(integers.removeFirst()))
            case .decimal: stringValues.append(String(decimals.removeFirst()))
            case .string: stringValues.append("\"\(strings.removeFirst())\"")
            case .comment(let comment): stringValues.append("// \(comment)\n")
            case .multilineComment(let comment): stringValues.append("/*\n\(comment)\n*/")
            case .other: stringValues.append(others.removeFirst())
            }
        }

        return stringValues.joined(separator: " ")
    }
}

extension NSRegularExpression {

    func match(_ string: String) -> Bool {
        let fullRange = NSRange(string.startIndex ..< string.endIndex, in: string)
        guard let firstMatch = self.firstMatch(in: string, options: [], range: fullRange) else {
            return false
        }
        return firstMatch.range == fullRange
    }
}

// swiftlint:disable type_body_length
/// `Tokenizer` converts an input string, file, or directory with files into a token stream.
public enum Tokenizer {

    // swiftlint:disable force_try
    static let integerRegex = try! NSRegularExpression(pattern: #"-?([1-9][0-9]*|0[Xx][0-9A-Fa-f]+|0[0-7]*)"#)
    static let decimalRegex = try! NSRegularExpression(pattern: #"-?(([0-9]+\.[0-9]*|[0-9]*\.[0-9]+)([Ee][+-]?[0-9]+)?|[0-9]+[Ee][+-]?[0-9]+)"#)
    static let identifierRegex = try! NSRegularExpression(pattern: #"[_-]?[A-Za-z][0-9A-Z_a-z-]*"#)
    static let otherRegex = try! NSRegularExpression(pattern: #"[^\t\n\r 0-9A-Za-z]"#)
    // swiftlint:enable force_try

    /// Tokenize all `.webidl` files in the given directory
    /// - Parameter directoryURL: An URL to a directory that contains `.webidl` files
    /// - Throws: Any error related to the file operations or the tokenization operation.
    /// - Returns: A `TokenisationResult` instance containing the token stream for the given files.
    public static func tokenize(filesInDirectoryAt directoryURL: URL) throws -> TokenisationResult? {

        var tokenisationResult = TokenisationResult(tokens: [], identifiers: [], integers: [], decimals: [], strings: [], others: [])
        let files = try FileManager.default.contentsOfDirectory(at: directoryURL,
                                                                includingPropertiesForKeys: nil,
                                                                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants])
        for file in files where file.pathExtension == "webidl" {

            guard let result = try Tokenizer.tokenize(fileAt: file) else {
                continue
            }
            tokenisationResult = tokenisationResult.merging(result)
        }
        return tokenisationResult
    }

    /// Tokenize a single Web IDL file
    /// - Parameter fileURL: An URL to a file containing Web IDL definitions.
    /// - Throws: Any error related to the file operations or the tokenization operation.
    /// - Returns: A `TokenisationResult` instance containing the token stream for the given file.
    public static func tokenize(fileAt fileURL: URL) throws -> TokenisationResult? {

        let fileData = try Data(contentsOf: fileURL)
        guard let string = String(data: fileData, encoding: .utf8) else {
            return nil
        }
        return try tokenize(string)
    }

    // swiftlint:disable cyclomatic_complexity function_body_length
    /// Tokenize Web IDL definitions
    /// - Parameter string: A string containing Web IDL definitions.
    /// - Throws: Any error related to the file operations or the tokenization operation.
    /// - Returns: A `TokenisationResult` instance containing the token stream for the given file.
    public static func tokenize(_ string: String) throws -> TokenisationResult {

        var tokens = Tokens()

        var state = State.regular
        var buffer = ""

        func reset() {
            state = .regular
            buffer = ""
        }

        var identifiers: [String] = []
        var integers: [Int] = []
        var decimals: [Double] = []
        var strings: [String] = []
        var others: [String] = []

        func appendIntegerLiteral() {
            defer { reset() }
            guard let integer = Int(buffer) else {
                return
            }
            tokens.append(.integer)
            integers.append(integer)
        }

        func appendHexLiteral() {
            defer { reset() }
            guard let integer = Int(buffer, radix: 16) else {
                return
            }
            tokens.append(.integer)
            integers.append(integer)
        }

        func appendDecimalLiteral() {
            defer { reset() }
            guard let double = Double(buffer) else {
                return
            }
            tokens.append(.decimal)
            decimals.append(double)
        }

        func appendIdentifier() {
            if let symbol = Terminal(rawValue: buffer) {
                tokens.append(.terminal(symbol))
            } else if identifierRegex.match(buffer) {
                tokens.append(.identifier)
                identifiers.append(buffer)
            } else if integerRegex.match(buffer), let integer = Int(buffer) ?? Int(buffer, radix: 16) {
                tokens.append(.integer)
                integers.append(integer)
            } else if decimalRegex.match(buffer), let double = Double(buffer) {
                tokens.append(.decimal)
                decimals.append(double)
            } else if otherRegex.match(buffer) {
                tokens.append(.other)
                others.append(buffer)
            } else {
                print("Undefined sequence: \(buffer)")
            }
            reset()
        }

        for character in string {

            switch (state, character) {
            case (.identifier, "["):
                appendIdentifier()
                tokens.append(.terminal(.openingSquareBracket))

            case (.regular, "["):
                tokens.append(.terminal(.openingSquareBracket))

            case (.identifier, "]"):
                appendIdentifier()
                fallthrough

            case (.regular, "]"):
                tokens.append(.terminal(.closingSquareBracket))

            case (.identifier, "("):
                appendIdentifier()
                fallthrough

            case (.regular, "("):
                tokens.append(.terminal(.openingParenthesis))

            case (.identifier, ")"):
                appendIdentifier()
                tokens.append(.terminal(.closingParenthesis))

            case (.integerLiteral, ")"):
                appendIntegerLiteral()
                tokens.append(.terminal(.closingParenthesis))

            case (.hexLiteral, ")"):
                appendHexLiteral()
                tokens.append(.terminal(.closingParenthesis))

            case (.regular, ")"):
                tokens.append(.terminal(.closingParenthesis))

            case (.identifier, "<"):
                appendIdentifier()
                tokens.append(.terminal(.openingAngleBracket))

            case (.regular, "<"):
                tokens.append(.terminal(.openingAngleBracket))

            case (.identifier, ">"):
                appendIdentifier()
                tokens.append(.terminal(.closingAngleBracket))

            case (.regular, ">"):
                tokens.append(.terminal(.closingAngleBracket))

            case (.identifier, "{"):
                appendIdentifier()
                tokens.append(.terminal(.openingCurlyBraces))

            case (.regular, "{"):
                tokens.append(.terminal(.openingCurlyBraces))

            case (.identifier, "}"):
                appendIdentifier()
                tokens.append(.terminal(.closingCurlyBraces))

            case (.regular, "}"):
                tokens.append(.terminal(.closingCurlyBraces))

            case (.identifier, "?"):
                appendIdentifier()
                tokens.append(.terminal(.questionMark))

            case (.regular, "?"):
                tokens.append(.terminal(.questionMark))

            case (.identifier, "="):
                appendIdentifier()
                tokens.append(.terminal(.equalSign))

            case (.regular, "="):
                tokens.append(.terminal(.equalSign))

            case (.identifier, ","):
                appendIdentifier()
                tokens.append(.terminal(.comma))

            case (.integerLiteral, ","):
                appendIntegerLiteral()
                tokens.append(.terminal(.comma))

            case (.hexLiteral, ","):
                appendHexLiteral()
                tokens.append(.terminal(.comma))

            case (.decimalLiteral, ","):
                appendDecimalLiteral()
                tokens.append(.terminal(.comma))

            case (.regular, ","):
                tokens.append(.terminal(.comma))

            case (.identifier, ";"):
                appendIdentifier()
                tokens.append(.terminal(.semicolon))

            case (.integerLiteral, ";"):
                appendIntegerLiteral()
                tokens.append(.terminal(.semicolon))

            case (.integerLiteral, "."):
                state = .decimalLiteral
                buffer.append(".")

            case (.hexLiteral, ";"):
                appendHexLiteral()
                tokens.append(.terminal(.semicolon))

            case (.decimalLiteral, ";"):
                appendDecimalLiteral()
                tokens.append(.terminal(.semicolon))

            case (.regular, ";"):
                tokens.append(.terminal(.semicolon))

            case (.identifier, ":"):
                appendIdentifier()
                tokens.append(.terminal(.colon))

            case (.identifier, "."):
                appendIdentifier()
                state = .startOfEllipsis

            case (.regular, ":"):
                tokens.append(.terminal(.colon))

            case (.regular, "."):
                state = .startOfEllipsis

            case (.startOfEllipsis, "."):
                state = .ellipsis

            case (.startOfEllipsis, let char) where char.isWhitespace || char.isNewline:
                tokens.append(.terminal(.dot))
                reset()

            case (.ellipsis, "."):
                tokens.append(.terminal(.ellipsis))
                reset()

            case (.ellipsis, let char) where char.isWhitespace || char.isNewline:
                tokens.append(.terminal(.dot))
                tokens.append(.terminal(.dot))
                reset()

            case (.integerLiteral, let char) where buffer.count == 1 && char.lowercased() == "x":
                state = .hexLiteral
                buffer = ""

            case (.hexLiteral, let char) where char.isHexDigit:
                buffer.append(char)

            case (.regular, "-"):
                buffer.append("-")

            case (.regular, let char) where char.isNumber,
                 (.integerLiteral, let char) where char.isNumber:
                state = .integerLiteral
                buffer.append(char)

            case (.decimalLiteral, let char) where char.isNumber:
                buffer.append(char)

            case (.decimalLiteral, "e") where !buffer.contains("e"),
                 (.decimalLiteral, "E") where !buffer.contains("e"),
                 (.integerLiteral, "e") where !buffer.contains("e"),
                 (.integerLiteral, "E") where !buffer.contains("e"):
                state = .decimalLiteral
                buffer.append("e")
                
            case (.decimalLiteral, "+") where buffer.last == "e":
                buffer.append("+")

            case (.integerLiteral, let char) where char.isWhitespace || char.isNewline:
                appendIntegerLiteral()

            case (.hexLiteral, let char) where char.isWhitespace || char.isNewline:
                appendHexLiteral()

            case (.decimalLiteral, let char) where char.isWhitespace || char.isNewline:
                appendDecimalLiteral()

            case (.regular, "/"):
                state = .startOfComment

            case (.startOfComment, "/"):
                state = .comment
                buffer = ""

            case (.comment, let char):
                if buffer.isEmpty, char.isWhitespace { continue }
                if char.isNewline {
                    tokens.append(.comment(buffer))
                    reset()
                    continue
                }
                buffer.append(char)

            case (.startOfComment, "*"):
                state = .multilineComment
                buffer = ""

            case (.multilineComment, "*"):
                state = .maybeEndOfMultilineComment

            case (.maybeEndOfMultilineComment, "/"):
                tokens.append(.multilineComment(buffer))
                reset()

            case (.maybeEndOfMultilineComment, "*"):
                buffer.append("*")

            case (.maybeEndOfMultilineComment, let char):
                state = .multilineComment
                buffer.append("*")
                buffer.append(char)

            case (.multilineComment, let char):
                buffer.append(char)

            case (.regular, let char) where char.isLetter || "_" == char:
                state = .identifier
                buffer.append(char)

            case (.identifier, let char) where char.isWhitespace || char.isNewline:
                appendIdentifier()

            case (.identifier, let char) where char.isLetter || ["_", "-"].contains(char) || char.isNumber:
                buffer.append(char)

            case (.regular, "\""):
                buffer = ""
                state = .stringLiteral

            case (.stringLiteral, "\\"):
                state = .escapedChar

            case (.escapedChar, "\""):
                state = .stringLiteral

            case (.stringLiteral, "\""):
                tokens.append(.string)
                strings.append(buffer)
                reset()

            case (.stringLiteral, let char):
                buffer.append(char)

            default:
                continue
            }
        }

        switch state {
        case .regular:
            break
        case .identifier:
            appendIdentifier()
        case .integerLiteral:
            appendIntegerLiteral()
        case .hexLiteral:
            appendHexLiteral()
        case .decimalLiteral:
            appendDecimalLiteral()
        case .stringLiteral:
            break
        case .escapedChar:
            break
        case .comment:
            tokens.append(.comment(buffer))
        case .multilineComment:
            tokens.append(.multilineComment(buffer))
        case .startOfComment, .maybeEndOfMultilineComment:
            fatalError("Unterminated start of comment")
        case .startOfEllipsis:
            tokens.append(.terminal(.dot))
        case .ellipsis:
            tokens.append(contentsOf: [.terminal(.dot), .terminal(.dot)])
        }

        return TokenisationResult(tokens: tokens, identifiers: identifiers, integers: integers, decimals: decimals, strings: strings, others: others)
    }
    // swiftlint:enable cyclomatic_complexity function_body_length
}
// swiftlint:enable type_body_length
