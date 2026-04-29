import Foundation

/// Minifies JSON content using Foundation's `JSONSerialization`.
///
/// If the input is valid JSON, it is re-serialised to compact form.
/// If the input is invalid (or becomes invalid after JSONC comment stripping),
/// the original text is returned with a warning — never silently corrupted.
public struct JSONMinifier: Sendable {

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
                    description: "Locked section — JSON preserved unchanged.",
                    contentType: .json
                )],
                stats: stats
            )
        }

        guard options.compactJSON else {
            // compactJSON disabled — return with only safe whitespace normalisation.
            let cleaned = removeTrailingWhitespace(block.text)
            let stats = makeStats(block.text, cleaned, estimator)
            return BlockMinificationResult(original: block, minifiedText: cleaned,
                                           warnings: [], appliedRules: [], stats: stats)
        }

        var warnings: [MinificationWarning] = []
        var appliedRules: [AppliedRule] = []

        // Always warn that token count is estimated.
        warnings.append(MinificationWarning(
            kind: .approximateTokenEstimate,
            message: "Token counts for this JSON block are approximate estimates.",
            severity: .info,
            contentType: .json
        ))

        let input = block.text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = input.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            // Invalid JSON — preserve original with warning.
            warnings.append(MinificationWarning(
                kind: .invalidJSON,
                message: "Input is not valid JSON. Original text preserved without modification.",
                severity: .caution,
                contentType: .json
            ))
            let stats = makeStats(block.text, block.text, estimator)
            return BlockMinificationResult(original: block, minifiedText: block.text,
                                           warnings: warnings, appliedRules: [], stats: stats)
        }

        // Re-serialise to compact form.
        guard let compactData = try? JSONSerialization.data(withJSONObject: obj, options: []),
              let compactString = String(data: compactData, encoding: .utf8) else {
            warnings.append(MinificationWarning(
                kind: .invalidJSON,
                message: "JSON re-serialisation failed. Original text preserved.",
                severity: .caution,
                contentType: .json
            ))
            let stats = makeStats(block.text, block.text, estimator)
            return BlockMinificationResult(original: block, minifiedText: block.text,
                                           warnings: warnings, appliedRules: [], stats: stats)
        }

        // Warn about potential key ordering change (JSONSerialization may reorder).
        if compactString != input {
            warnings.append(MinificationWarning(
                kind: .jsonKeyOrderMayChange,
                message: "JSON was re-serialised to compact form. Key ordering may differ from the original.",
                severity: .info,
                contentType: .json
            ))
            appliedRules.append(AppliedRule(
                rule: .compactedJSON,
                description: "Re-serialised JSON to compact single-line form.",
                contentType: .json
            ))
        }

        let stats = makeStats(block.text, compactString, estimator)
        return BlockMinificationResult(
            original: block,
            minifiedText: compactString,
            warnings: warnings,
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
