import Foundation

/// A pre-segmented section of a prompt pack, supplied by ContextComposerKit.
///
/// Using this type allows MinifyAI to skip the `BlockSegmenter` pass and work
/// directly with sections that have already been classified and labelled by the
/// context composer. This is the preferred integration path when sections are
/// already known at call time.
public struct PromptSectionInput: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    /// Display title of this section.
    public let title: String
    /// Raw rendered text of this section (without the heading line itself).
    public let content: String
    /// The semantic role of this section.
    public let role: PromptSectionRole
    /// The protection level to enforce during minification.
    public let protectionLevel: PromptSectionProtectionLevel

    public init(
        id: UUID = UUID(),
        title: String,
        content: String,
        role: PromptSectionRole,
        protectionLevel: PromptSectionProtectionLevel
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.role = role
        self.protectionLevel = protectionLevel
    }
}
