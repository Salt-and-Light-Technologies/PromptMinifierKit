import Foundation

/// How serious a warning is.
public enum WarningSeverity: String, Codable, CaseIterable, Sendable, Hashable, Comparable {
    /// Purely informational — no action required.
    case info
    /// Worth noting — the output is safe but the user should be aware.
    case caution
    /// Real risk — the transformation may have changed meaning or correctness.
    case risk
    /// A transformation was blocked or failed.
    case error

    private var order: Int {
        switch self {
        case .info:    return 0
        case .caution: return 1
        case .risk:    return 2
        case .error:   return 3
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.order < rhs.order
    }
}

/// Categories of warning that PromptMinifierKit can emit.
public enum MinificationWarningKind: String, Codable, CaseIterable, Sendable, Hashable {
    case approximateTokenEstimate
    case outputLargerThanInput
    case outputEmpty
    case unsupportedLanguage
    case commentStrippingSkipped
    case commentStrippingRisk
    case unclosedCodeFence
    case invalidJSON
    case jsonKeyOrderMayChange
    case yamlMinificationConservative
    case logsMinificationConservative
    case protectedSectionPreserved
    case lockedSectionNotModified
    case aggressiveModeRisk
    case shellCommentStrippingSkipped
    case indentationPreserved
    case validationFailed

    /// Human-readable label.
    public var displayName: String {
        switch self {
        case .approximateTokenEstimate:      return "Approximate Token Estimate"
        case .outputLargerThanInput:         return "Output Larger Than Input"
        case .outputEmpty:                   return "Output Is Empty"
        case .unsupportedLanguage:           return "Unsupported Language"
        case .commentStrippingSkipped:       return "Comment Stripping Skipped"
        case .commentStrippingRisk:          return "Comment Stripping Risk"
        case .unclosedCodeFence:             return "Unclosed Code Fence"
        case .invalidJSON:                   return "Invalid JSON"
        case .jsonKeyOrderMayChange:         return "JSON Key Order May Change"
        case .yamlMinificationConservative:  return "YAML Minification Is Conservative"
        case .logsMinificationConservative:  return "Logs Minification Is Conservative"
        case .protectedSectionPreserved:     return "Protected Section Preserved"
        case .lockedSectionNotModified:      return "Locked Section Not Modified"
        case .aggressiveModeRisk:            return "Aggressive Mode Risk"
        case .shellCommentStrippingSkipped:  return "Shell Comment Stripping Skipped"
        case .indentationPreserved:          return "Indentation Preserved"
        case .validationFailed:              return "Validation Failed"
        }
    }
}

/// A warning produced during minification.
///
/// Warnings appear in `MinificationResult.warnings` and in per-block results.
/// They should be surfaced to the user in the MinifyAI review screen before
/// the prompt is copied or sent.
public struct MinificationWarning: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    /// Category of the warning.
    public let kind: MinificationWarningKind
    /// A human-readable explanation.
    public let message: String
    /// How serious this warning is.
    public let severity: WarningSeverity
    /// The content type this warning relates to, if known.
    public let contentType: ContentType?
    /// The programming language, if relevant.
    public let language: CodeLanguage?
    /// The prompt-section role, if relevant.
    public let sectionRole: PromptSectionRole?

    public init(
        id: UUID = UUID(),
        kind: MinificationWarningKind,
        message: String,
        severity: WarningSeverity,
        contentType: ContentType? = nil,
        language: CodeLanguage? = nil,
        sectionRole: PromptSectionRole? = nil
    ) {
        self.id = id
        self.kind = kind
        self.message = message
        self.severity = severity
        self.contentType = contentType
        self.language = language
        self.sectionRole = sectionRole
    }
}
