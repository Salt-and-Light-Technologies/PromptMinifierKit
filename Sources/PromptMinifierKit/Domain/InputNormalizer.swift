import Foundation

/// Stage 1 of the minification pipeline.
///
/// `InputNormalizer` performs safe, formatting-only transformations on raw input
/// text before it reaches the classifier or minifiers. It never changes semantic
/// content — only whitespace encoding and BOM artefacts.
public struct InputNormalizer: Sendable {

    public init() {}

    // MARK: - Public API

    /// Normalise `text` according to `options` and return the cleaned string
    /// together with any rules that were applied.
    public func normalize(_ text: String, options: MinificationOptions) -> NormalizationResult {
        var result = text
        var appliedRules: [AppliedRule] = []

        // 1. Strip UTF-8 BOM (\u{FEFF}) if present.
        if result.hasPrefix("\u{FEFF}") {
            result = String(result.dropFirst())
            appliedRules.append(AppliedRule(
                rule: .strippedBOM,
                description: "Removed UTF-8 Byte Order Mark (BOM) from the start of the input."
            ))
        }

        // 2. Normalise CRLF (\r\n) and standalone CR (\r) to LF (\n).
        let beforeLineNorm = result
        result = result
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if result != beforeLineNorm {
            appliedRules.append(AppliedRule(
                rule: .normalizedLineEndings,
                description: "Normalised CRLF and CR line endings to LF."
            ))
        }

        // 3. Remove trailing whitespace from each line (if enabled).
        if options.removeTrailingWhitespace {
            let before = result
            result = normalizeTrailingWhitespace(result)
            if result != before {
                appliedRules.append(AppliedRule(
                    rule: .removedTrailingWhitespace,
                    description: "Removed trailing whitespace from one or more lines."
                ))
            }
        }

        return NormalizationResult(text: result, appliedRules: appliedRules)
    }

    // MARK: - Helpers

    private func normalizeTrailingWhitespace(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let trimmed = lines.map { $0.replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression) }
        return trimmed.joined(separator: "\n")
    }
}

// MARK: - Result type

public struct NormalizationResult: Sendable {
    /// The normalised text.
    public let text: String
    /// Transformations that were applied.
    public let appliedRules: [AppliedRule]
}
