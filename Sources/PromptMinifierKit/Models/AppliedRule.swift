import Foundation

/// A specific transformation that was applied to content during minification.
public enum AppliedRuleKind: String, Codable, CaseIterable, Sendable, Hashable {
    case normalizedLineEndings
    case strippedBOM
    case removedTrailingWhitespace
    case collapsedRepeatedSpaces
    case collapsedBlankLines
    case strippedComments
    case compactedJSON
    case preservedProtectedSection
    case preservedIndentationSensitiveLanguage
    case compactedBraces
    case segmentedMixedContent
    case minifiedFencedCodeBlock
    case conservativeYAML
    case conservativeLogs

    /// Human-readable description of this rule.
    public var displayName: String {
        switch self {
        case .normalizedLineEndings:              return "Normalised Line Endings"
        case .strippedBOM:                        return "Stripped UTF-8 BOM"
        case .removedTrailingWhitespace:          return "Removed Trailing Whitespace"
        case .collapsedRepeatedSpaces:            return "Collapsed Repeated Spaces"
        case .collapsedBlankLines:                return "Collapsed Blank Lines"
        case .strippedComments:                   return "Stripped Comments"
        case .compactedJSON:                      return "Compacted JSON"
        case .preservedProtectedSection:          return "Preserved Protected Section"
        case .preservedIndentationSensitiveLanguage: return "Preserved Indentation (Sensitive Language)"
        case .compactedBraces:                    return "Compacted Brace Style"
        case .segmentedMixedContent:              return "Segmented Mixed Content"
        case .minifiedFencedCodeBlock:            return "Minified Fenced Code Block"
        case .conservativeYAML:                   return "Conservative YAML Minification"
        case .conservativeLogs:                   return "Conservative Logs Minification"
        }
    }
}

/// Records a single transformation applied to a block of content.
public struct AppliedRule: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    /// The kind of transformation that was applied.
    public let rule: AppliedRuleKind
    /// A human-readable explanation shown in the UI.
    public let description: String
    /// The content type this rule was applied to, if known.
    public let contentType: ContentType?
    /// The programming language, if relevant.
    public let language: CodeLanguage?
    /// The prompt-section role, if relevant.
    public let sectionRole: PromptSectionRole?

    public init(
        id: UUID = UUID(),
        rule: AppliedRuleKind,
        description: String,
        contentType: ContentType? = nil,
        language: CodeLanguage? = nil,
        sectionRole: PromptSectionRole? = nil
    ) {
        self.id = id
        self.rule = rule
        self.description = description
        self.contentType = contentType
        self.language = language
        self.sectionRole = sectionRole
    }
}
