import Foundation

/// The central orchestrator of the PromptMinifierKit 7-stage pipeline.
///
/// `MinificationEngine` is the only public entry point callers need. It:
/// 1. Normalises input (Stage 1)
/// 2. Classifies content (Stage 2)
/// 3. Segments into blocks (Stage 3)
/// 4. Minifies each block (Stage 4)
/// 5. Validates output (Stage 5)
/// 6. Estimates token savings (Stage 6)
/// 7. Assembles the final `MinificationResult` (Stage 7)
///
/// Design constraints:
/// - No shared mutable state.
/// - No singletons.
/// - Deterministic — same input + options always produces the same output.
/// - Synchronous — callers wrap in a `Task` if needed.
/// - Throws only for hard failures; normal edge cases return warnings.
public final class MinificationEngine: Sendable {

    // MARK: - Pipeline components

    private let normalizer  = InputNormalizer()
    private let classifier  = ContentClassifier()
    private let segmenter   = BlockSegmenter()
    private let validator   = MinificationValidator()

    private let plainTextMinifier  = PlainTextMinifier()
    private let markdownMinifier   = MarkdownMinifier()
    private let codeMinifier       = CodeMinifier()
    private let jsonMinifier       = JSONMinifier()
    private let yamlMinifier       = YAMLMinifier()
    private let logsMinifier       = LogsMinifier()
    private let promptPackMinifier = PromptPackMinifier()

    private let estimator: any TokenEstimating

    // MARK: - Init

    /// Create an engine with the default `ApproximateTokenEstimator`.
    public init() {
        self.estimator = ApproximateTokenEstimator()
    }

    /// Create an engine with a custom token estimator (useful for testing or
    /// injecting a provider-specific tokenizer in the future).
    public init(estimator: any TokenEstimating) {
        self.estimator = estimator
    }

    // MARK: - Convenience entry points

    /// Minify a raw string using safe defaults.
    public func minify(_ input: String) throws -> MinificationResult {
        let request = MinificationRequest(
            input: input,
            options: MinificationOptions(),
            profile: .safePrompt
        )
        return try minify(request)
    }

    /// Minify a raw string with explicit options and profile.
    public func minify(
        _ input: String,
        options: MinificationOptions,
        profile: PromptMinificationProfile = .safePrompt
    ) throws -> MinificationResult {
        let request = MinificationRequest(
            input: input,
            options: options,
            profile: profile
        )
        return try minify(request)
    }

    /// Minify a structured `MinificationRequest`.
    /// This is the canonical entry point.
    public func minify(_ request: MinificationRequest) throws -> MinificationResult {

        // Hard failure: empty input.
        guard !request.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MinificationError.emptyInput
        }

        let options = request.options

        // ── Stage 1: Input Normalisation ─────────────────────────────────────
        let normResult = normalizer.normalize(request.input, options: options)
        let normalizedText = normResult.text
        var allAppliedRules = normResult.appliedRules
        var allWarnings: [MinificationWarning] = []

        // Always emit the approximate-token-estimate warning at document level.
        allWarnings.append(MinificationWarning(
            kind: .approximateTokenEstimate,
            message: "Token counts are approximate estimates based on a character heuristic. Actual token usage will vary by provider and model.",
            severity: .info
        ))

        // ── Stage 2: Content Classification ──────────────────────────────────
        let classification = classifier.classify(normalizedText, options: options)
        allWarnings.append(contentsOf: classification.warnings)

        // ── Stage 3: Block Segmentation ───────────────────────────────────────
        let segmentation = segmenter.segment(
            normalizedText,
            classification: classification,
            options: options,
            protectedSections: request.protectedSections
        )
        allWarnings.append(contentsOf: segmentation.warnings)

        if segmentation.blocks.count > 1 {
            allAppliedRules.append(AppliedRule(
                rule: .segmentedMixedContent,
                description: "Document segmented into \(segmentation.blocks.count) typed blocks for type-specific minification.",
                contentType: classification.contentType
            ))
        }

        // ── Stage 4: Block Minification ───────────────────────────────────────
        var blockResults: [BlockMinificationResult] = []

        // Prompt packs get special batched handling.
        if classification.contentType == .promptPack {
            let packResult = promptPackMinifier.minify(
                blocks: segmentation.blocks,
                options: options,
                estimator: estimator
            )
            blockResults = packResult.blockResults
            allWarnings.append(contentsOf: packResult.warnings)
            allAppliedRules.append(contentsOf: packResult.appliedRules)
        } else {
            for block in segmentation.blocks {
                let result = minifyBlock(block, options: options)
                blockResults.append(result)
                allWarnings.append(contentsOf: result.warnings)
                allAppliedRules.append(contentsOf: result.appliedRules)
            }
        }

        // Assemble output text.
        // Trim trailing newlines from each block before joining so block boundaries
        // never introduce blank lines, regardless of what individual minifiers returned.
        let outputText: String
        if blockResults.count == 1 {
            outputText = blockResults[0].minifiedText
                .trimmingCharacters(in: .newlines)
        } else {
            outputText = blockResults
                .map { $0.minifiedText.trimmingCharacters(in: .newlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }

        // ── Stage 5: Validation ───────────────────────────────────────────────
        let validationWarnings = try validator.validate(
            input: normalizedText,
            output: outputText,
            options: options,
            blockResults: blockResults
        )
        allWarnings.append(contentsOf: validationWarnings)

        // Aggressive mode: emit a risk-level warning.
        if options.processingMode == .aggressive {
            allWarnings.append(MinificationWarning(
                kind: .aggressiveModeRisk,
                message: "Aggressive mode was used. Review the minified output carefully before sending to an LLM.",
                severity: .risk
            ))
        }

        // ── Stage 6: Token Estimation ─────────────────────────────────────────
        let originalTokens  = estimator.estimateTokens(for: normalizedText)
        let minifiedTokens  = estimator.estimateTokens(for: outputText)
        let originalLines   = normalizedText.components(separatedBy: "\n").count
        let minifiedLines   = outputText.components(separatedBy: "\n").count

        let stats = MinificationStats(
            originalCharacters: normalizedText.count,
            minifiedCharacters: outputText.count,
            originalEstimatedTokens: originalTokens,
            minifiedEstimatedTokens: minifiedTokens,
            originalLines: originalLines,
            minifiedLines: minifiedLines
        )

        // Deduplicate rules by kind (keep first occurrence).
        let dedupedRules = deduplicate(allAppliedRules)

        // ── Stage 7: Result Assembly ──────────────────────────────────────────
        return MinificationResult(
            id: UUID(),
            inputText: normalizedText,
            outputText: outputText,
            originalContentType: options.contentType,
            detectedContentType: classification.contentType,
            detectedLanguage: classification.detectedLanguage,
            mode: options.processingMode,
            profile: request.profile,
            options: options,
            stats: stats,
            warnings: allWarnings,
            appliedRules: dedupedRules,
            blockResults: options.includeBlockResults ? blockResults : [],
            createdAt: Date()
        )
    }

    // MARK: - Section-input convenience

    /// Minify an array of pre-labelled `PromptSectionInput` values.
    ///
    /// This skips the classifier and segmenter and works directly with sections
    /// supplied by ContextComposerKit.
    public func minify(
        sections: [PromptSectionInput],
        options: MinificationOptions = MinificationOptions(),
        profile: PromptMinificationProfile = .safePrompt
    ) throws -> MinificationResult {
        guard !sections.isEmpty else { throw MinificationError.emptyInput }

        // Convert to ContentBlocks.
        let blocks = sections.map { section in
            ContentBlock(
                type: .promptPack,
                text: section.content,
                language: nil,
                role: section.role,
                protectionLevel: section.protectionLevel
            )
        }

        let combined = sections.map { $0.content }.joined(separator: "\n")
        let request = MinificationRequest(
            input: combined,
            options: options,
            profile: profile
        )

        // Run a stripped-down pipeline (skip classifier/segmenter, use supplied blocks).
        guard !combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MinificationError.emptyInput
        }

        var allWarnings: [MinificationWarning] = [
            MinificationWarning(
                kind: .approximateTokenEstimate,
                message: "Token counts are approximate estimates.",
                severity: .info
            )
        ]
        var allRules: [AppliedRule] = []
        var blockResults: [BlockMinificationResult] = []

        let packResult = promptPackMinifier.minify(blocks: blocks, options: options, estimator: estimator)
        blockResults = packResult.blockResults
        allWarnings.append(contentsOf: packResult.warnings)
        allRules.append(contentsOf: packResult.appliedRules)

        let outputText = blockResults
            .map { $0.minifiedText.trimmingCharacters(in: .newlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        let validationWarnings = try validator.validate(
            input: combined,
            output: outputText,
            options: options,
            blockResults: blockResults
        )
        allWarnings.append(contentsOf: validationWarnings)

        let stats = MinificationStats(
            originalCharacters: combined.count,
            minifiedCharacters: outputText.count,
            originalEstimatedTokens: estimator.estimateTokens(for: combined),
            minifiedEstimatedTokens: estimator.estimateTokens(for: outputText),
            originalLines: combined.components(separatedBy: "\n").count,
            minifiedLines: outputText.components(separatedBy: "\n").count
        )

        return MinificationResult(
            inputText: combined,
            outputText: outputText,
            originalContentType: .promptPack,
            detectedContentType: .promptPack,
            detectedLanguage: nil,
            mode: options.processingMode,
            profile: profile,
            options: options,
            stats: stats,
            warnings: allWarnings,
            appliedRules: deduplicate(allRules),
            blockResults: options.includeBlockResults ? blockResults : [],
            createdAt: Date()
        )
    }

    // MARK: - Block dispatch

    private func minifyBlock(
        _ block: ContentBlock,
        options: MinificationOptions
    ) -> BlockMinificationResult {
        switch block.type {
        case .plainText:
            return plainTextMinifier.minify(block, options: options, estimator: estimator)
        case .markdown, .mixed:
            return markdownMinifier.minify(block, options: options, estimator: estimator)
        case .code:
            return codeMinifier.minify(block, options: options, estimator: estimator)
        case .json:
            return jsonMinifier.minify(block, options: options, estimator: estimator)
        case .yaml:
            return yamlMinifier.minify(block, options: options, estimator: estimator)
        case .logs:
            return logsMinifier.minify(block, options: options, estimator: estimator)
        case .promptPack:
            // Single-block prompt packs go through the pack minifier.
            let packResult = promptPackMinifier.minify(
                blocks: [block], options: options, estimator: estimator
            )
            return packResult.blockResults.first ?? fallbackResult(block, options: options)
        case .auto:
            // Should not reach here — classifier always resolves .auto.
            return plainTextMinifier.minify(block, options: options, estimator: estimator)
        }
    }

    private func fallbackResult(_ block: ContentBlock, options: MinificationOptions) -> BlockMinificationResult {
        let stats = MinificationStats(
            originalCharacters: block.text.count,
            minifiedCharacters: block.text.count,
            originalEstimatedTokens: estimator.estimateTokens(for: block.text),
            minifiedEstimatedTokens: estimator.estimateTokens(for: block.text),
            originalLines: block.text.components(separatedBy: "\n").count,
            minifiedLines: block.text.components(separatedBy: "\n").count
        )
        return BlockMinificationResult(original: block, minifiedText: block.text,
                                       warnings: [], appliedRules: [], stats: stats)
    }

    // MARK: - Deduplication

    private func deduplicate(_ rules: [AppliedRule]) -> [AppliedRule] {
        var seen = Set<AppliedRuleKind>()
        return rules.filter { seen.insert($0.rule).inserted }
    }
}
