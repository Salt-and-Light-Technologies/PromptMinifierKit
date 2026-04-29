import Foundation

/// Controls how aggressively PromptMinifierKit compacts content.
public enum ProcessingMode: String, Codable, CaseIterable, Sendable, Hashable {

    /// Minimal cleanup only. Normalises line endings and trims trailing whitespace.
    /// Preserves wording, headings, comments, and code formatting almost entirely.
    case readable

    /// Default safe mode. Normalises whitespace, collapses blank lines, compacts JSON,
    /// minifies fenced code blocks carefully. Preserves Markdown structure, hard
    /// constraints, response format, gotchas, and warnings. Comment stripping is
    /// disabled unless explicitly opted in.
    case safe

    /// Opt-in aggressive compaction. More whitespace collapsing, code brace compaction
    /// when safe, optional comment removal in supported languages, heavier Markdown
    /// compaction. Always emits risk warnings. Must never be the default.
    case aggressive

    /// Optimised for prompt packs containing substantial source code. Preserves code
    /// correctness above everything else. Keeps fenced-code language tags, string
    /// literals, and indentation-sensitive formatting intact.
    case codeHeavy

    /// Human-readable label.
    public var displayName: String {
        switch self {
        case .readable:   return "Readable"
        case .safe:       return "Safe"
        case .aggressive: return "Aggressive"
        case .codeHeavy:  return "Code-Heavy"
        }
    }

    /// A short description shown in the UI.
    public var shortDescription: String {
        switch self {
        case .readable:
            return "Minimal cleanup. Preserves original formatting and wording."
        case .safe:
            return "Default. Compacts whitespace and JSON without risking meaning."
        case .aggressive:
            return "Opt-in heavy compaction. May reduce readability. Review warnings."
        case .codeHeavy:
            return "Prioritises code correctness. Best for code-heavy prompt packs."
        }
    }
}
