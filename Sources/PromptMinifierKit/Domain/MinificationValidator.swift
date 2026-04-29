import Foundation

/// Stage 5 of the minification pipeline.
///
/// `MinificationValidator` performs practical safety checks on the assembled
/// output. It does **not** claim to prove semantic equivalence — that is
/// impossible without running the LLM. It makes the checks that are tractable:
/// structural integrity, size sanity, and locked-section fidelity.
public struct MinificationValidator: Sendable {

    public init() {}

    // MARK: - Public API

    /// Validate `output` against `input` and return any validation warnings.
    /// Throws `MinificationError.validationFailed` only for hard failures.
    public func validate(
        input: String,
        output: String,
        options: MinificationOptions,
        blockResults: [BlockMinificationResult]
    ) throws -> [MinificationWarning] {

        var warnings: [MinificationWarning] = []

        // 1. Non-empty input must not produce empty output.
        if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if options.failIfOutputLarger {
                throw MinificationError.validationFailed(
                    "Output is empty but input was not. This indicates a minification error."
                )
            }
            warnings.append(MinificationWarning(
                kind: .outputEmpty,
                message: "The minified output is empty, but the input was not. Review the minification settings.",
                severity: .error
            ))
        }

        // 2. Output larger than input.
        if output.count > input.count {
            if options.failIfOutputLarger {
                throw MinificationError.validationFailed(
                    "Output (\(output.count) chars) is larger than input (\(input.count) chars)."
                )
            }
            warnings.append(MinificationWarning(
                kind: .outputLargerThanInput,
                message: "The minified output (\(output.count) chars) is larger than the input (\(input.count) chars). This can happen when JSON is reformatted or when content could not be safely compacted.",
                severity: .caution
            ))
        }

        // 3. Validate locked sections are unchanged.
        for result in blockResults {
            let block = result.original
            if block.protectionLevel.isLocked {
                // Normalise both sides to LF for comparison.
                let originalNorm = block.text
                    .replacingOccurrences(of: "\r\n", with: "\n")
                    .replacingOccurrences(of: "\r", with: "\n")
                let minifiedNorm = result.minifiedText
                    .replacingOccurrences(of: "\r\n", with: "\n")
                    .replacingOccurrences(of: "\r", with: "\n")

                if originalNorm != minifiedNorm {
                    warnings.append(MinificationWarning(
                        kind: .validationFailed,
                        message: "Locked section '\(block.role?.displayName ?? "unknown")' was modified during minification. This is a bug — please report it.",
                        severity: .error,
                        contentType: block.type,
                        sectionRole: block.role
                    ))
                }
            }
        }

        // 4. JSON blocks must remain valid JSON after minification.
        for result in blockResults where result.original.type == .json {
            let minifiedText = result.minifiedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !minifiedText.isEmpty {
                if let data = minifiedText.data(using: .utf8),
                   (try? JSONSerialization.jsonObject(with: data)) == nil {
                    warnings.append(MinificationWarning(
                        kind: .invalidJSON,
                        message: "A JSON block is no longer valid JSON after minification. Original may be safer to use.",
                        severity: .risk,
                        contentType: .json
                    ))
                }
            }
        }

        // 5. Fenced code blocks must remain balanced.
        let inputFenceCount = countFences(in: input)
        let outputFenceCount = countFences(in: output)
        if inputFenceCount != outputFenceCount {
            warnings.append(MinificationWarning(
                kind: .unclosedCodeFence,
                message: "The number of fenced code block markers changed from \(inputFenceCount) to \(outputFenceCount) during minification. Output may be structurally broken.",
                severity: .risk
            ))
        }

        return warnings
    }

    // MARK: - Helpers

    private func countFences(in text: String) -> Int {
        text.components(separatedBy: "\n")
            .filter { $0.hasPrefix("```") || $0.hasPrefix("~~~") }
            .count
    }
}
