import Foundation

/// Named presets that produce ready-to-use `MinificationOptions`.
///
/// Profiles are the recommended way for the MinifyAI app to expose simple choices
/// to the user. Each profile maps to a fully-configured `MinificationOptions` value.
public enum PromptMinificationProfile: String, Codable, CaseIterable, Sendable, Hashable {

    /// Light cleanup — preserve maximum readability.
    case readablePrompt

    /// Default safe profile — conservative, non-destructive.
    case safePrompt

    /// Aggressive profile — maximum compaction (review warnings carefully).
    case aggressivePrompt

    /// Best for prompt packs with heavy source-code content.
    case codeHeavyPrompt

    /// Targeted at standalone JSON documents.
    case jsonOnly

    /// Targeted at standalone Markdown documents.
    case markdownOnly

    /// Targeted at plain prose text.
    case plainTextOnly

    // MARK: - Display

    public var displayName: String {
        switch self {
        case .readablePrompt:   return "Readable Prompt"
        case .safePrompt:       return "Safe Prompt"
        case .aggressivePrompt: return "Aggressive Prompt"
        case .codeHeavyPrompt:  return "Code-Heavy Prompt"
        case .jsonOnly:         return "JSON Only"
        case .markdownOnly:     return "Markdown Only"
        case .plainTextOnly:    return "Plain Text Only"
        }
    }

    public var shortDescription: String {
        switch self {
        case .readablePrompt:
            return "Minimal cleanup. Best when the recipient needs to read the prompt."
        case .safePrompt:
            return "Conservative compaction. Safe for all prompt packs."
        case .aggressivePrompt:
            return "Maximum token savings. Always review warnings before sending."
        case .codeHeavyPrompt:
            return "Preserves code correctness. Ideal for code-heavy packs."
        case .jsonOnly:
            return "Compacts JSON to minimal form."
        case .markdownOnly:
            return "Cleans Markdown whitespace and blank lines."
        case .plainTextOnly:
            return "Trims trailing whitespace and collapses blank lines."
        }
    }

    // MARK: - Options

    /// Returns `MinificationOptions` configured for this profile.
    public var defaultOptions: MinificationOptions {
        switch self {

        case .readablePrompt:
            return MinificationOptions(
                contentType: .auto,
                processingMode: .readable,
                removeTrailingWhitespace: true,
                collapseRepeatedSpaces: false,
                collapseBlankLines: true,
                maxConsecutiveBlankLines: 0,
                stripComments: false,
                compactBraces: false,
                compactJSON: false,
                preserveMarkdownHeadings: true,
                preserveBulletStructure: true,
                preserveNumberedLists: true,
                protectPromptSections: true,
                allowAggressiveProseCompaction: false,
                allowCodeCommentStripping: false,
                allowMarkdownAnnotationStripping: false
            )

        case .safePrompt:
            return MinificationOptions() // safe defaults

        case .aggressivePrompt:
            return MinificationOptions(
                contentType: .auto,
                processingMode: .aggressive,
                removeTrailingWhitespace: true,
                collapseRepeatedSpaces: true,
                collapseBlankLines: true,
                maxConsecutiveBlankLines: 0,
                stripComments: false,          // still opt-in; per-block allowCodeCommentStripping
                compactBraces: true,
                compactJSON: true,
                preserveMarkdownHeadings: true,
                preserveBulletStructure: true,
                preserveNumberedLists: true,
                protectPromptSections: true,
                allowAggressiveProseCompaction: true,
                allowCodeCommentStripping: true,
                allowMarkdownAnnotationStripping: false // always false — too risky
            )

        case .codeHeavyPrompt:
            return MinificationOptions(
                contentType: .auto,
                processingMode: .codeHeavy,
                removeTrailingWhitespace: true,
                collapseRepeatedSpaces: false,
                collapseBlankLines: true,
                maxConsecutiveBlankLines: 0,
                stripComments: false,
                preserveIndentation: true,
                compactBraces: false,
                compactJSON: true,
                preserveMarkdownHeadings: true,
                preserveBulletStructure: true,
                preserveNumberedLists: true,
                preserveFencedCodeLanguageTags: true,
                protectPromptSections: true,
                allowAggressiveProseCompaction: false,
                allowCodeCommentStripping: false
            )

        case .jsonOnly:
            return MinificationOptions(
                contentType: .json,
                processingMode: .safe,
                removeTrailingWhitespace: true,
                collapseRepeatedSpaces: false,
                collapseBlankLines: false,
                compactJSON: true,
                detectMixedContent: false,
                protectPromptSections: false
            )

        case .markdownOnly:
            return MinificationOptions(
                contentType: .markdown,
                processingMode: .safe,
                removeTrailingWhitespace: true,
                collapseRepeatedSpaces: true,
                collapseBlankLines: true,
                maxConsecutiveBlankLines: 0,
                compactJSON: false,
                detectMixedContent: false,
                preserveMarkdownHeadings: true,
                preserveBulletStructure: true,
                preserveNumberedLists: true,
                protectPromptSections: false
            )

        case .plainTextOnly:
            return MinificationOptions(
                contentType: .plainText,
                processingMode: .safe,
                removeTrailingWhitespace: true,
                collapseRepeatedSpaces: true,
                collapseBlankLines: true,
                maxConsecutiveBlankLines: 0,
                compactJSON: false,
                detectMixedContent: false,
                protectPromptSections: false
            )
        }
    }
}
