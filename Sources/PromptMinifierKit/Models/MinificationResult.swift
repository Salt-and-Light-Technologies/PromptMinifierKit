import Foundation

/// The complete output of a minification pass.
///
/// This type is the primary value returned by `MinificationEngine`. It contains
/// everything the MinifyAI app needs to render a before/after comparison,
/// display warnings, show applied rules, and let the user decide whether to
/// use the original or minified text.
public struct MinificationResult: Codable, Sendable, Hashable {
    public let id: UUID

    // MARK: - Text

    /// The original input text (after normalisation; not modified).
    public let inputText: String
    /// The minified output text.
    public let outputText: String

    // MARK: - Classification

    /// The content type declared in the options (may be `.auto`).
    public let originalContentType: ContentType
    /// The content type that the classifier actually detected.
    public let detectedContentType: ContentType
    /// The programming language detected, if any.
    public let detectedLanguage: CodeLanguage?

    // MARK: - Configuration

    public let mode: ProcessingMode
    public let profile: PromptMinificationProfile
    public let options: MinificationOptions

    // MARK: - Results

    /// Aggregate statistics across all blocks.
    public let stats: MinificationStats
    /// All warnings produced during this pass (document + block level).
    public let warnings: [MinificationWarning]
    /// All transformations applied during this pass.
    public let appliedRules: [AppliedRule]
    /// Per-block results (populated when `options.includeBlockResults == true`).
    public let blockResults: [BlockMinificationResult]

    // MARK: - Metadata

    public let createdAt: Date

    // MARK: - Init

    public init(
        id: UUID = UUID(),
        inputText: String,
        outputText: String,
        originalContentType: ContentType,
        detectedContentType: ContentType,
        detectedLanguage: CodeLanguage?,
        mode: ProcessingMode,
        profile: PromptMinificationProfile,
        options: MinificationOptions,
        stats: MinificationStats,
        warnings: [MinificationWarning],
        appliedRules: [AppliedRule],
        blockResults: [BlockMinificationResult],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.inputText = inputText
        self.outputText = outputText
        self.originalContentType = originalContentType
        self.detectedContentType = detectedContentType
        self.detectedLanguage = detectedLanguage
        self.mode = mode
        self.profile = profile
        self.options = options
        self.stats = stats
        self.warnings = warnings
        self.appliedRules = appliedRules
        self.blockResults = blockResults
        self.createdAt = createdAt
    }

    // MARK: - Convenience

    /// `true` if the minified output is shorter than the input.
    public var didReduce: Bool {
        outputText.count < inputText.count
    }

    /// `true` if any warning has severity `.risk` or `.error`.
    public var hasRiskyWarnings: Bool {
        warnings.contains { $0.severity >= .risk }
    }

    /// The highest-severity warning in the result, or `nil` if there are none.
    public var maxWarningSeverity: WarningSeverity? {
        warnings.map(\.severity).max()
    }
}
