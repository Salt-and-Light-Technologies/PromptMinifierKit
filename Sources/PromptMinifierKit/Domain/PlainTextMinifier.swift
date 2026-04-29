import Foundation

/// Minifies plain prose text blocks.
///
/// Safe behaviour: trims trailing whitespace, collapses blank lines, and
/// optionally collapses repeated spaces. Does **not** rewrite sentences or
/// remove content semantically — that would require an LLM.
public struct PlainTextMinifier: Sendable {

    public init() {}

    public func minify(
        _ block: ContentBlock,
        options: MinificationOptions,
        estimator: any TokenEstimating
    ) -> BlockMinificationResult {

        let protection = block.protectionLevel

        if protection.isLocked {
            let stats = makeStats(original: block.text, minified: block.text, estimator: estimator)
            return BlockMinificationResult(
                original: block,
                minifiedText: block.text,
                warnings: [],
                appliedRules: [lockedRule(block)],
                stats: stats
            )
        }

        let adapted = options.adapted(for: .plainText, language: nil,
                                      role: block.role, protection: protection)

        var text = block.text
        var appliedRules: [AppliedRule] = []

        // 1. Remove trailing whitespace.
        if adapted.removeTrailingWhitespace {
            let before = text
            text = removeTrailingWhitespace(text)
            if text != before {
                appliedRules.append(AppliedRule(
                    rule: .removedTrailingWhitespace,
                    description: "Removed trailing whitespace from text lines.",
                    contentType: .plainText
                ))
            }
        }

        // 2. Collapse repeated spaces (intra-line).
        if adapted.collapseRepeatedSpaces {
            let before = text
            text = text.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            if text != before {
                appliedRules.append(AppliedRule(
                    rule: .collapsedRepeatedSpaces,
                    description: "Collapsed repeated spaces within lines.",
                    contentType: .plainText
                ))
            }
        }

        // 3. Collapse blank lines.
        if adapted.collapseBlankLines {
            let before = text
            text = collapseBlankLines(text, max: adapted.maxConsecutiveBlankLines)
            if text != before {
                appliedRules.append(AppliedRule(
                    rule: .collapsedBlankLines,
                    description: "Collapsed consecutive blank lines to \(adapted.maxConsecutiveBlankLines) maximum.",
                    contentType: .plainText
                ))
            }
        }

        let stats = makeStats(original: block.text, minified: text, estimator: estimator)
        return BlockMinificationResult(
            original: block,
            minifiedText: text,
            warnings: [],
            appliedRules: appliedRules,
            stats: stats
        )
    }

    // MARK: - Helpers

    private func removeTrailingWhitespace(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression) }
            .joined(separator: "\n")
    }

    private func collapseBlankLines(_ text: String, max maxBlank: Int) -> String {
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var blanks = 0
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                blanks += 1
                if blanks <= maxBlank { result.append(line) }
            } else {
                blanks = 0
                result.append(line)
            }
        }
        return result.joined(separator: "\n")
    }

    private func lockedRule(_ block: ContentBlock) -> AppliedRule {
        AppliedRule(
            rule: .preservedProtectedSection,
            description: "Locked section — plain text preserved unchanged.",
            contentType: .plainText,
            sectionRole: block.role
        )
    }

    private func makeStats(original: String, minified: String, estimator: any TokenEstimating) -> MinificationStats {
        MinificationStats(
            originalCharacters: original.count,
            minifiedCharacters: minified.count,
            originalEstimatedTokens: estimator.estimateTokens(for: original),
            minifiedEstimatedTokens: estimator.estimateTokens(for: minified),
            originalLines: original.components(separatedBy: "\n").count,
            minifiedLines: minified.components(separatedBy: "\n").count
        )
    }
}
