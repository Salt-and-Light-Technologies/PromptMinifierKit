import Foundation

/// A fully specified minification request.
///
/// Prefer this type over the convenience string-based overloads when you need
/// to provide protected section hints or non-default options.
public struct MinificationRequest: Codable, Sendable, Hashable {
    public let id: UUID
    /// The raw rendered text to minify.
    public let input: String
    /// Options controlling minification behaviour.
    public let options: MinificationOptions
    /// The named profile that produced (or informed) these options.
    public let profile: PromptMinificationProfile
    /// Caller-declared sections that must receive special protection.
    public let protectedSections: [ProtectedPromptSection]
    /// When this request was created.
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        input: String,
        options: MinificationOptions = MinificationOptions(),
        profile: PromptMinificationProfile = .safePrompt,
        protectedSections: [ProtectedPromptSection] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.input = input
        self.options = options
        self.profile = profile
        self.protectedSections = protectedSections
        self.createdAt = createdAt
    }
}
