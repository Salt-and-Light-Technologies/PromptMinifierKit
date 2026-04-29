import Foundation

/// Stage 2 of the minification pipeline.
///
/// `ContentClassifier` examines normalised text and returns the most likely
/// `ContentType`, a confidence score (0–1), optional detected language, and a
/// list of reasons that justify the classification.
///
/// When the caller explicitly supplies a non-`.auto` content type in options,
/// the classifier respects that declaration and skips heuristics.
public struct ContentClassifier: Sendable {

    public init() {}

    // MARK: - Public API

    /// Classify `text` given the declared options.
    public func classify(_ text: String, options: MinificationOptions) -> ContentClassificationResult {
        // If the caller pinned a specific type, respect it.
        if options.contentType != .auto {
            let lang: CodeLanguage? = options.contentType == .code ? options.codeLanguage : nil
            return ContentClassificationResult(
                contentType: options.contentType,
                confidence: 1.0,
                detectedLanguage: lang == .unknown ? nil : lang,
                reasons: ["Content type explicitly declared as '\(options.contentType.rawValue)'."],
                warnings: []
            )
        }

        return detectContentType(in: text)
    }

    // MARK: - Detection engine

    private func detectContentType(in text: String) -> ContentClassificationResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ContentClassificationResult(
                contentType: .plainText,
                confidence: 0.5,
                detectedLanguage: nil,
                reasons: ["Input is empty or whitespace-only."],
                warnings: []
            )
        }

        var signals: [(ContentType, Double, String)] = [] // (type, score, reason)

        // --- JSON ---
        if let jsonScore = jsonScore(text) {
            signals.append((.json, jsonScore.score, jsonScore.reason))
        }

        // --- Prompt pack ---
        let ppScore = promptPackScore(text)
        if ppScore.score > 0 {
            signals.append((.promptPack, ppScore.score, ppScore.reason))
        }

        // --- Markdown ---
        let mdScore = markdownScore(text)
        if mdScore.score > 0 {
            signals.append((.markdown, mdScore.score, mdScore.reason))
        }

        // --- YAML ---
        let yamlScore = yamlScore(text)
        if yamlScore.score > 0 {
            signals.append((.yaml, yamlScore.score, yamlScore.reason))
        }

        // --- Logs ---
        let logsScore = logsScore(text)
        if logsScore.score > 0 {
            signals.append((.logs, logsScore.score, logsScore.reason))
        }

        // --- Code ---
        let (codeScore, codeLang) = codeScore(text)
        if codeScore > 0 {
            signals.append((.code, codeScore, "Detected source code structural signals for \(codeLang?.displayName ?? "unknown language")."))
        }

        // Sort by descending score.
        let sorted = signals.sorted { $0.1 > $1.1 }

        if sorted.isEmpty {
            return ContentClassificationResult(
                contentType: .plainText,
                confidence: 0.5,
                detectedLanguage: nil,
                reasons: ["No strong structural signals detected; treating as plain text."],
                warnings: []
            )
        }

        let top = sorted[0]

        // Mixed: if two types both score above 0.4 and are within 0.25 of each other.
        if sorted.count >= 2 {
            let second = sorted[1]
            if second.1 >= 0.4 && (top.1 - second.1) < 0.25 {
                let reasons = sorted.map { "\($0.0.displayName): \(String(format: "%.0f", $0.1 * 100))% – \($0.2)" }
                return ContentClassificationResult(
                    contentType: .mixed,
                    confidence: top.1,
                    detectedLanguage: codeLang,
                    reasons: reasons,
                    warnings: []
                )
            }
        }

        let detectedLang: CodeLanguage? = top.0 == .code ? codeLang : nil
        return ContentClassificationResult(
            contentType: top.0,
            confidence: top.1,
            detectedLanguage: detectedLang,
            reasons: sorted.map { "\($0.0.displayName): \(String(format: "%.0f", $0.1 * 100))% – \($0.2)" },
            warnings: []
        )
    }

    // MARK: - JSON

    private struct ScoreResult { var score: Double; var reason: String }

    private func jsonScore(_ text: String) -> ScoreResult? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
              (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) else {
            return nil
        }
        // Attempt parse.
        if let data = trimmed.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return ScoreResult(score: 0.97, reason: "Successfully parsed as JSON.")
        }
        // Looks like JSON but didn't parse cleanly (JSONC / malformed).
        return ScoreResult(score: 0.60, reason: "Starts and ends with JSON delimiters but did not parse cleanly.")
    }

    // MARK: - Prompt pack

    private func promptPackScore(_ text: String) -> ScoreResult {
        let markers = [
            "# MinifyAI Prompt Pack",
            "# Task",
            "# Current Task",
            "# Hard Constraints",
            "# Constraints",
            "# Instructions",
            "# Required Response Format",
            "# Project Context",
            "<task>",
            "<constraints>",
            "<project_context>",
            "<relevant_modules>"
        ]
        var hits = 0
        for marker in markers {
            if text.contains(marker) { hits += 1 }
        }
        if hits == 0 { return ScoreResult(score: 0, reason: "") }
        let score = min(0.95, 0.50 + Double(hits) * 0.08)
        return ScoreResult(score: score, reason: "Found \(hits) prompt-pack section marker(s).")
    }

    // MARK: - Markdown

    private func markdownScore(_ text: String) -> ScoreResult {
        let lines = text.components(separatedBy: "\n")
        var score = 0.0
        var reasons: [String] = []

        let headingLines = lines.filter { $0.hasPrefix("#") && ($0.count > 1) && $0[$0.index(after: $0.startIndex)] == " " }
        if !headingLines.isEmpty {
            score += 0.30
            reasons.append("Contains \(headingLines.count) Markdown heading(s)")
        }

        let fenceLines = lines.filter { $0.hasPrefix("```") || $0.hasPrefix("~~~") }
        if fenceLines.count >= 2 {
            score += 0.25
            reasons.append("Contains fenced code block markers")
        }

        let bulletLines = lines.filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ")
        }
        if bulletLines.count >= 2 {
            score += 0.15
            reasons.append("Contains bullet list items")
        }

        // Markdown links [text](url)
        if text.range(of: #"\[.+\]\(.+\)"#, options: .regularExpression) != nil {
            score += 0.10
            reasons.append("Contains Markdown links")
        }

        // Tables (pipe-separated)
        let tableLines = lines.filter { $0.contains("|") && $0.trimmingCharacters(in: .whitespaces).hasPrefix("|") }
        if tableLines.count >= 2 {
            score += 0.10
            reasons.append("Contains Markdown table rows")
        }

        // Bold/italic
        if text.contains("**") || text.contains("__") || text.contains("*") {
            score += 0.05
        }

        let capped = min(score, 0.92)
        return ScoreResult(score: capped, reason: reasons.joined(separator: "; "))
    }

    // MARK: - YAML

    private func yamlScore(_ text: String) -> ScoreResult {
        let lines = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return ScoreResult(score: 0, reason: "") }

        var hits = 0
        for line in lines.prefix(30) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // key: value pattern
            if trimmed.range(of: #"^[\w\-]+\s*:(\s|$)"#, options: .regularExpression) != nil {
                hits += 1
            }
            // list items
            if trimmed.hasPrefix("- ") { hits += 1 }
            // YAML document markers
            if trimmed == "---" || trimmed == "..." { hits += 2 }
        }

        if hits < 3 { return ScoreResult(score: 0, reason: "") }

        // Avoid false positive on JSON (JSON won't have --- marker, but double-check)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("{") || trimmed.hasPrefix("[")) {
            return ScoreResult(score: 0, reason: "")
        }

        let score = min(0.80, 0.40 + Double(hits) * 0.04)
        return ScoreResult(score: score, reason: "Detected \(hits) YAML structural signal(s).")
    }

    // MARK: - Logs

    private func logsScore(_ text: String) -> ScoreResult {
        let lines = text.components(separatedBy: "\n").prefix(40)
        var hits = 0

        // Common log patterns.
        let timestampPattern = #"\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}"#
        let levelPattern = #"\b(DEBUG|INFO|WARN|WARNING|ERROR|CRITICAL|FATAL|TRACE)\b"#
        let stackPattern = #"^\s+(at |in |\tat )"#

        for line in lines {
            if line.range(of: timestampPattern, options: .regularExpression) != nil { hits += 2 }
            if line.range(of: levelPattern, options: .regularExpression) != nil { hits += 2 }
            if line.range(of: stackPattern, options: .regularExpression) != nil { hits += 1 }
        }

        if hits < 4 { return ScoreResult(score: 0, reason: "") }
        let score = min(0.88, 0.45 + Double(hits) * 0.02)
        return ScoreResult(score: score, reason: "Detected log-level labels, timestamps, or stack-trace lines.")
    }

    // MARK: - Code

    private func codeScore(_ text: String) -> (Double, CodeLanguage?) {
        // Look for fenced block language hints first.
        if let lang = fenceLanguageHint(in: text) {
            return (0.80, lang)
        }

        // Structural code signals.
        var score = 0.0
        var language: CodeLanguage? = nil

        let lines = text.components(separatedBy: "\n")

        // Function/method declarations.
        if text.range(of: #"\bfunc\s+\w+"#, options: .regularExpression) != nil {
            score += 0.30; language = language ?? .swift
        }
        if text.range(of: #"\bdef\s+\w+"#, options: .regularExpression) != nil {
            score += 0.30; language = language ?? .python
        }
        if text.range(of: #"\bfunction\s+\w+"#, options: .regularExpression) != nil {
            score += 0.25; language = language ?? .javaScript
        }
        if text.range(of: #"\bfn\s+\w+"#, options: .regularExpression) != nil {
            score += 0.25; language = language ?? .rust
        }

        // Import/use statements.
        if text.range(of: #"^import\s+"#, options: [.regularExpression, .anchorsMatchLines]) != nil { score += 0.15 }
        if text.range(of: #"^use\s+"#, options: [.regularExpression, .anchorsMatchLines]) != nil { score += 0.10 }

        // Class/struct/enum.
        if text.range(of: #"\b(class|struct|enum|interface|protocol)\s+\w+"#, options: .regularExpression) != nil { score += 0.20 }

        // Block braces.
        let braceLines = lines.filter { $0.contains("{") || $0.contains("}") }
        if Double(braceLines.count) / Double(max(lines.count, 1)) > 0.10 { score += 0.10 }

        return (min(score, 0.85), language)
    }

    private func fenceLanguageHint(in text: String) -> CodeLanguage? {
        let fencePattern = #"^```(\w+)"#
        let lines = text.components(separatedBy: "\n")
        for line in lines.prefix(5) {
            if let range = line.range(of: fencePattern, options: .regularExpression) {
                let hint = String(line[range]).replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespaces)
                if !hint.isEmpty { return CodeLanguage.from(fenceHint: hint) }
            }
        }
        return nil
    }
}

// MARK: - Result type

public struct ContentClassificationResult: Codable, Sendable {
    public let contentType: ContentType
    /// 0.0 (no confidence) … 1.0 (certain).
    public let confidence: Double
    /// Detected programming language (only set for `.code` blocks).
    public let detectedLanguage: CodeLanguage?
    /// Human-readable justifications for the classification.
    public let reasons: [String]
    /// Any warnings generated during classification.
    public let warnings: [MinificationWarning]

    public init(
        contentType: ContentType,
        confidence: Double,
        detectedLanguage: CodeLanguage?,
        reasons: [String],
        warnings: [MinificationWarning]
    ) {
        self.contentType = contentType
        self.confidence = confidence
        self.detectedLanguage = detectedLanguage
        self.reasons = reasons
        self.warnings = warnings
    }
}
