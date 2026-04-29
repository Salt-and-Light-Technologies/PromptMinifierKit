import Foundation

/// The type of content being minified.
public enum ContentType: String, Codable, CaseIterable, Sendable, Hashable {
    /// Automatically detect the content type.
    case auto
    /// Plain prose text with no structural markup.
    case plainText
    /// GitHub-Flavoured Markdown (may contain fenced code blocks).
    case markdown
    /// A JSON object or array.
    case json
    /// YAML document.
    case yaml
    /// Source code in a specific programming language.
    case code
    /// Log output (timestamped lines, stack traces, level prefixes).
    case logs
    /// A document containing multiple distinct content types.
    case mixed
    /// A MinifyAI-style rendered prompt pack with labelled sections.
    case promptPack

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .auto:        return "Auto-Detect"
        case .plainText:   return "Plain Text"
        case .markdown:    return "Markdown"
        case .json:        return "JSON"
        case .yaml:        return "YAML"
        case .code:        return "Code"
        case .logs:        return "Logs"
        case .mixed:       return "Mixed"
        case .promptPack:  return "Prompt Pack"
        }
    }
}
