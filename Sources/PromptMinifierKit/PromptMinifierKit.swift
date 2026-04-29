/// PromptMinifierKit
///
/// A pure Swift, Foundation-first package for safely minifying LLM prompt packs,
/// Markdown, source code, JSON, YAML, logs, and plain text.
///
/// # Quick start
///
/// ```swift
/// import PromptMinifierKit
///
/// let engine = MinificationEngine()
///
/// // Simple string input
/// let result = try engine.minify(renderedPrompt)
/// print(result.outputText)
/// print(result.stats.estimatedTokenReductionPercent)
///
/// // With explicit options and profile
/// let result = try engine.minify(
///     renderedPrompt,
///     options: .safePromptDefaults,
///     profile: .safePrompt
/// )
///
/// // With caller-declared protected sections
/// let request = MinificationRequest(
///     input: renderedPrompt,
///     options: MinificationOptions(),
///     profile: .safePrompt,
///     protectedSections: [
///         ProtectedPromptSection(
///             title: "Hard Constraints",
///             role: .hardConstraints,
///             protectionLevel: .locked,
///             startMarker: "# Hard Constraints",
///             endMarker: "# Project Context"
///         )
///     ]
/// )
/// let result = try engine.minify(request)
/// ```
///
/// # Pipeline
///
/// 1. `InputNormalizer`      — CRLF→LF, BOM removal, trailing whitespace
/// 2. `ContentClassifier`    — detects JSON / Markdown / YAML / logs / code / prompt pack / mixed
/// 3. `BlockSegmenter`       — splits mixed content into typed blocks
/// 4. Type-specific minifiers — `PlainTextMinifier`, `MarkdownMinifier`, `CodeMinifier`,
///                              `JSONMinifier`, `YAMLMinifier`, `LogsMinifier`, `PromptPackMinifier`
/// 5. `MinificationValidator` — structural integrity checks
/// 6. `TokenEstimator`        — approximate token-count estimation
/// 7. `MinificationEngine`    — assembles `MinificationResult`
///
/// # Package boundaries
///
/// PromptMinifierKit does **not**:
/// - Import SwiftUI or AppKit
/// - Access the clipboard
/// - Call any LLM API
/// - Store API keys
/// - Write files
/// - Make network calls
/// - Depend on RailroadKit, RosettaKit, or ContextComposerKit

@_exported import Foundation
