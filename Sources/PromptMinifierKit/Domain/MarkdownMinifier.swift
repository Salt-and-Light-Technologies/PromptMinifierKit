import Foundation

/// Minifies Markdown content while preserving structural elements.
///
/// Responsibilities:
/// - Preserve headings, bullet lists, numbered lists, tables, and hard breaks.
/// - Detect and buffer fenced code blocks; dispatch their interiors to `CodeMinifier`.
/// - Handle unclosed fences gracefully with a warning.
/// - Optionally strip low-value annotations (only when `allowMarkdownAnnotationStripping`
///   is explicitly enabled — disabled by default).
public struct MarkdownMinifier: Sendable {

    private let codeMinifier = CodeMinifier()
    private let plainTextMinifier = PlainTextMinifier()

    public init() {}

    // MARK: - Public API

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
                appliedRules: [AppliedRule(
                    rule: .preservedProtectedSection,
                    description: "Locked section — Markdown preserved unchanged.",
                    contentType: .markdown,
                    sectionRole: block.role
                )],
                stats: stats
            )
        }

        let adapted = options.adapted(for: .markdown, language: nil,
                                      role: block.role, protection: protection)

        var warnings: [MinificationWarning] = []
        var appliedRules: [AppliedRule] = []
        let outputLines = processLines(
            block.text,
            options: adapted,
            block: block,
            estimator: estimator,
            warnings: &warnings,
            appliedRules: &appliedRules
        )

        var output = outputLines.joined(separator: "\n")

        // Collapse blank lines in the assembled prose.
        if adapted.collapseBlankLines {
            let before = output
            output = collapseBlankLines(output, max: adapted.maxConsecutiveBlankLines)
            if output != before {
                appliedRules.append(AppliedRule(
                    rule: .collapsedBlankLines,
                    description: "Collapsed consecutive blank lines in Markdown prose.",
                    contentType: .markdown
                ))
            }
        }

        let stats = makeStats(original: block.text, minified: output, estimator: estimator)

        if output.count > block.text.count {
            warnings.append(MinificationWarning(
                kind: .outputLargerThanInput,
                message: "Markdown block output is larger than input.",
                severity: .caution,
                contentType: .markdown
            ))
        }

        return BlockMinificationResult(
            original: block,
            minifiedText: output,
            warnings: warnings,
            appliedRules: appliedRules,
            stats: stats
        )
    }

    // MARK: - Line processor

    private func processLines(
        _ text: String,
        options: MinificationOptions,
        block: ContentBlock,
        estimator: any TokenEstimating,
        warnings: inout [MinificationWarning],
        appliedRules: inout [AppliedRule]
    ) -> [String] {

        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var i = 0
        var inFence = false
        var fenceMarker = ""
        var fenceLanguage: CodeLanguage? = nil
        var fenceContent: [String] = []
        var fenceStartLine = 0

        while i < lines.count {
            let line = lines[i]

            if !inFence {
                // Detect fence open.
                if line.hasPrefix("```") || line.hasPrefix("~~~") {
                    let marker = line.hasPrefix("```") ? "```" : "~~~"
                    let hint = String(line.dropFirst(marker.count))
                        .trimmingCharacters(in: .whitespaces)
                    fenceMarker = marker
                    fenceLanguage = hint.isEmpty ? nil : CodeLanguage.from(fenceHint: hint)
                    inFence = true
                    fenceContent = [line]
                    fenceStartLine = i
                    i += 1
                    continue
                }

                // Normal prose line processing.
                var processedLine = line

                // Remove trailing whitespace — but preserve Markdown hard breaks (2 trailing spaces).
                if options.removeTrailingWhitespace {
                    if options.preserveMarkdownHardBreaks && line.hasSuffix("  ") {
                        // Keep the two trailing spaces.
                        processedLine = line.replacingOccurrences(
                            of: #"[ \t]{3,}$"#, with: "  ", options: .regularExpression
                        )
                    } else {
                        processedLine = line.replacingOccurrences(
                            of: #"[ \t]+$"#, with: "", options: .regularExpression
                        )
                    }
                }

                result.append(processedLine)
            } else {
                // Inside a fenced code block.
                fenceContent.append(line)

                // Detect fence close.
                let stripped = line.trimmingCharacters(in: .whitespaces)
                let isClose = stripped == fenceMarker
                    || (stripped.hasPrefix(fenceMarker) && stripped.dropFirst(fenceMarker.count).allSatisfy { $0 == " " })

                if isClose {
                    inFence = false
                    // Minify the fenced block content (everything between open/close lines).
                    let minifiedLines = minifyFencedBlock(
                        lines: fenceContent,
                        openMarker: fenceContent[0],
                        closeMarker: line,
                        language: fenceLanguage,
                        parentBlock: block,
                        options: options,
                        estimator: estimator,
                        appliedRules: &appliedRules
                    )
                    result.append(contentsOf: minifiedLines)
                    fenceContent = []
                    fenceLanguage = nil
                    fenceMarker = ""
                }
            }

            i += 1
        }

        // Unclosed fence at EOF.
        if inFence {
            warnings.append(MinificationWarning(
                kind: .unclosedCodeFence,
                message: "Unclosed fenced code block starting at line \(fenceStartLine). Preserving block content unchanged.",
                severity: .caution,
                contentType: .markdown,
                language: fenceLanguage
            ))
            result.append(contentsOf: fenceContent)
        }

        return result
    }

    // MARK: - Fenced code block minification

    private func minifyFencedBlock(
        lines: [String],
        openMarker: String,
        closeMarker: String,
        language: CodeLanguage?,
        parentBlock: ContentBlock,
        options: MinificationOptions,
        estimator: any TokenEstimating,
        appliedRules: inout [AppliedRule]
    ) -> [String] {

        guard lines.count >= 2 else { return lines }

        // Extract the interior (between the fence markers).
        let interior = lines.dropFirst().dropLast().joined(separator: "\n")

        let lang = language ?? .unknown
        let protection: PromptSectionProtectionLevel = lang.isIndentationSensitive
            ? .preserveStructure : .minifiable

        let innerBlock = ContentBlock(
            type: .code,
            text: interior,
            language: lang,
            role: .code,
            protectionLevel: protection
        )

        let codeResult = codeMinifier.minify(innerBlock, options: options, estimator: estimator)
        appliedRules.append(contentsOf: codeResult.appliedRules)

        if codeResult.minifiedText != interior {
            appliedRules.append(AppliedRule(
                rule: .minifiedFencedCodeBlock,
                description: "Minified fenced \(lang.displayName) code block.",
                contentType: .markdown,
                language: lang
            ))
        }

        // Re-assemble with original fence markers (preserving language hint).
        let minifiedLines = codeResult.minifiedText.components(separatedBy: "\n")
        return [openMarker] + minifiedLines + [closeMarker]
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
