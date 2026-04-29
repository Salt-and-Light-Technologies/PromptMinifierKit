import Foundation

/// A type that can estimate the number of tokens in a string.
///
/// Token counts are **always estimates** unless a provider-specific tokenizer is
/// injected. All implementations must be deterministic and `Sendable`.
public protocol TokenEstimating: Sendable {
    func estimateTokens(for text: String) -> Int
}

/// A simple character-based token estimator.
///
/// Uses the well-known approximation of ~4 characters per token, with a slight
/// word-boundary correction that improves accuracy for mixed code/prose content.
///
/// Always treat these counts as estimates (~). Never display them without a
/// qualifier in the UI.
public struct ApproximateTokenEstimator: TokenEstimating {

    public init() {}

    public func estimateTokens(for text: String) -> Int {
        guard !text.isEmpty else { return 0 }

        // Heuristic:
        // - Split into "words" by whitespace.
        // - Each word contributes approximately ceil(charCount / 3.5) tokens.
        // - Each whitespace gap contributes 0.25 tokens on average.
        // - Clamp minimum at 1 token per non-empty input.
        //
        // This is more accurate than the naive char/4 for code (where tokens
        // tend to be shorter) and for prose (where tokens align with word boundaries).

        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        if words.isEmpty { return 0 }

        var total = 0.0
        for word in words {
            // Short words (≤3 chars) usually map to 1 token.
            // Longer words map to roughly ceil(len / 3.5).
            let len = Double(word.count)
            if len <= 3 {
                total += 1.0
            } else {
                total += ceil(len / 3.5)
            }
        }

        // Add whitespace token fraction.
        total += Double(words.count) * 0.25

        return max(1, Int(ceil(total)))
    }
}

/// A deterministic fixed-ratio estimator for use in unit tests.
/// Returns exactly `ceil(characterCount / 4)`.
public struct NaiveTokenEstimator: TokenEstimating {

    public init() {}

    public func estimateTokens(for text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return Int(ceil(Double(text.count) / 4.0))
    }
}
