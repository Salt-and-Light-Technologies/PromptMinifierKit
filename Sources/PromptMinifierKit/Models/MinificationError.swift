import Foundation

/// Errors thrown by `MinificationEngine` for hard failures.
///
/// Normal edge cases (e.g. unsupported language, conservative YAML) are returned
/// as `MinificationWarning` values inside `MinificationResult`, not thrown here.
public enum MinificationError: Error, LocalizedError, Sendable {
    /// The caller passed an empty string.
    case emptyInput
    /// The validator detected a hard inconsistency in the output.
    case validationFailed(String)
    /// A content type was supplied that this engine cannot handle.
    case unsupportedContentType(ContentType)
    /// An internal consistency check failed (indicates a bug in PromptMinifierKit).
    case internalInconsistentState(String)

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "The input text is empty. Provide at least one character."
        case .validationFailed(let reason):
            return "Minification validation failed: \(reason)"
        case .unsupportedContentType(let type):
            return "Content type '\(type.displayName)' is not supported by this version of PromptMinifierKit."
        case .internalInconsistentState(let detail):
            return "Internal inconsistency detected: \(detail). This is a bug — please report it."
        }
    }
}
