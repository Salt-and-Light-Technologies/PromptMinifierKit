import Foundation

/// A caller-declared section of a prompt pack that should receive special protection.
///
/// The MinifyAI app (or ContextComposerKit) passes these alongside the rendered
/// prompt text so that PromptMinifierKit can find and honour them without needing
/// to know anything about project structure.
public struct ProtectedPromptSection: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    /// Display title of this section (e.g. "Hard Constraints").
    public let title: String
    /// The semantic role of this section.
    public let role: PromptSectionRole
    /// The protection level to apply.
    public let protectionLevel: PromptSectionProtectionLevel
    /// The string that marks the beginning of this section in the rendered text.
    /// If `nil`, the section is detected by heading heuristics only.
    public let startMarker: String?
    /// The string that marks the end of this section in the rendered text.
    /// If `nil`, the section ends at the next detected section boundary.
    public let endMarker: String?

    public init(
        id: UUID = UUID(),
        title: String,
        role: PromptSectionRole,
        protectionLevel: PromptSectionProtectionLevel,
        startMarker: String? = nil,
        endMarker: String? = nil
    ) {
        self.id = id
        self.title = title
        self.role = role
        self.protectionLevel = protectionLevel
        self.startMarker = startMarker
        self.endMarker = endMarker
    }
}
