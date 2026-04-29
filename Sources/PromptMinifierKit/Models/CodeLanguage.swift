import Foundation

/// A programming or markup language that PromptMinifierKit understands.
public enum CodeLanguage: String, Codable, CaseIterable, Sendable, Hashable {
    case unknown
    case c
    case cpp
    case csharp
    case java
    case kotlin
    case scala
    case dart
    case go
    case rust
    case swift
    case javaScript
    case typeScript
    case python
    case ruby
    case php
    case lua
    case shell
    case haskell
    case elixir
    case r
    case css
    case sql
    case json
    case yaml

    // MARK: - Display

    /// Human-readable name shown in the UI.
    public var displayName: String {
        switch self {
        case .unknown:    return "Unknown"
        case .c:          return "C"
        case .cpp:        return "C++"
        case .csharp:     return "C#"
        case .java:       return "Java"
        case .kotlin:     return "Kotlin"
        case .scala:      return "Scala"
        case .dart:       return "Dart"
        case .go:         return "Go"
        case .rust:       return "Rust"
        case .swift:      return "Swift"
        case .javaScript: return "JavaScript"
        case .typeScript: return "TypeScript"
        case .python:     return "Python"
        case .ruby:       return "Ruby"
        case .php:        return "PHP"
        case .lua:        return "Lua"
        case .shell:      return "Shell"
        case .haskell:    return "Haskell"
        case .elixir:     return "Elixir"
        case .r:          return "R"
        case .css:        return "CSS"
        case .sql:        return "SQL"
        case .json:       return "JSON"
        case .yaml:       return "YAML"
        }
    }

    // MARK: - File extensions

    /// Common file extensions for this language.
    public var commonExtensions: [String] {
        switch self {
        case .unknown:    return []
        case .c:          return ["c", "h"]
        case .cpp:        return ["cpp", "cc", "cxx", "hpp", "hxx"]
        case .csharp:     return ["cs"]
        case .java:       return ["java"]
        case .kotlin:     return ["kt", "kts"]
        case .scala:      return ["scala", "sc"]
        case .dart:       return ["dart"]
        case .go:         return ["go"]
        case .rust:       return ["rs"]
        case .swift:      return ["swift"]
        case .javaScript: return ["js", "jsx", "mjs", "cjs"]
        case .typeScript: return ["ts", "tsx"]
        case .python:     return ["py", "pyw"]
        case .ruby:       return ["rb", "rake"]
        case .php:        return ["php"]
        case .lua:        return ["lua"]
        case .shell:      return ["sh", "bash", "zsh", "fish"]
        case .haskell:    return ["hs", "lhs"]
        case .elixir:     return ["ex", "exs"]
        case .r:          return ["r", "R"]
        case .css:        return ["css", "scss", "less"]
        case .sql:        return ["sql"]
        case .json:       return ["json", "jsonc"]
        case .yaml:       return ["yaml", "yml"]
        }
    }

    /// Fenced-code-block hint strings that map to this language.
    public var commonFenceHints: [String] {
        switch self {
        case .unknown:    return []
        case .c:          return ["c"]
        case .cpp:        return ["cpp", "cc", "cxx", "hpp", "c++"]
        case .csharp:     return ["cs", "csharp", "c#"]
        case .java:       return ["java"]
        case .kotlin:     return ["kotlin", "kt", "kts"]
        case .scala:      return ["scala"]
        case .dart:       return ["dart"]
        case .go:         return ["go", "golang"]
        case .rust:       return ["rust", "rs"]
        case .swift:      return ["swift"]
        case .javaScript: return ["javascript", "js", "jsx"]
        case .typeScript: return ["typescript", "ts", "tsx"]
        case .python:     return ["python", "py", "python3"]
        case .ruby:       return ["ruby", "rb"]
        case .php:        return ["php"]
        case .lua:        return ["lua"]
        case .shell:      return ["shell", "sh", "bash", "zsh"]
        case .haskell:    return ["haskell", "hs"]
        case .elixir:     return ["elixir", "ex", "exs"]
        case .r:          return ["r", "R"]
        case .css:        return ["css", "scss", "less"]
        case .sql:        return ["sql"]
        case .json:       return ["json", "jsonc"]
        case .yaml:       return ["yaml", "yml"]
        }
    }

    // MARK: - Capabilities

    /// Whether this language's comments can be safely stripped by PromptMinifierKit.
    public var supportsCommentStripping: Bool {
        switch self {
        case .unknown, .yaml: return false
        // Shell comment stripping requires heredoc-safety; disabled in v1.
        case .shell:          return false
        default:              return true
        }
    }

    /// Whether indentation is structurally significant in this language.
    public var isIndentationSensitive: Bool {
        switch self {
        case .python, .yaml, .haskell, .elixir: return true
        default:                                 return false
        }
    }

    /// The prefix that begins a single-line comment, if any.
    public var lineCommentPrefix: String? {
        switch self {
        case .swift, .c, .cpp, .csharp, .java, .kotlin, .scala,
             .dart, .go, .rust, .javaScript, .typeScript, .php: return "//"
        case .python, .ruby, .shell, .r:                         return "#"
        case .elixir:                                             return "#"
        case .haskell, .lua, .sql:                               return "--"
        case .css, .yaml, .json, .unknown:                       return nil
        }
    }

    /// Opening and closing markers for a block comment, if supported.
    public var blockCommentMarkers: (open: String, close: String)? {
        switch self {
        case .swift, .c, .cpp, .csharp, .java, .kotlin, .scala,
             .dart, .go, .rust, .javaScript, .typeScript, .php,
             .css, .sql:                                         return ("/*", "*/")
        case .haskell:                                           return ("{-", "-}")
        case .lua:                                               return ("--[[", "]]")
        default:                                                 return nil
        }
    }

    // MARK: - Lookup

    /// Return a `CodeLanguage` from a fenced-code-block hint string (case-insensitive).
    public static func from(fenceHint: String) -> CodeLanguage {
        let hint = fenceHint.trimmingCharacters(in: .whitespaces).lowercased()
        for language in CodeLanguage.allCases {
            if language.commonFenceHints.contains(hint) {
                return language
            }
        }
        return .unknown
    }
}
