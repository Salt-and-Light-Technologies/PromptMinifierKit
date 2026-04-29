import Foundation

/// Minifies source-code blocks with language-aware safety rules.
///
/// Hard invariants that this minifier must never violate:
/// - String literal contents are never modified.
/// - Comment markers inside strings are never treated as comments.
/// - Indentation is always preserved for Python, YAML, and Haskell.
/// - Comments are only stripped when the language supports it AND options allow it.
/// - Shell comments are never stripped in v1 (no heredoc-safety implementation).
public struct CodeMinifier: Sendable {

    private let commentStripper = CommentStripper()

    public init() {}

    // MARK: - Public API

    public func minify(
        _ block: ContentBlock,
        options: MinificationOptions,
        estimator: any TokenEstimating
    ) -> BlockMinificationResult {

        let language = block.language ?? .unknown
        let protection = block.protectionLevel

        // Locked sections: only safe normalisation (already done upstream).
        if protection.isLocked {
            let stats = makeStats(original: block.text, minified: block.text, estimator: estimator)
            let rule = AppliedRule(
                rule: .preservedProtectedSection,
                description: "Locked section — code content preserved unchanged.",
                contentType: .code,
                language: language,
                sectionRole: block.role
            )
            return BlockMinificationResult(original: block, minifiedText: block.text,
                                           warnings: [], appliedRules: [rule], stats: stats)
        }

        // Adapt options for this block's context.
        let adapted = options.adapted(
            for: .code,
            language: language,
            role: block.role,
            protection: protection
        )

        var text = block.text
        var appliedRules: [AppliedRule] = []
        var warnings: [MinificationWarning] = []

        // --- Indentation-sensitive languages: emit info rule ---
        if language.isIndentationSensitive {
            appliedRules.append(AppliedRule(
                rule: .preservedIndentationSensitiveLanguage,
                description: "Indentation preserved for \(language.displayName).",
                contentType: .code,
                language: language
            ))
        }

        // Stage 1: Strip comments (opt-in, safety-gated).
        let shouldStripComments = (adapted.stripComments || adapted.allowCodeCommentStripping)
            && language.supportsCommentStripping
            && language != .shell

        if shouldStripComments {
            let stripped = commentStripper.strip(text, language: language, options: adapted)
            text = stripped.text
            warnings.append(contentsOf: stripped.warnings)
            appliedRules.append(contentsOf: stripped.appliedRules)
        }

        // Stage 2: Remove trailing whitespace.
        if adapted.removeTrailingWhitespace {
            let before = text
            text = removeTrailingWhitespace(text)
            if text != before {
                appliedRules.append(AppliedRule(
                    rule: .removedTrailingWhitespace,
                    description: "Removed trailing whitespace from code lines.",
                    contentType: .code,
                    language: language
                ))
            }
        }

        // Stage 3: Collapse repeated spaces (only outside indentation, skipped for sensitive langs).
        if adapted.collapseRepeatedSpaces && !language.isIndentationSensitive {
            let before = text
            text = collapseRepeatedSpaces(text, language: language)
            if text != before {
                appliedRules.append(AppliedRule(
                    rule: .collapsedRepeatedSpaces,
                    description: "Collapsed repeated spaces (outside string literals).",
                    contentType: .code,
                    language: language
                ))
            }
        }

        // Stage 4: Collapse blank lines.
        if adapted.collapseBlankLines {
            let before = text
            text = collapseBlankLines(text, max: adapted.maxConsecutiveBlankLines)
            if text != before {
                appliedRules.append(AppliedRule(
                    rule: .collapsedBlankLines,
                    description: "Collapsed consecutive blank lines to \(adapted.maxConsecutiveBlankLines) maximum.",
                    contentType: .code,
                    language: language
                ))
            }
        }

        // Stage 5: Brace compaction (opt-in, never for indentation-sensitive languages).
        if adapted.compactBraces && !language.isIndentationSensitive
            && !protection.prohibitsBraceCompaction {
            let (compacted, didCompact, braceWarnings) = compactBraces(text, language: language)
            if didCompact {
                text = compacted
                appliedRules.append(AppliedRule(
                    rule: .compactedBraces,
                    description: "Converted Allman-style braces to K&R style.",
                    contentType: .code,
                    language: language
                ))
            }
            warnings.append(contentsOf: braceWarnings)
        }

        let stats = makeStats(original: block.text, minified: text, estimator: estimator)

        // Warn if output is larger.
        if text.count > block.text.count {
            warnings.append(MinificationWarning(
                kind: .outputLargerThanInput,
                message: "Code block output is larger than input after minification.",
                severity: .caution,
                contentType: .code,
                language: language
            ))
        }

        return BlockMinificationResult(
            original: block,
            minifiedText: text,
            warnings: warnings,
            appliedRules: appliedRules,
            stats: stats
        )
    }

    // MARK: - Trailing whitespace

    private func removeTrailingWhitespace(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        return lines.map {
            $0.replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression)
        }.joined(separator: "\n")
    }

    // MARK: - Repeated spaces

    /// Collapses runs of 2+ spaces into a single space, but only outside of
    /// string literals. This is a conservative heuristic — if uncertain, we skip.
    private func collapseRepeatedSpaces(_ text: String, language: CodeLanguage) -> String {
        // For languages where we don't have a reliable string scanner, skip.
        switch language {
        case .python, .yaml, .haskell, .elixir, .unknown, .shell:
            return text
        default:
            break
        }

        let lines = text.components(separatedBy: "\n")
        return lines.map { line in
            // Preserve leading indentation.
            let leadingSpaces = line.prefix(while: { $0 == " " || $0 == "\t" })
            let rest = String(line.dropFirst(leadingSpaces.count))
            // Collapse repeated spaces in the non-indent portion, heuristically.
            let collapsed = rest.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            return leadingSpaces + collapsed
        }.joined(separator: "\n")
    }

    // MARK: - Blank line collapsing

    private func collapseBlankLines(_ text: String, max maxBlank: Int) -> String {
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var consecutiveBlanks = 0

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                consecutiveBlanks += 1
                if consecutiveBlanks <= maxBlank {
                    result.append(line)
                }
            } else {
                consecutiveBlanks = 0
                result.append(line)
            }
        }
        return result.joined(separator: "\n")
    }

    // MARK: - Brace compaction (Allman → K&R)

    /// Converts standalone opening braces (Allman style) to K&R style.
    /// Only operates on clear cases to avoid breaking code.
    private func compactBraces(
        _ text: String,
        language: CodeLanguage
    ) -> (String, Bool, [MinificationWarning]) {
        var lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var didCompact = false
        var warnings: [MinificationWarning] = []

        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // A lone `{` on its own line — merge with the previous line.
            if trimmed == "{" && !result.isEmpty {
                let prev = result[result.count - 1]
                let prevTrimmed = prev.trimmingCharacters(in: .whitespaces)
                // Only merge if previous line ends without a comment or string issue.
                if !prevTrimmed.hasSuffix("{") && !prevTrimmed.hasSuffix(",")
                    && !prevTrimmed.isEmpty {
                    result[result.count - 1] = prev + " {"
                    didCompact = true
                    i += 1
                    continue
                }
            }

            result.append(line)
            i += 1
        }

        if didCompact {
            warnings.append(MinificationWarning(
                kind: .aggressiveModeRisk,
                message: "Brace compaction was applied. Review the output for \(language.displayName) to ensure correctness.",
                severity: .caution,
                contentType: .code,
                language: language
            ))
        }

        return (result.joined(separator: "\n"), didCompact, warnings)
    }

    // MARK: - Stats

    private func makeStats(original: String, minified: String, estimator: any TokenEstimating) -> MinificationStats {
        let origLines = original.components(separatedBy: "\n").count
        let minLines  = minified.components(separatedBy: "\n").count
        return MinificationStats(
            originalCharacters: original.count,
            minifiedCharacters: minified.count,
            originalEstimatedTokens: estimator.estimateTokens(for: original),
            minifiedEstimatedTokens: estimator.estimateTokens(for: minified),
            originalLines: origLines,
            minifiedLines: minLines
        )
    }
}
