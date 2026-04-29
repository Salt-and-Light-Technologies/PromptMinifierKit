import Foundation

/// The MinifyAI-specific minifier for rendered prompt packs.
///
/// `PromptPackMinifier` understands the section structure of a prompt pack and
/// applies different minification rules to each section based on its role and
/// protection level. It is the most important safety-critical piece in the
/// PromptMinifierKit pipeline — getting this wrong means the LLM receives a
/// corrupted prompt.
///
/// Section handling by protection level:
/// - `.locked`              → byte-identical output (only upstream normalisation applied)
/// - `.preserveStructure`   → trim whitespace, collapse blank lines; never touch headings/bullets
/// - `.preserveMeaning`     → compact spacing; preserve wording
/// - `.minifiable`          → standard safe minification
/// - `.aggressivelyMinifiable` → aggressive compaction when mode allows
public struct PromptPackMinifier: Sendable {

    private let markdownMinifier  = MarkdownMinifier()
    private let plainTextMinifier = PlainTextMinifier()
    private let codeMinifier      = CodeMinifier()

    public init() {}

    // MARK: - Public API

    /// Minify all blocks from a segmented prompt pack.
    public func minify(
        blocks: [ContentBlock],
        options: MinificationOptions,
        estimator: any TokenEstimating
    ) -> PromptPackMinificationResult {

        var blockResults: [BlockMinificationResult] = []
        var allWarnings: [MinificationWarning] = []
        var allRules: [AppliedRule] = []

        for block in blocks {
            let result = minifyBlock(block, options: options, estimator: estimator)
            blockResults.append(result)
            allWarnings.append(contentsOf: result.warnings)
            allRules.append(contentsOf: result.appliedRules)
        }

        // Re-assemble the full document from block outputs.
        let assembled = blockResults.map(\.minifiedText).joined(separator: "\n")

        return PromptPackMinificationResult(
            blockResults: blockResults,
            assembledText: assembled,
            warnings: allWarnings,
            appliedRules: allRules
        )
    }

    // MARK: - Block dispatch

    private func minifyBlock(
        _ block: ContentBlock,
        options: MinificationOptions,
        estimator: any TokenEstimating
    ) -> BlockMinificationResult {

        let protection = block.protectionLevel

        // Locked: return unchanged (upstream normalisation already applied).
        if protection.isLocked {
            let stats = makeStats(block.text, block.text, estimator)
            let warning = MinificationWarning(
                kind: .lockedSectionNotModified,
                message: "Section '\(block.role?.displayName ?? "unknown")' is locked and was not modified.",
                severity: .info,
                contentType: .promptPack,
                sectionRole: block.role
            )
            let rule = AppliedRule(
                rule: .preservedProtectedSection,
                description: "Locked prompt-pack section '\(block.role?.displayName ?? "unknown")' preserved unchanged.",
                contentType: .promptPack,
                sectionRole: block.role
            )
            return BlockMinificationResult(
                original: block,
                minifiedText: block.text,
                warnings: [warning],
                appliedRules: [rule],
                stats: stats
            )
        }

        // preserveStructure: whitespace cleanup only, no prose compaction.
        if protection == .preserveStructure {
            return minifyPreserveStructure(block, options: options, estimator: estimator)
        }

        // For code blocks embedded in a prompt pack.
        if block.type == .code {
            return codeMinifier.minify(block, options: options, estimator: estimator)
        }

        // preserveMeaning, minifiable, aggressivelyMinifiable: delegate to Markdown minifier.
        return markdownMinifier.minify(block, options: options, estimator: estimator)
    }

    // MARK: - preserveStructure handling

    /// Applies only whitespace-safe transformations to a preserve-structure block.
    private func minifyPreserveStructure(
        _ block: ContentBlock,
        options: MinificationOptions,
        estimator: any TokenEstimating
    ) -> BlockMinificationResult {

        var text = block.text
        var appliedRules: [AppliedRule] = []

        let lines = text.components(separatedBy: "\n")
        var resultLines: [String] = []
        var blanks = 0

        for line in lines {
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty

            if isBlank {
                blanks += 1
                if blanks <= options.maxConsecutiveBlankLines {
                    resultLines.append(line)
                }
            } else {
                blanks = 0
                // Trim trailing whitespace, but preserve hard breaks.
                if options.removeTrailingWhitespace {
                    if options.preserveMarkdownHardBreaks && line.hasSuffix("  ") {
                        resultLines.append(line)
                    } else {
                        resultLines.append(
                            line.replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression)
                        )
                    }
                } else {
                    resultLines.append(line)
                }
            }
        }

        text = resultLines.joined(separator: "\n")

        if text != block.text {
            appliedRules.append(AppliedRule(
                rule: .collapsedBlankLines,
                description: "Trimmed whitespace and collapsed blank lines in preserve-structure section '\(block.role?.displayName ?? "unknown")'.",
                contentType: .promptPack,
                sectionRole: block.role
            ))
        }

        let warning = MinificationWarning(
            kind: .protectedSectionPreserved,
            message: "Section '\(block.role?.displayName ?? "unknown")' has preserveStructure protection — only whitespace was cleaned.",
            severity: .info,
            contentType: .promptPack,
            sectionRole: block.role
        )

        let stats = makeStats(block.text, text, estimator)
        return BlockMinificationResult(
            original: block,
            minifiedText: text,
            warnings: [warning],
            appliedRules: appliedRules,
            stats: stats
        )
    }

    // MARK: - Helpers

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

// MARK: - Result type

public struct PromptPackMinificationResult: Sendable {
    public let blockResults: [BlockMinificationResult]
    public let assembledText: String
    public let warnings: [MinificationWarning]
    public let appliedRules: [AppliedRule]
}
