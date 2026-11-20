import Foundation

struct LauncherArithmetic {
    private var remaining: Substring
    private var hasOperation = false

    static func evaluate(_ query: String) -> String? {
        var parser = LauncherArithmetic(remaining: query[...])
        guard let value = parser.sum(), !value.isNaN, parser.hasOperation else { return nil }
        parser.skipWhitespace()
        guard parser.remaining.isEmpty else { return nil }
        return NSDecimalNumber(decimal: value).stringValue
    }

    private mutating func sum(depth: Int = 0) -> Decimal? {
        guard var value = product(depth: depth) else { return nil }
        while let operation = consume(oneOf: "+-") {
            guard let right = product(depth: depth) else { return nil }
            hasOperation = true
            value = operation == "+" ? value + right : value - right
        }
        return value
    }

    private mutating func product(depth: Int) -> Decimal? {
        guard var value = operand(depth: depth) else { return nil }
        while let operation = consume(oneOf: "*/") {
            guard let right = operand(depth: depth), operation != "/" || right != 0 else { return nil }
            hasOperation = true
            value = operation == "*" ? value * right : value / right
        }
        return value
    }

    private mutating func operand(depth: Int) -> Decimal? {
        let negative = consume(oneOf: "-") != nil
        let value: Decimal
        if consume(oneOf: "(") != nil {
            // shortcut: cap nesting at 128 to bound stack use, revisit if deeper expressions are needed.
            guard depth < 128, let inner = sum(depth: depth + 1), consume(oneOf: ")") != nil else {
                return nil
            }
            value = inner
        } else {
            guard let number = remaining.prefixMatch(of: /[0-9]+(?:\.[0-9]+)?|\.[0-9]+/),
                  let decimal = Decimal(string: String(number.output), locale: Locale(identifier: "en_US_POSIX")) else {
                return nil
            }
            remaining = remaining[number.range.upperBound...]
            value = decimal
        }
        return negative ? -value : value
    }

    private mutating func consume(oneOf characters: String) -> Character? {
        skipWhitespace()
        guard let next = remaining.first, characters.contains(next) else { return nil }
        remaining = remaining.dropFirst()
        return next
    }

    private mutating func skipWhitespace() {
        remaining = remaining.drop(while: \.isWhitespace)
    }
}
