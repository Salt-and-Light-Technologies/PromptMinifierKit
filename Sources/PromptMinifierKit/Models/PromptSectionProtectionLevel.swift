import Foundation

/// How much a prompt section may be modified during minification.
///
/// Levels are ordered from most protected (`.locked`) to most compactable
/// (`.aggressivelyMinifiable`). Minifiers must respect the level assigned to
/// each block; violating a protection level is never acceptable.
public enum PromptSectionProtectionLevel: String, Codable, CaseIterable, Sendable, Hashable,
    Comparable
{
    /// Text must remain byte-identical to the normalised input.
    /// Only safe whitespace normalisation (CRLF→LF, BOM removal) is permitted.
    case locked

    /// Whitespace may be cleaned, but headings, bullet structure, numbering,
    /// and ordering must be preserved verbatim.
    case preserveStructure

    /// Prose spacing and redundant blank lines may be compacted, but wording
    /// must remain close enough to the original that meaning is unchanged.
    case preserveMeaning

    /// Standard safe minification is permitted.
    case minifiable

    /// Aggressive compaction is permitted when the processing mode allows it.
    case aggressivelyMinifiable

    // MARK: - Comparable

    private var order: Int {
        switch self {
        case .locked:                 return 0
        case .preserveStructure:      return 1
        case .preserveMeaning:        return 2
        case .minifiable:             return 3
        case .aggressivelyMinifiable: return 4
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.order < rhs.order
    }

    // MARK: - Helpers

    /// Returns `true` when comment stripping is never appropriate for this level.
    public var prohibitsCommentStripping: Bool {
        self <= .preserveStructure
    }

    /// Returns `true` when brace compaction is never appropriate for this level.
    public var prohibitsBraceCompaction: Bool {
        self <= .preserveMeaning
    }

    /// Returns `true` when the section must be passed through unchanged (modulo
    /// safe normalisation).
    public var isLocked: Bool {
        self == .locked
    }
}
