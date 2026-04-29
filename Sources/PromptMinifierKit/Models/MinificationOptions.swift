import Foundation

/// All knobs that control how PromptMinifierKit transforms content.
///
/// The defaults represent the **safe** profile: conservative, non-destructive,
/// and opt-in for anything that might change meaning or break code.
public struct MinificationOptions: Codable, Sendable, Hashable {

    // MARK: - Content

    /// The declared content type. Use `.auto` to let the classifier decide.
    public var contentType: ContentType

    /// The declared code language (used when `contentType == .code`).
    public var codeLanguage: CodeLanguage

    /// The processing mode governing overall aggressiveness.
    public var processingMode: ProcessingMode

    // MARK: - Whitespace

    /// Remove trailing whitespace from every line.
    public var removeTrailingWhitespace: Bool

    /// Collapse two-or-more consecutive spaces into one (outside string literals).
    public var collapseRepeatedSpaces: Bool

    /// Replace runs of consecutive blank lines with at most `maxConsecutiveBlankLines`.
    public var collapseBlankLines: Bool

    /// Maximum number of blank lines to allow in a row when `collapseBlankLines` is `true`.
    public var maxConsecutiveBlankLines: Int

    // MARK: - Code

    /// Strip comments (opt-in; requires language support; dangerous in prompt packs).
    public var stripComments: Bool

    /// Never remove indentation (mandatory for Python, YAML, etc.).
    public var preserveIndentation: Bool

    /// Compact Allman-style braces to K&R style when it is safe to do so.
    public var compactBraces: Bool

    /// Compact valid JSON to its minimal single-line form.
    public var compactJSON: Bool

    /// Attempt to detect and segment mixed-content documents.
    public var detectMixedContent: Bool

    // MARK: - Markdown

    /// Never remove or alter Markdown headings (`#`, `##`, …).
    public var preserveMarkdownHeadings: Bool

    /// Keep bullet list structure intact (indentation, markers).
    public var preserveBulletStructure: Bool

    /// Keep numbered list structure intact.
    public var preserveNumberedLists: Bool

    /// Keep the language hint on fenced code blocks (` ```swift `, etc.).
    public var preserveFencedCodeLanguageTags: Bool

    /// Keep trailing double-space hard-breaks in Markdown.
    public var preserveMarkdownHardBreaks: Bool

    // MARK: - Prompt-pack safety

    /// Apply protection-level rules to prompt-pack sections.
    public var protectPromptSections: Bool

    /// Allow more aggressive prose compaction in applicable sections.
    public var allowAggressiveProseCompaction: Bool

    /// Allow comment stripping inside code sections of a prompt pack.
    public var allowCodeCommentStripping: Bool

    /// Allow removal of low-value Markdown annotations (opt-in, dangerous).
    public var allowMarkdownAnnotationStripping: Bool

    // MARK: - Output validation

    /// Treat output-larger-than-input as an error (rather than a warning).
    public var failIfOutputLarger: Bool

    /// Include per-block minification results in the final `MinificationResult`.
    public var includeBlockResults: Bool

    // MARK: - Initialisers

    public init(
        contentType: ContentType = .auto,
        codeLanguage: CodeLanguage = .unknown,
        processingMode: ProcessingMode = .safe,
        removeTrailingWhitespace: Bool = true,
        collapseRepeatedSpaces: Bool = true,
        collapseBlankLines: Bool = true,
        maxConsecutiveBlankLines: Int = 0,
        stripComments: Bool = false,
        preserveIndentation: Bool = true,
        compactBraces: Bool = false,
        compactJSON: Bool = true,
        detectMixedContent: Bool = true,
        preserveMarkdownHeadings: Bool = true,
        preserveBulletStructure: Bool = true,
        preserveNumberedLists: Bool = true,
        preserveFencedCodeLanguageTags: Bool = true,
        preserveMarkdownHardBreaks: Bool = true,
        protectPromptSections: Bool = true,
        allowAggressiveProseCompaction: Bool = false,
        allowCodeCommentStripping: Bool = false,
        allowMarkdownAnnotationStripping: Bool = false,
        failIfOutputLarger: Bool = false,
        includeBlockResults: Bool = true
    ) {
        self.contentType = contentType
        self.codeLanguage = codeLanguage
        self.processingMode = processingMode
        self.removeTrailingWhitespace = removeTrailingWhitespace
        self.collapseRepeatedSpaces = collapseRepeatedSpaces
        self.collapseBlankLines = collapseBlankLines
        self.maxConsecutiveBlankLines = maxConsecutiveBlankLines
        self.stripComments = stripComments
        self.preserveIndentation = preserveIndentation
        self.compactBraces = compactBraces
        self.compactJSON = compactJSON
        self.detectMixedContent = detectMixedContent
        self.preserveMarkdownHeadings = preserveMarkdownHeadings
        self.preserveBulletStructure = preserveBulletStructure
        self.preserveNumberedLists = preserveNumberedLists
        self.preserveFencedCodeLanguageTags = preserveFencedCodeLanguageTags
        self.preserveMarkdownHardBreaks = preserveMarkdownHardBreaks
        self.protectPromptSections = protectPromptSections
        self.allowAggressiveProseCompaction = allowAggressiveProseCompaction
        self.allowCodeCommentStripping = allowCodeCommentStripping
        self.allowMarkdownAnnotationStripping = allowMarkdownAnnotationStripping
        self.failIfOutputLarger = failIfOutputLarger
        self.includeBlockResults = includeBlockResults
    }

    // MARK: - Named defaults

    /// Conservative defaults — alias for the default initialiser.
    public static let safePromptDefaults = MinificationOptions()

    /// Readable: only safe normalisation, no compaction.
    public static let readableDefaults = MinificationOptions(
        processingMode: .readable,
        collapseRepeatedSpaces: false,
        collapseBlankLines: true,
        maxConsecutiveBlankLines: 0,
        compactJSON: false
    )

    /// Aggressive: opt-in heavy compaction (always review warnings).
    public static let aggressiveDefaults = MinificationOptions(
        processingMode: .aggressive,
        maxConsecutiveBlankLines: 0,
        compactBraces: true,
        allowAggressiveProseCompaction: true,
        allowCodeCommentStripping: true
    )

    /// Code-heavy: preserves code correctness above token savings.
    public static let codeHeavyDefaults = MinificationOptions(
        processingMode: .codeHeavy,
        stripComments: false,
        preserveIndentation: true,
        compactBraces: false,
        allowCodeCommentStripping: false
    )

    // MARK: - Adaptation

    /// Returns a copy of these options adjusted for a specific block context.
    ///
    /// Hard safety rules:
    /// - Locked sections skip almost all transformations.
    /// - Python and YAML always have indentation preserved.
    /// - Unknown or shell languages never strip comments.
    /// - Hard constraints and tasks are never aggressively minified.
    public func adapted(
        for contentType: ContentType,
        language: CodeLanguage?,
        role: PromptSectionRole?,
        protection: PromptSectionProtectionLevel
    ) -> MinificationOptions {
        var opts = self
        let lang = language ?? .unknown

        // --- Protection level overrides ---
        if protection.isLocked {
            opts.stripComments = false
            opts.compactBraces = false
            opts.collapseRepeatedSpaces = false
            opts.allowAggressiveProseCompaction = false
            opts.allowCodeCommentStripping = false
            opts.allowMarkdownAnnotationStripping = false
            opts.compactJSON = false
            // Keep removeTrailingWhitespace and collapseBlankLines as safe normalisation.
            return opts
        }

        if protection <= .preserveStructure {
            opts.compactBraces = false
            opts.allowAggressiveProseCompaction = false
            opts.allowMarkdownAnnotationStripping = false
        }

        // --- Language-specific overrides ---
        if lang.isIndentationSensitive {
            opts.preserveIndentation = true
            opts.collapseRepeatedSpaces = false
            opts.compactBraces = false
        }

        if !lang.supportsCommentStripping {
            opts.stripComments = false
            opts.allowCodeCommentStripping = false
        }

        // Shell: no comment stripping in v1 (heredoc safety not implemented).
        if lang == .shell {
            opts.stripComments = false
            opts.allowCodeCommentStripping = false
        }

        // YAML: never compact inline structures.
        if lang == .yaml || contentType == .yaml {
            opts.compactBraces = false
            opts.compactJSON = false
            opts.collapseRepeatedSpaces = false
            opts.preserveIndentation = true
        }

        // --- Role-specific overrides ---
        if let role {
            switch role {
            case .task, .hardConstraints:
                opts.allowAggressiveProseCompaction = false
                opts.allowMarkdownAnnotationStripping = false
                opts.stripComments = false
                opts.compactBraces = false
            case .responseFormat, .instructions, .gotcha, .warning:
                opts.allowAggressiveProseCompaction = false
                opts.allowMarkdownAnnotationStripping = false
            default:
                break
            }
        }

        // --- Mode-specific overrides ---
        if processingMode == .readable {
            opts.compactBraces = false
            opts.allowAggressiveProseCompaction = false
            opts.allowCodeCommentStripping = false
            opts.collapseRepeatedSpaces = false
        }

        if processingMode == .codeHeavy {
            opts.preserveIndentation = true
            opts.compactBraces = false
            opts.allowCodeCommentStripping = false
        }

        return opts
    }
}
