import Foundation

/// The semantic role of a section within a rendered prompt pack.
/// Used to determine how aggressively the section may be minified.
public enum PromptSectionRole: String, Codable, CaseIterable, Sendable, Hashable {
    /// The current task the LLM should perform.
    case task
    /// Non-negotiable hard constraints the LLM must respect.
    case hardConstraints
    /// Operational instructions (how, not what).
    case instructions
    /// The exact output format required.
    case responseFormat
    /// High-level project overview prose.
    case projectOverview
    /// Architectural notes and design decisions.
    case architecture
    /// Context for a specific module or component.
    case moduleContext
    /// Persistent memory entries from previous sessions.
    case memory
    /// Recorded decisions and their rationale.
    case decision
    /// Known pitfalls or tricky implementation details.
    case gotcha
    /// Explicit warnings to the LLM.
    case warning
    /// Open questions that haven't been resolved.
    case unresolvedQuestion
    /// Auto-generated summary of source files.
    case sourceSummary
    /// Worked examples or sample input/output pairs.
    case examples
    /// Raw source code block.
    case code
    /// Section whose role could not be determined.
    case unknown

    /// Human-readable label.
    public var displayName: String {
        switch self {
        case .task:               return "Task"
        case .hardConstraints:    return "Hard Constraints"
        case .instructions:       return "Instructions"
        case .responseFormat:     return "Response Format"
        case .projectOverview:    return "Project Overview"
        case .architecture:       return "Architecture"
        case .moduleContext:      return "Module Context"
        case .memory:             return "Memory"
        case .decision:           return "Decision"
        case .gotcha:             return "Gotcha"
        case .warning:            return "Warning"
        case .unresolvedQuestion: return "Unresolved Question"
        case .sourceSummary:      return "Source Summary"
        case .examples:           return "Examples"
        case .code:               return "Code"
        case .unknown:            return "Unknown"
        }
    }

    /// The default protection level associated with this role.
    public var defaultProtectionLevel: PromptSectionProtectionLevel {
        switch self {
        case .task:               return .locked
        case .hardConstraints:    return .locked
        case .instructions:       return .preserveStructure
        case .responseFormat:     return .preserveStructure
        case .gotcha:             return .preserveStructure
        case .warning:            return .preserveStructure
        case .unresolvedQuestion: return .preserveStructure
        case .examples:           return .preserveStructure
        case .projectOverview:    return .preserveMeaning
        case .architecture:       return .preserveMeaning
        case .moduleContext:      return .preserveMeaning
        case .memory:             return .preserveMeaning
        case .decision:           return .preserveMeaning
        case .sourceSummary:      return .minifiable
        case .code:               return .preserveStructure
        case .unknown:            return .preserveMeaning
        }
    }
}
