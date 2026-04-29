import Foundation

/// Safety-critical language-aware comment stripper.
///
/// The cardinal rule: **never treat text inside a string literal as a comment**.
/// Each language scanner tracks string-literal state before deciding whether a
/// comment marker is genuine.
///
/// Languages that are not yet supported return the original text unchanged with
/// a `.commentStrippingSkipped` warning.
public struct CommentStripper: Sendable {

    public init() {}

    // MARK: - Public API

    public func strip(
        _ text: String,
        language: CodeLanguage,
        options: MinificationOptions
    ) -> CommentStripResult {

        guard language.supportsCommentStripping else {
            let warning = MinificationWarning(
                kind: language == .shell ? .shellCommentStrippingSkipped : .commentStrippingSkipped,
                message: "Comment stripping is not supported for \(language.displayName) in this version. Original text preserved.",
                severity: .info,
                contentType: .code,
                language: language
            )
            return CommentStripResult(text: text, warnings: [warning], appliedRules: [])
        }

        switch language {
        case .swift:
            return stripSwift(text, language: language)
        case .python:
            return stripPython(text, language: language)
        case .ruby:
            return stripRuby(text, language: language)
        case .c, .cpp, .csharp, .java, .kotlin, .scala, .dart, .go, .php:
            return stripCStyle(text, language: language, supportsNested: language == .kotlin || language == .scala)
        case .javaScript, .typeScript:
            return stripJavaScript(text, language: language)
        case .rust:
            return stripRust(text, language: language)
        case .haskell:
            return stripHaskell(text, language: language)
        case .lua:
            return stripLua(text, language: language)
        case .css:
            return stripCSS(text, language: language)
        case .sql:
            return stripSQL(text, language: language)
        case .elixir:
            return stripElixir(text, language: language)
        case .r:
            return stripR(text, language: language)
        case .json:
            return stripJSONC(text, language: language)
        case .yaml:
            // YAML comment stripping is explicitly disabled (supportsCommentStripping returns false).
            let warning = MinificationWarning(
                kind: .commentStrippingSkipped,
                message: "YAML comment stripping is disabled to prevent structural corruption.",
                severity: .info,
                language: language
            )
            return CommentStripResult(text: text, warnings: [warning], appliedRules: [])
        default:
            let warning = MinificationWarning(
                kind: .commentStrippingSkipped,
                message: "Comment stripping is not implemented for \(language.displayName). Original text preserved.",
                severity: .info,
                language: language
            )
            return CommentStripResult(text: text, warnings: [warning], appliedRules: [])
        }
    }

    // MARK: - Swift

    private func stripSwift(_ text: String, language: CodeLanguage) -> CommentStripResult {
        var result = ""
        var i = text.startIndex
        var inLineComment = false
        var blockDepth = 0          // Swift supports nested /* */
        var inString = false
        var inMultilineString = false
        var didStrip = false

        while i < text.endIndex {
            let c = text[i]

            // Handle multiline string literals """ ... """
            if !inLineComment && blockDepth == 0 && !inString {
                if text[i...].hasPrefix("\"\"\"") {
                    inMultilineString.toggle()
                    result.append("\"\"\"")
                    i = text.index(i, offsetBy: 3, limitedBy: text.endIndex) ?? text.endIndex
                    continue
                }
            }

            if inMultilineString {
                if text[i...].hasPrefix("\"\"\"") {
                    inMultilineString = false
                    result.append("\"\"\"")
                    i = text.index(i, offsetBy: 3, limitedBy: text.endIndex) ?? text.endIndex
                } else {
                    result.append(c)
                    i = text.index(after: i)
                }
                continue
            }

            // Regular string literal
            if !inLineComment && blockDepth == 0 {
                if c == "\"" && !inString {
                    inString = true
                    result.append(c)
                    i = text.index(after: i)
                    continue
                }
                if inString {
                    if c == "\\" {
                        // Escape sequence — pass both chars through
                        result.append(c)
                        i = text.index(after: i)
                        if i < text.endIndex { result.append(text[i]); i = text.index(after: i) }
                        continue
                    }
                    if c == "\"" { inString = false }
                    result.append(c)
                    i = text.index(after: i)
                    continue
                }
            }

            // Line comment
            if !inLineComment && blockDepth == 0 {
                if text[i...].hasPrefix("//") {
                    inLineComment = true
                    didStrip = true
                    i = text.index(after: i); i = text.index(after: i)
                    continue
                }
            }

            // Nested block comment open
            if !inLineComment && text[i...].hasPrefix("/*") {
                blockDepth += 1
                didStrip = true
                i = text.index(after: i); i = text.index(after: i)
                continue
            }

            // Block comment close
            if blockDepth > 0 && text[i...].hasPrefix("*/") {
                blockDepth -= 1
                i = text.index(after: i); i = text.index(after: i)
                continue
            }

            // End of line
            if c == "\n" {
                inLineComment = false
                result.append(c)
                i = text.index(after: i)
                continue
            }

            // Inside comment — skip
            if inLineComment || blockDepth > 0 {
                i = text.index(after: i)
                continue
            }

            result.append(c)
            i = text.index(after: i)
        }

        let rules: [AppliedRule] = didStrip ? [AppliedRule(
            rule: .strippedComments,
            description: "Stripped Swift comments (// and nested /* */).",
            contentType: .code,
            language: language
        )] : []

        return CommentStripResult(text: result, warnings: [], appliedRules: rules)
    }

    // MARK: - C-style (C, C++, C#, Java, Kotlin, Scala, Dart, Go, PHP)

    private func stripCStyle(
        _ text: String,
        language: CodeLanguage,
        supportsNested: Bool
    ) -> CommentStripResult {
        var result = ""
        var i = text.startIndex
        var inLineComment = false
        var blockDepth = 0
        var inString = false
        var inChar = false
        var didStrip = false

        while i < text.endIndex {
            let c = text[i]

            // Go raw strings: backtick literals — pass through entirely
            if language == .go && c == "`" && !inString && !inChar && !inLineComment && blockDepth == 0 {
                result.append(c)
                i = text.index(after: i)
                while i < text.endIndex && text[i] != "`" {
                    result.append(text[i])
                    i = text.index(after: i)
                }
                if i < text.endIndex { result.append(text[i]); i = text.index(after: i) }
                continue
            }

            if !inLineComment && blockDepth == 0 {
                // String literal
                if c == "\"" && !inChar {
                    inString.toggle()
                    result.append(c)
                    i = text.index(after: i)
                    continue
                }
                if inString {
                    if c == "\\" {
                        result.append(c); i = text.index(after: i)
                        if i < text.endIndex { result.append(text[i]); i = text.index(after: i) }
                        continue
                    }
                    if c == "\"" { inString = false }
                    result.append(c); i = text.index(after: i)
                    continue
                }
                // Char literal
                if c == "'" && !inString {
                    inChar = true
                    result.append(c); i = text.index(after: i)
                    continue
                }
                if inChar {
                    if c == "\\" {
                        result.append(c); i = text.index(after: i)
                        if i < text.endIndex { result.append(text[i]); i = text.index(after: i) }
                        continue
                    }
                    if c == "'" { inChar = false }
                    result.append(c); i = text.index(after: i)
                    continue
                }
            }

            // Line comment
            if !inLineComment && blockDepth == 0 && !inString && !inChar {
                if text[i...].hasPrefix("//") {
                    inLineComment = true; didStrip = true
                    i = text.index(after: i); i = text.index(after: i)
                    continue
                }
            }

            // Block comment open
            if !inLineComment && !inString && !inChar && text[i...].hasPrefix("/*") {
                if supportsNested { blockDepth += 1 } else { blockDepth = 1 }
                didStrip = true
                i = text.index(after: i); i = text.index(after: i)
                continue
            }

            // Block comment close
            if blockDepth > 0 && text[i...].hasPrefix("*/") {
                if supportsNested { blockDepth -= 1 } else { blockDepth = 0 }
                i = text.index(after: i); i = text.index(after: i)
                continue
            }

            if c == "\n" { inLineComment = false; result.append(c); i = text.index(after: i); continue }
            if inLineComment || blockDepth > 0 { i = text.index(after: i); continue }

            result.append(c)
            i = text.index(after: i)
        }

        let rules: [AppliedRule] = didStrip ? [AppliedRule(
            rule: .strippedComments,
            description: "Stripped \(language.displayName) comments.",
            contentType: .code,
            language: language
        )] : []
        return CommentStripResult(text: result, warnings: [], appliedRules: rules)
    }

    // MARK: - JavaScript / TypeScript

    private func stripJavaScript(_ text: String, language: CodeLanguage) -> CommentStripResult {
        // JS/TS: // and /* */ plus template literals ` ... `
        var result = ""
        var i = text.startIndex
        var inLineComment = false
        var blockDepth = 0
        var inSingleString = false
        var inDoubleString = false
        var inTemplate = false
        var didStrip = false

        while i < text.endIndex {
            let c = text[i]

            if !inLineComment && blockDepth == 0 {
                if c == "`" && !inSingleString && !inDoubleString {
                    inTemplate.toggle()
                    result.append(c); i = text.index(after: i); continue
                }
                if inTemplate {
                    // Pass through template literal content safely
                    if c == "\\" {
                        result.append(c); i = text.index(after: i)
                        if i < text.endIndex { result.append(text[i]); i = text.index(after: i) }
                        continue
                    }
                    if c == "`" { inTemplate = false }
                    result.append(c); i = text.index(after: i); continue
                }
                if c == "\"" && !inSingleString {
                    inDoubleString.toggle(); result.append(c); i = text.index(after: i); continue
                }
                if inDoubleString {
                    if c == "\\" { result.append(c); i = text.index(after: i)
                        if i < text.endIndex { result.append(text[i]); i = text.index(after: i) }; continue }
                    if c == "\"" { inDoubleString = false }
                    result.append(c); i = text.index(after: i); continue
                }
                if c == "'" && !inDoubleString {
                    inSingleString.toggle(); result.append(c); i = text.index(after: i); continue
                }
                if inSingleString {
                    if c == "\\" { result.append(c); i = text.index(after: i)
                        if i < text.endIndex { result.append(text[i]); i = text.index(after: i) }; continue }
                    if c == "'" { inSingleString = false }
                    result.append(c); i = text.index(after: i); continue
                }
            }

            let inStringLiteral = inSingleString || inDoubleString || inTemplate

            if !inLineComment && blockDepth == 0 && !inStringLiteral {
                if text[i...].hasPrefix("//") { inLineComment = true; didStrip = true; i = text.index(after: i); i = text.index(after: i); continue }
                if text[i...].hasPrefix("/*") { blockDepth = 1; didStrip = true; i = text.index(after: i); i = text.index(after: i); continue }
            }
            if blockDepth > 0 && text[i...].hasPrefix("*/") { blockDepth = 0; i = text.index(after: i); i = text.index(after: i); continue }
            if c == "\n" { inLineComment = false; result.append(c); i = text.index(after: i); continue }
            if inLineComment || blockDepth > 0 { i = text.index(after: i); continue }

            result.append(c); i = text.index(after: i)
        }

        let rules: [AppliedRule] = didStrip ? [AppliedRule(
            rule: .strippedComments,
            description: "Stripped \(language.displayName) comments.",
            contentType: .code, language: language)] : []
        return CommentStripResult(text: result, warnings: [], appliedRules: rules)
    }

    // MARK: - Rust

    private func stripRust(_ text: String, language: CodeLanguage) -> CommentStripResult {
        // Rust: //, ///, //!, nested /* */
        // Raw strings: r"..." r#"..."# — pass through safely
        var result = ""
        var i = text.startIndex
        var inLineComment = false
        var blockDepth = 0
        var inString = false
        var didStrip = false

        while i < text.endIndex {
            let c = text[i]

            if !inLineComment && blockDepth == 0 && !inString {
                if text[i...].hasPrefix("r\"") || text[i...].hasPrefix("r#") {
                    // Raw string — find the matching delimiter and pass through
                    var hashCount = 0
                    var j = text.index(after: i) // past 'r'
                    while j < text.endIndex && text[j] == "#" { hashCount += 1; j = text.index(after: j) }
                    // Expect opening "
                    if j < text.endIndex && text[j] == "\"" {
                        j = text.index(after: j)
                        let close = "\"" + String(repeating: "#", count: hashCount)
                        while j < text.endIndex {
                            if text[j...].hasPrefix(close) {
                                // consume close
                                let rawText = String(text[i..<j]) + close
                                result.append(rawText)
                                j = text.index(j, offsetBy: close.count, limitedBy: text.endIndex) ?? text.endIndex
                                i = j; break
                            }
                            j = text.index(after: j)
                        }
                        continue
                    }
                }
                if c == "\"" { inString = true; result.append(c); i = text.index(after: i); continue }
            }
            if inString && !inLineComment && blockDepth == 0 {
                if c == "\\" { result.append(c); i = text.index(after: i)
                    if i < text.endIndex { result.append(text[i]); i = text.index(after: i) }; continue }
                if c == "\"" { inString = false }
                result.append(c); i = text.index(after: i); continue
            }

            if !inLineComment && blockDepth == 0 && !inString {
                if text[i...].hasPrefix("//") { inLineComment = true; didStrip = true; i = text.index(after: i); i = text.index(after: i); continue }
                if text[i...].hasPrefix("/*") { blockDepth += 1; didStrip = true; i = text.index(after: i); i = text.index(after: i); continue }
            }
            if blockDepth > 0 && text[i...].hasPrefix("*/") { blockDepth -= 1; i = text.index(after: i); i = text.index(after: i); continue }
            if c == "\n" { inLineComment = false; result.append(c); i = text.index(after: i); continue }
            if inLineComment || blockDepth > 0 { i = text.index(after: i); continue }

            result.append(c); i = text.index(after: i)
        }

        let rules: [AppliedRule] = didStrip ? [AppliedRule(rule: .strippedComments,
            description: "Stripped Rust comments (// /// //! nested /* */).",
            contentType: .code, language: language)] : []
        return CommentStripResult(text: result, warnings: [], appliedRules: rules)
    }

    // MARK: - Python

    private func stripPython(_ text: String, language: CodeLanguage) -> CommentStripResult {
        var result = ""
        var i = text.startIndex
        var didStrip = false

        while i < text.endIndex {
            let c = text[i]

            // Triple-quoted strings (""" or ''')
            for q in ["\"\"\"", "'''"] {
                if text[i...].hasPrefix(q) {
                    result.append(q)
                    i = text.index(i, offsetBy: 3, limitedBy: text.endIndex) ?? text.endIndex
                    while i < text.endIndex {
                        if text[i...].hasPrefix(q) {
                            result.append(q)
                            i = text.index(i, offsetBy: 3, limitedBy: text.endIndex) ?? text.endIndex
                            break
                        }
                        result.append(text[i]); i = text.index(after: i)
                    }
                    // continue outer loop
                    break
                }
            }
            guard i < text.endIndex else { break }
            let c2 = text[i]

            // Single-quoted strings
            if c2 == "\"" || c2 == "'" {
                let q = c2
                result.append(c2); i = text.index(after: i)
                while i < text.endIndex {
                    let ch = text[i]
                    if ch == "\\" { result.append(ch); i = text.index(after: i)
                        if i < text.endIndex { result.append(text[i]); i = text.index(after: i) }; continue }
                    result.append(ch); i = text.index(after: i)
                    if ch == q { break }
                }
                continue
            }

            // Hash comment
            if c2 == "#" {
                didStrip = true
                while i < text.endIndex && text[i] != "\n" { i = text.index(after: i) }
                continue
            }

            result.append(c2); i = text.index(after: i)
        }

        let rules: [AppliedRule] = didStrip ? [AppliedRule(rule: .strippedComments,
            description: "Stripped Python # comments (triple-quoted strings preserved).",
            contentType: .code, language: language)] : []
        return CommentStripResult(text: result, warnings: [], appliedRules: rules)
    }

    // MARK: - Ruby

    private func stripRuby(_ text: String, language: CodeLanguage) -> CommentStripResult {
        var lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var inEmbeddedDoc = false
        var didStrip = false

        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t == "=begin" { inEmbeddedDoc = true; didStrip = true; continue }
            if t == "=end" && inEmbeddedDoc { inEmbeddedDoc = false; continue }
            if inEmbeddedDoc { continue }

            // Strip inline # comment (basic — doesn't handle strings)
            var resultLine = ""
            var inStr: Character? = nil
            var j = line.startIndex
            var stripped = false
            while j < line.endIndex {
                let ch = line[j]
                if let q = inStr {
                    if ch == "\\" { resultLine.append(ch); j = line.index(after: j)
                        if j < line.endIndex { resultLine.append(line[j]); j = line.index(after: j) }; continue }
                    if ch == q { inStr = nil }
                    resultLine.append(ch); j = line.index(after: j); continue
                }
                if ch == "\"" || ch == "'" { inStr = ch; resultLine.append(ch); j = line.index(after: j); continue }
                if ch == "#" { stripped = true; break }
                resultLine.append(ch); j = line.index(after: j)
            }
            if stripped { didStrip = true }
            result.append(resultLine)
        }
        _ = lines // suppress warning

        let rules: [AppliedRule] = didStrip ? [AppliedRule(rule: .strippedComments,
            description: "Stripped Ruby # and =begin/=end comments.",
            contentType: .code, language: language)] : []
        return CommentStripResult(text: result.joined(separator: "\n"), warnings: [], appliedRules: rules)
    }

    // MARK: - Haskell

    private func stripHaskell(_ text: String, language: CodeLanguage) -> CommentStripResult {
        var result = ""
        var i = text.startIndex
        var blockDepth = 0
        var inLineComment = false
        var inString = false
        var didStrip = false

        while i < text.endIndex {
            let c = text[i]
            if !inLineComment && blockDepth == 0 && !inString {
                if c == "\"" { inString = true; result.append(c); i = text.index(after: i); continue }
                if text[i...].hasPrefix("{-") { blockDepth += 1; didStrip = true; i = text.index(after: i); i = text.index(after: i); continue }
                if text[i...].hasPrefix("--") { inLineComment = true; didStrip = true; i = text.index(after: i); i = text.index(after: i); continue }
            }
            if inString {
                if c == "\\" { result.append(c); i = text.index(after: i)
                    if i < text.endIndex { result.append(text[i]); i = text.index(after: i) }; continue }
                if c == "\"" { inString = false }
                result.append(c); i = text.index(after: i); continue
            }
            if blockDepth > 0 && text[i...].hasPrefix("-}") { blockDepth -= 1; i = text.index(after: i); i = text.index(after: i); continue }
            if c == "\n" { inLineComment = false; result.append(c); i = text.index(after: i); continue }
            if inLineComment || blockDepth > 0 { i = text.index(after: i); continue }
            result.append(c); i = text.index(after: i)
        }

        let rules: [AppliedRule] = didStrip ? [AppliedRule(rule: .strippedComments,
            description: "Stripped Haskell -- and {- -} comments.",
            contentType: .code, language: language)] : []
        return CommentStripResult(text: result, warnings: [], appliedRules: rules)
    }

    // MARK: - Lua

    private func stripLua(_ text: String, language: CodeLanguage) -> CommentStripResult {
        var result = ""
        var i = text.startIndex
        var inLineComment = false
        var inBlockComment = false
        var inString = false
        var inStringDelim: Character = "\""
        var didStrip = false

        while i < text.endIndex {
            let c = text[i]
            if !inLineComment && !inBlockComment && !inString {
                if c == "\"" || c == "'" { inString = true; inStringDelim = c; result.append(c); i = text.index(after: i); continue }
                if text[i...].hasPrefix("--[[") { inBlockComment = true; didStrip = true; i = text.index(i, offsetBy: 4, limitedBy: text.endIndex) ?? text.endIndex; continue }
                if text[i...].hasPrefix("--") { inLineComment = true; didStrip = true; i = text.index(after: i); i = text.index(after: i); continue }
            }
            if inString {
                if c == "\\" { result.append(c); i = text.index(after: i)
                    if i < text.endIndex { result.append(text[i]); i = text.index(after: i) }; continue }
                if c == inStringDelim { inString = false }
                result.append(c); i = text.index(after: i); continue
            }
            if inBlockComment && text[i...].hasPrefix("]]") { inBlockComment = false; i = text.index(after: i); i = text.index(after: i); continue }
            if c == "\n" { inLineComment = false; result.append(c); i = text.index(after: i); continue }
            if inLineComment || inBlockComment { i = text.index(after: i); continue }
            result.append(c); i = text.index(after: i)
        }

        let rules: [AppliedRule] = didStrip ? [AppliedRule(rule: .strippedComments,
            description: "Stripped Lua -- and --[[ ]] comments.",
            contentType: .code, language: language)] : []
        return CommentStripResult(text: result, warnings: [], appliedRules: rules)
    }

    // MARK: - CSS

    private func stripCSS(_ text: String, language: CodeLanguage) -> CommentStripResult {
        var result = ""
        var i = text.startIndex
        var inBlock = false
        var didStrip = false

        while i < text.endIndex {
            if !inBlock && text[i...].hasPrefix("/*") { inBlock = true; didStrip = true; i = text.index(after: i); i = text.index(after: i); continue }
            if inBlock && text[i...].hasPrefix("*/") { inBlock = false; i = text.index(after: i); i = text.index(after: i); continue }
            if !inBlock { result.append(text[i]) }
            i = text.index(after: i)
        }

        let rules: [AppliedRule] = didStrip ? [AppliedRule(rule: .strippedComments,
            description: "Stripped CSS /* */ comments.",
            contentType: .code, language: language)] : []
        return CommentStripResult(text: result, warnings: [], appliedRules: rules)
    }

    // MARK: - SQL

    private func stripSQL(_ text: String, language: CodeLanguage) -> CommentStripResult {
        var result = ""
        var i = text.startIndex
        var inLine = false
        var inBlock = false
        var inStr = false
        var didStrip = false

        while i < text.endIndex {
            let c = text[i]
            if !inLine && !inBlock && !inStr {
                if c == "'" { inStr = true; result.append(c); i = text.index(after: i); continue }
                if text[i...].hasPrefix("--") { inLine = true; didStrip = true; i = text.index(after: i); i = text.index(after: i); continue }
                if text[i...].hasPrefix("/*") { inBlock = true; didStrip = true; i = text.index(after: i); i = text.index(after: i); continue }
            }
            if inStr {
                // SQL escaped single quote: ''
                if c == "'" {
                    if text.index(after: i) < text.endIndex && text[text.index(after: i)] == "'" {
                        result.append("''"); i = text.index(after: i); i = text.index(after: i); continue
                    }
                    inStr = false
                }
                result.append(c); i = text.index(after: i); continue
            }
            if inBlock && text[i...].hasPrefix("*/") { inBlock = false; i = text.index(after: i); i = text.index(after: i); continue }
            if c == "\n" { inLine = false; result.append(c); i = text.index(after: i); continue }
            if inLine || inBlock { i = text.index(after: i); continue }
            result.append(c); i = text.index(after: i)
        }

        let rules: [AppliedRule] = didStrip ? [AppliedRule(rule: .strippedComments,
            description: "Stripped SQL -- and /* */ comments.",
            contentType: .code, language: language)] : []
        return CommentStripResult(text: result, warnings: [], appliedRules: rules)
    }

    // MARK: - Elixir

    private func stripElixir(_ text: String, language: CodeLanguage) -> CommentStripResult {
        // Elixir: # line comments; strings "..." and heredocs ~s"""..."""
        var result = ""
        var i = text.startIndex
        var inStr = false
        var inLine = false
        var didStrip = false

        while i < text.endIndex {
            let c = text[i]
            if !inLine && !inStr {
                if c == "\"" { inStr = true; result.append(c); i = text.index(after: i); continue }
                if c == "#" { inLine = true; didStrip = true; i = text.index(after: i); continue }
            }
            if inStr {
                if c == "\\" { result.append(c); i = text.index(after: i)
                    if i < text.endIndex { result.append(text[i]); i = text.index(after: i) }; continue }
                if c == "\"" { inStr = false }
                result.append(c); i = text.index(after: i); continue
            }
            if c == "\n" { inLine = false; result.append(c); i = text.index(after: i); continue }
            if inLine { i = text.index(after: i); continue }
            result.append(c); i = text.index(after: i)
        }

        let rules: [AppliedRule] = didStrip ? [AppliedRule(rule: .strippedComments,
            description: "Stripped Elixir # comments.",
            contentType: .code, language: language)] : []
        return CommentStripResult(text: result, warnings: [], appliedRules: rules)
    }

    // MARK: - R

    private func stripR(_ text: String, language: CodeLanguage) -> CommentStripResult {
        var result = ""
        var i = text.startIndex
        var inStr = false
        var inLine = false
        var didStrip = false

        while i < text.endIndex {
            let c = text[i]
            if !inLine && !inStr {
                if c == "\"" || c == "'" { inStr = true; result.append(c); i = text.index(after: i); continue }
                if c == "#" { inLine = true; didStrip = true; i = text.index(after: i); continue }
            }
            if inStr {
                if c == "\\" { result.append(c); i = text.index(after: i)
                    if i < text.endIndex { result.append(text[i]); i = text.index(after: i) }; continue }
                if c == "\"" || c == "'" { inStr = false }
                result.append(c); i = text.index(after: i); continue
            }
            if c == "\n" { inLine = false; result.append(c); i = text.index(after: i); continue }
            if inLine { i = text.index(after: i); continue }
            result.append(c); i = text.index(after: i)
        }

        let rules: [AppliedRule] = didStrip ? [AppliedRule(rule: .strippedComments,
            description: "Stripped R # comments.",
            contentType: .code, language: language)] : []
        return CommentStripResult(text: result, warnings: [], appliedRules: rules)
    }

    // MARK: - JSONC (JSON with comments)

    private func stripJSONC(_ text: String, language: CodeLanguage) -> CommentStripResult {
        // Only strip if JSONC-like comments are actually present.
        guard text.contains("//") || text.contains("/*") else {
            return CommentStripResult(text: text, warnings: [], appliedRules: [])
        }
        // Strip using C-style scanner.
        let stripped = stripCStyle(text, language: language, supportsNested: false)
        // Validate that the result is valid JSON.
        let trimmed = stripped.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return stripped
        }
        let warning = MinificationWarning(
            kind: .invalidJSON,
            message: "JSONC comment stripping produced invalid JSON. Original preserved.",
            severity: .caution,
            contentType: .json,
            language: language
        )
        return CommentStripResult(text: text, warnings: [warning], appliedRules: [])
    }
}

// MARK: - Result type

public struct CommentStripResult: Sendable {
    public let text: String
    public let warnings: [MinificationWarning]
    public let appliedRules: [AppliedRule]
}
