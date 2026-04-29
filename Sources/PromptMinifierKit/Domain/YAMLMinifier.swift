import Foundation

/// Conservative YAML minifier.
///
/// YAML is structurally sensitive: indentation is significant, and `#` characters
/// inside quoted strings are not comments. A naive stripper would break valid YAML.
///
/// v1 policy: only safe whitespace normalisation is applied. No comment stripping,
/// no inline-structure compaction, no key reordering. A conservative warning is
/// always returned so the user knows the savings are limited.
public struct YAMLMinifier: Sendable {

    public init() {}

    public func minify(
        _ block: ContentBlock,
        options: MinificationOptions,
        estimator: any TokenEstimating
    ) -> BlockMinificationResult {

        let protection = block.protectionLevel

        if protection.isLocked {
            let stats = makeStats(block.text, block.text, estimator)
            return BlockMinificationResult(
                original: block,
                minifiedText: block.text,
                warnings: [],
                appliedRules: [AppliedRule(
                    rule: .preservedProtectedSection,
                    description: "Locked section — YAML preserved unchanged.",
                    contentType: .yaml
                )],
                stats: stats
            )
        }

        var text = block.text
        var appliedRules: [AppliedRule] = []

        // 1. Remove trailing whitespace (safe for YAML — indentation is leading, not trailing).
        if options.removeTrailingWhitespace {
            let before = text
            text = text.components(separatedBy: "\n")
                .map { $0.replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression) }
                .joined(separator: "\n")
            if text != before {
                appliedRules.append(AppliedRule(
                    rule: .removedTrailingWhitespace,
                    description: "Removed trailing whitespace from YAML lines.",
                    contentType: .yaml
                ))
            }
        }

        // 2. Collapse excessive blank lines conservatively (max 1 in YAML).
        if options.collapseBlankLines {
            let effectiveMax = min(options.maxConsecutiveBlankLines, 1)
            let before = text
            text = collapseBlankLines(text, max: effectiveMax)
            if text != before {
                appliedRules.append(AppliedRule(
                    rule: .collapsedBlankLines,
                    description: "Collapsed consecutive blank lines in YAML (conservative, max 1).",
                    contentType: .yaml
                ))
            }
        }

        // 3. Apply the conservative YAML rule.
        appliedRules.append(AppliedRule(
            rule: .conservativeYAML,
            description: "YAML minification is conservative: indentation, comments, and structure preserved.",
            contentType: .yaml
        ))

        let warnings: [MinificationWarning] = [
            MinificationWarning(
                kind: .yamlMinificationConservative,
                message: "YAML minification is conservative in v1. Only trailing whitespace and excessive blank lines were removed. Comment stripping and structural compaction are disabled to prevent corruption.",
                severity: .info,
                contentType: .yaml
            ),
            MinificationWarning(
                kind: .approximateTokenEstimate,
                message: "Token counts for this YAML block are approximate estimates.",
                severity: .info,
                contentType: .yaml
            )
        ]

        let stats = makeStats(block.text, text, estimator)
        return BlockMinificationResult(
            original: block,
            minifiedText: text,
            warnings: warnings,
            appliedRules: appliedRules,
            stats: stats
        )
    }

    // MARK: - Helpers

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

    private func makeStats(_ original: String, _ minified: String, _ estimator: any TokenEstimating) -> MinificationStats {
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
