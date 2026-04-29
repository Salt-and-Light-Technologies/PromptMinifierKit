import Foundation

/// Quantitative summary of what minification achieved for a block or the whole document.
///
/// All token counts are **estimates** based on a character-level heuristic.
/// They should be displayed with an appropriate "~" or "est." qualifier in the UI.
public struct MinificationStats: Codable, Sendable, Hashable {

    // MARK: - Characters

    public let originalCharacters: Int
    public let minifiedCharacters: Int

    public var characterReduction: Int {
        max(0, originalCharacters - minifiedCharacters)
    }

    public var characterReductionPercent: Double {
        guard originalCharacters > 0 else { return 0 }
        return Double(characterReduction) / Double(originalCharacters) * 100
    }

    // MARK: - Estimated tokens

    /// Approximate token count of the original text.
    public let originalEstimatedTokens: Int
    /// Approximate token count of the minified text.
    public let minifiedEstimatedTokens: Int

    public var estimatedTokenReduction: Int {
        max(0, originalEstimatedTokens - minifiedEstimatedTokens)
    }

    public var estimatedTokenReductionPercent: Double {
        guard originalEstimatedTokens > 0 else { return 0 }
        return Double(estimatedTokenReduction) / Double(originalEstimatedTokens) * 100
    }

    // MARK: - Lines

    public let originalLines: Int
    public let minifiedLines: Int

    public var lineReduction: Int {
        max(0, originalLines - minifiedLines)
    }

    public var lineReductionPercent: Double {
        guard originalLines > 0 else { return 0 }
        return Double(lineReduction) / Double(originalLines) * 100
    }

    // MARK: - Init

    public init(
        originalCharacters: Int,
        minifiedCharacters: Int,
        originalEstimatedTokens: Int,
        minifiedEstimatedTokens: Int,
        originalLines: Int,
        minifiedLines: Int
    ) {
        self.originalCharacters = originalCharacters
        self.minifiedCharacters = minifiedCharacters
        self.originalEstimatedTokens = originalEstimatedTokens
        self.minifiedEstimatedTokens = minifiedEstimatedTokens
        self.originalLines = originalLines
        self.minifiedLines = minifiedLines
    }

    // MARK: - Combining

    /// Merge two stats objects (used when assembling document-level stats from block stats).
    public func merging(_ other: MinificationStats) -> MinificationStats {
        MinificationStats(
            originalCharacters: originalCharacters + other.originalCharacters,
            minifiedCharacters: minifiedCharacters + other.minifiedCharacters,
            originalEstimatedTokens: originalEstimatedTokens + other.originalEstimatedTokens,
            minifiedEstimatedTokens: minifiedEstimatedTokens + other.minifiedEstimatedTokens,
            originalLines: originalLines + other.originalLines,
            minifiedLines: minifiedLines + other.minifiedLines
        )
    }

    public static let zero = MinificationStats(
        originalCharacters: 0,
        minifiedCharacters: 0,
        originalEstimatedTokens: 0,
        minifiedEstimatedTokens: 0,
        originalLines: 0,
        minifiedLines: 0
    )
}
