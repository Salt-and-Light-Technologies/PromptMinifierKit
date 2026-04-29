import Foundation

/// A line-range hint that can be stored in a `Codable` context.
///
/// `Range<String.Index>` is not `Codable`, so we record the zero-based start
/// and end line numbers of a block within the original document instead.
public struct RangeHint: Codable, Sendable, Hashable {
    /// Zero-based index of the first line of the block.
    public let startLine: Int
    /// Zero-based index of the last line of the block (inclusive).
    public let endLine: Int

    public init(startLine: Int, endLine: Int) {
        self.startLine = startLine
        self.endLine = endLine
    }
}

/// A typed segment of a segmented document.
///
/// `BlockSegmenter` produces an ordered array of `ContentBlock` values.
/// Each block carries its detected type, raw text, language (for code blocks),
/// position hint, and any prompt-pack role and protection level.
public struct ContentBlock: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    /// The content type of this block.
    public let type: ContentType
    /// The raw, unmodified text of this block.
    public let text: String
    /// The programming/markup language, if known (only set for `.code` blocks).
    public let language: CodeLanguage?
    /// Line-range within the original document (zero-based, inclusive end).
    public let rangeHint: RangeHint?
    /// The prompt-section role, if this block belongs to a prompt pack section.
    public let role: PromptSectionRole?
    /// How aggressively this block may be minified.
    public let protectionLevel: PromptSectionProtectionLevel

    public init(
        id: UUID = UUID(),
        type: ContentType,
        text: String,
        language: CodeLanguage? = nil,
        rangeHint: RangeHint? = nil,
        role: PromptSectionRole? = nil,
        protectionLevel: PromptSectionProtectionLevel = .minifiable
    ) {
        self.id = id
        self.type = type
        self.text = text
        self.language = language
        self.rangeHint = rangeHint
        self.role = role
        self.protectionLevel = protectionLevel
    }
}
