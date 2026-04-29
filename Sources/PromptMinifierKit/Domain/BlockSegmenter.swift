import Foundation

/// Stage 3 of the minification pipeline.
///
/// `BlockSegmenter` walks normalised text line-by-line and splits it into an
/// ordered array of `ContentBlock` values. Each block has a detected type,
/// optional language, line-range hint, and (for prompt-pack content) a section
/// role and protection level.
///
/// The segmenter preserves order and is deterministic — the same input always
/// produces the same sequence of blocks.
public struct BlockSegmenter: Sendable {

    public init() {}

    // MARK: - Public API

    /// Segment `text` into typed `ContentBlock` values.
    ///
    /// - Parameters:
    ///   - text: Normalised input (LF line endings, no BOM).
    ///   - classification: The document-level classification result.
    ///   - options: The active minification options.
    ///   - protectedSections: Caller-declared protected sections.
    /// - Returns: Ordered blocks and any warnings generated during segmentation.
    public func segment(
        _ text: String,
        classification: ContentClassificationResult,
        options: MinificationOptions,
        protectedSections: [ProtectedPromptSection] = []
    ) -> SegmentationResult {

        let docType = classification.contentType

        // For homogeneous types, wrap the whole document in a single block.
        switch docType {
        case .json:
            return single(text: text, type: .json, language: nil,
                          role: nil, protection: .minifiable)
        case .yaml:
            return single(text: text, type: .yaml, language: nil,
                          role: nil, protection: .minifiable)
        case .logs:
            return single(text: text, type: .logs, language: nil,
                          role: nil, protection: .minifiable)
        case .code:
            let lang = classification.detectedLanguage
            let protection: PromptSectionProtectionLevel = lang?.isIndentationSensitive == true
                ? .preserveStructure : .minifiable
            return single(text: text, type: .code, language: lang,
                          role: .code, protection: protection)
        case .plainText:
            return single(text: text, type: .plainText, language: nil,
                          role: nil, protection: .minifiable)
        case .promptPack:
            return segmentPromptPack(text, protectedSections: protectedSections)
        case .markdown, .mixed, .auto:
            return segmentMarkdownOrMixed(text, docType: docType,
                                          protectedSections: protectedSections)
        }
    }

    // MARK: - Prompt Pack Segmenter

    private func segmentPromptPack(
        _ text: String,
        protectedSections: [ProtectedPromptSection]
    ) -> SegmentationResult {

        var blocks: [ContentBlock] = []
        var warnings: [MinificationWarning] = []

        let lines = text.components(separatedBy: "\n")
        var currentSectionLines: [String] = []
        var currentRole: PromptSectionRole = .unknown
        var currentProtection: PromptSectionProtectionLevel = .preserveMeaning
        var currentStartLine = 0
        var lineIndex = 0

        func flushSection() {
            guard !currentSectionLines.isEmpty else { return }
            let sectionText = currentSectionLines.joined(separator: "\n")
            let hint = RangeHint(startLine: currentStartLine, endLine: lineIndex - 1)
            blocks.append(ContentBlock(
                type: .promptPack,
                text: sectionText,
                language: nil,
                rangeHint: hint,
                role: currentRole,
                protectionLevel: currentProtection
            ))
        }

        for (idx, line) in lines.enumerated() {
            lineIndex = idx

            // Check if line starts a new section heading.
            if let (role, protection) = sectionRole(
                for: line,
                protectedSections: protectedSections
            ) {
                flushSection()
                currentSectionLines = [line]
                currentRole = role
                currentProtection = protection
                currentStartLine = idx
            } else {
                currentSectionLines.append(line)
            }
        }

        lineIndex = lines.count
        flushSection()

        if blocks.isEmpty {
            // Fall back to a single block.
            blocks.append(ContentBlock(
                type: .promptPack,
                text: text,
                language: nil,
                rangeHint: RangeHint(startLine: 0, endLine: lines.count - 1),
                role: .unknown,
                protectionLevel: .preserveMeaning
            ))
        }

        return SegmentationResult(blocks: blocks, warnings: warnings)
    }

    // MARK: - Markdown / Mixed Segmenter

    private func segmentMarkdownOrMixed(
        _ text: String,
        docType: ContentType,
        protectedSections: [ProtectedPromptSection]
    ) -> SegmentationResult {

        var blocks: [ContentBlock] = []
        var warnings: [MinificationWarning] = []
        let lines = text.components(separatedBy: "\n")

        var pendingLines: [String] = []
        var pendingStartLine = 0
        var inFence = false
        var fenceMarker = ""
        var fenceLanguage: CodeLanguage? = nil
        var fenceLines: [String] = []
        var fenceStartLine = 0

        func flushPending(upToLine endLine: Int) {
            guard !pendingLines.isEmpty else { return }
            let joined = pendingLines.joined(separator: "\n")
            let hint = RangeHint(startLine: pendingStartLine, endLine: endLine)
            // Sub-classify the pending block.
            let type: ContentType = docType == .mixed ? subClassify(joined) : .markdown
            let protection: PromptSectionProtectionLevel = .preserveStructure
            blocks.append(ContentBlock(
                type: type,
                text: joined,
                language: nil,
                rangeHint: hint,
                role: nil,
                protectionLevel: protection
            ))
            pendingLines = []
        }

        for (idx, line) in lines.enumerated() {
            if !inFence {
                // Detect fence open.
                if line.hasPrefix("```") || line.hasPrefix("~~~") {
                    let marker = line.hasPrefix("```") ? "```" : "~~~"
                    let hintStr = String(line.dropFirst(marker.count))
                        .trimmingCharacters(in: .whitespaces)
                    fenceMarker = marker
                    fenceLanguage = hintStr.isEmpty ? nil : CodeLanguage.from(fenceHint: hintStr)
                    inFence = true
                    fenceLines = [line]
                    fenceStartLine = idx
                    // Flush any accumulated prose first.
                    flushPending(upToLine: idx - 1)
                } else {
                    if pendingLines.isEmpty { pendingStartLine = idx }
                    pendingLines.append(line)
                }
            } else {
                fenceLines.append(line)
                // Detect fence close (same marker prefix, nothing else significant on the line).
                let stripped = line.trimmingCharacters(in: .whitespaces)
                if stripped == fenceMarker || stripped.hasPrefix(fenceMarker) && stripped.dropFirst(fenceMarker.count).allSatisfy({ $0 == " " }) {
                    // Close the fence block.
                    let fenceText = fenceLines.joined(separator: "\n")
                    let hint = RangeHint(startLine: fenceStartLine, endLine: idx)
                    let protection: PromptSectionProtectionLevel = fenceLanguage?.isIndentationSensitive == true
                        ? .preserveStructure : .minifiable
                    blocks.append(ContentBlock(
                        type: .code,
                        text: fenceText,
                        language: fenceLanguage,
                        rangeHint: hint,
                        role: .code,
                        protectionLevel: protection
                    ))
                    inFence = false
                    fenceLines = []
                    fenceLanguage = nil
                    fenceMarker = ""
                    pendingStartLine = idx + 1
                }
            }
        }

        // If we're still inside a fence at EOF, emit warning and treat as code block.
        if inFence {
            warnings.append(MinificationWarning(
                kind: .unclosedCodeFence,
                message: "Unclosed fenced code block starting at line \(fenceStartLine). Preserving block content unchanged.",
                severity: .caution,
                contentType: .code,
                language: fenceLanguage
            ))
            let fenceText = fenceLines.joined(separator: "\n")
            blocks.append(ContentBlock(
                type: .code,
                text: fenceText,
                language: fenceLanguage,
                rangeHint: RangeHint(startLine: fenceStartLine, endLine: lines.count - 1),
                role: .code,
                protectionLevel: .preserveStructure
            ))
        } else {
            flushPending(upToLine: lines.count - 1)
        }

        if blocks.isEmpty {
            return single(text: text, type: docType == .mixed ? .mixed : .markdown,
                          language: nil, role: nil, protection: .preserveStructure)
        }

        return SegmentationResult(blocks: blocks, warnings: warnings)
    }

    // MARK: - Helpers

    private func single(
        text: String,
        type: ContentType,
        language: CodeLanguage?,
        role: PromptSectionRole?,
        protection: PromptSectionProtectionLevel
    ) -> SegmentationResult {
        let lines = text.components(separatedBy: "\n")
        let block = ContentBlock(
            type: type,
            text: text,
            language: language,
            rangeHint: RangeHint(startLine: 0, endLine: max(0, lines.count - 1)),
            role: role,
            protectionLevel: protection
        )
        return SegmentationResult(blocks: [block], warnings: [])
    }

    /// Detects the section role and protection level for a prompt-pack heading line.
    private func sectionRole(
        for line: String,
        protectedSections: [ProtectedPromptSection]
    ) -> (PromptSectionRole, PromptSectionProtectionLevel)? {

        // Check caller-declared protected sections first.
        for ps in protectedSections {
            if let marker = ps.startMarker, line.hasPrefix(marker) {
                return (ps.role, ps.protectionLevel)
            }
        }

        // Markdown heading heuristics.
        guard line.hasPrefix("#") else {
            // XML-like tags.
            return xmlSectionRole(for: line)
        }

        let heading = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces).lowercased()

        switch heading {
        case "task", "current task":
            return (.task, .locked)
        case "hard constraints", "constraints":
            return (.hardConstraints, .locked)
        case "instructions":
            return (.instructions, .preserveStructure)
        case "required response format", "response format", "output format":
            return (.responseFormat, .preserveStructure)
        case "project context", "project overview":
            return (.projectOverview, .preserveMeaning)
        case "architecture":
            return (.architecture, .preserveMeaning)
        case "relevant modules", "module context":
            return (.moduleContext, .preserveMeaning)
        case "memory":
            return (.memory, .preserveMeaning)
        case "decisions", "decision":
            return (.decision, .preserveMeaning)
        case "gotchas", "gotcha":
            return (.gotcha, .preserveStructure)
        case "warnings", "warning":
            return (.warning, .preserveStructure)
        case "unresolved questions", "unresolved question":
            return (.unresolvedQuestion, .preserveStructure)
        case "source summary":
            return (.sourceSummary, .minifiable)
        case "examples":
            return (.examples, .preserveStructure)
        default:
            if heading.hasPrefix("#") { return nil }
            // Any other heading — treat as unknown, preserve meaning.
            return heading.isEmpty ? nil : (.unknown, .preserveMeaning)
        }
    }

    private func xmlSectionRole(for line: String) -> (PromptSectionRole, PromptSectionProtectionLevel)? {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t == "<task>" { return (.task, .locked) }
        if t == "<constraints>" { return (.hardConstraints, .locked) }
        if t == "<instructions>" { return (.instructions, .preserveStructure) }
        if t == "<project_context>" { return (.projectOverview, .preserveMeaning) }
        if t == "<relevant_modules>" { return (.moduleContext, .preserveMeaning) }
        if t == "<memory>" { return (.memory, .preserveMeaning) }
        if t == "<decisions>" { return (.decision, .preserveMeaning) }
        if t == "<gotchas>" { return (.gotcha, .preserveStructure) }
        if t == "<response_format>" { return (.responseFormat, .preserveStructure) }
        return nil
    }

    /// Heuristic sub-classifier for mixed-content prose blocks.
    private func subClassify(_ text: String) -> ContentType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
           (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")),
           let data = trimmed.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return .json
        }
        return .markdown
    }
}

// MARK: - Result type

public struct SegmentationResult: Sendable {
    public let blocks: [ContentBlock]
    public let warnings: [MinificationWarning]
}
