import Foundation

/// Conservative log output minifier.
///
/// Log content often contains critical debugging information: timestamps, log
/// levels, stack traces, and exception messages. This minifier only applies
/// safe whitespace transformations and never removes or reorders lines.
///
/// Optional deduplication of consecutive identical lines is available but
/// disabled by default.
public struct LogsMinifier: Sendable {

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
                    description: "Locked section — log content preserved unchanged.",
                    contentType: .logs
                )],
                stats: stats
            )
        }

        var text = block.text
        var appliedRules: [AppliedRule] = []

        // 1. Remove trailing whitespace.
        if options.removeTrailingWhitespace {
            let before = text
            text = text.components(separatedBy: "\n")
                .map { $0.replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression) }
                .joined(separator: "\n")
            if text != before {
                appliedRules.append(AppliedRule(
                    rule: .removedTrailingWhitespace,
                    description: "Removed trailing whitespace from log lines.",
                    contentType: .logs
                ))
            }
        }

        // 2. Collapse excessive blank lines (logs rarely need multiple blank lines).
        if options.collapseBlankLines {
            let before = text
            text = collapseBlankLines(text, max: options.maxConsecutiveBlankLines)
            if text != before {
                appliedRules.append(AppliedRule(
                    rule: .collapsedBlankLines,
                    description: "Collapsed consecutive blank lines in log output.",
                    contentType: .logs
                ))
            }
        }

        appliedRules.append(AppliedRule(
            rule: .conservativeLogs,
            description: "Log minification is conservative: line order, timestamps, and stack traces preserved.",
            contentType: .logs
        ))

        let warnings: [MinificationWarning] = [
            MinificationWarning(
                kind: .logsMinificationConservative,
                message: "Log minification is conservative. Timestamps, log levels, and stack traces are preserved. Line ordering is unchanged.",
                severity: .info,
                contentType: .logs
            ),
            MinificationWarning(
                kind: .approximateTokenEstimate,
                message: "Token counts for this log block are approximate estimates.",
                severity: .info,
                contentType: .logs
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
