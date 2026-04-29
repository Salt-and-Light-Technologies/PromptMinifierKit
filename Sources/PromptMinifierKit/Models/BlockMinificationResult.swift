import Foundation

/// The result of minifying a single `ContentBlock`.
public struct BlockMinificationResult: Codable, Sendable, Hashable {
    /// The original block before any transformations.
    public let original: ContentBlock
    /// The text after minification (may equal `original.text` if no changes were safe).
    public let minifiedText: String
    /// Warnings produced while processing this block.
    public let warnings: [MinificationWarning]
    /// Transformations that were applied to this block.
    public let appliedRules: [AppliedRule]
    /// Quantitative statistics for this block.
    public let stats: MinificationStats

    public init(
        original: ContentBlock,
        minifiedText: String,
        warnings: [MinificationWarning] = [],
        appliedRules: [AppliedRule] = [],
        stats: MinificationStats
    ) {
        self.original = original
        self.minifiedText = minifiedText
        self.warnings = warnings
        self.appliedRules = appliedRules
        self.stats = stats
    }
}
