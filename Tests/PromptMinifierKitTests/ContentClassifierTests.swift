import Testing
@testable import PromptMinifierKit

@Suite("ContentClassifier")
struct ContentClassifierTests {

    let classifier = ContentClassifier()

    func opts(type: ContentType = .auto) -> MinificationOptions {
        var o = MinificationOptions()
        o.contentType = type
        return o
    }

    @Test("Detects valid JSON object")
    func detectsJSON() {
        let json = #"{"key": "value", "count": 42}"#
        let result = classifier.classify(json, options: opts())
        #expect(result.contentType == .json)
        #expect(result.confidence > 0.9)
    }

    @Test("Detects valid JSON array")
    func detectsJSONArray() {
        let json = #"[1, 2, 3, "hello"]"#
        let result = classifier.classify(json, options: opts())
        #expect(result.contentType == .json)
    }

    @Test("Detects Markdown with headings")
    func detectsMarkdownHeadings() {
        let md = """
        # My Document
        ## Section One
        Some prose here.
        - bullet one
        - bullet two
        """
        let result = classifier.classify(md, options: opts())
        #expect(result.contentType == .markdown || result.contentType == .promptPack)
        #expect(result.confidence > 0.3)
    }

    @Test("Detects Markdown with fenced code")
    func detectsMarkdownFenced() {
        let md = """
        Here is some code:
        ```swift
        let x = 1
        ```
        And more prose.
        """
        let result = classifier.classify(md, options: opts())
        #expect(result.contentType == .markdown)
    }

    @Test("Detects prompt pack")
    func detectsPromptPack() {
        let pack = """
        # Task
        Write a Swift function.

        # Hard Constraints
        - Must compile.
        - No force unwraps.

        # Project Context
        This is a Swift package.
        """
        let result = classifier.classify(pack, options: opts())
        #expect(result.contentType == .promptPack)
    }

    @Test("Detects log content")
    func detectsLogs() {
        let logs = """
        2024-01-15T10:23:45 INFO Server started on port 8080
        2024-01-15T10:23:46 ERROR Failed to connect to database
        2024-01-15T10:23:46 DEBUG Connection timeout after 30s
            at com.example.App.connect(App.java:42)
        """
        let result = classifier.classify(logs, options: opts())
        #expect(result.contentType == .logs)
    }

    @Test("Explicit content type is respected")
    func explicitType() {
        let text = "just some text"
        let result = classifier.classify(text, options: opts(type: .yaml))
        #expect(result.contentType == .yaml)
        #expect(result.confidence == 1.0)
    }

    @Test("Empty input classifies as plain text")
    func emptyInput() {
        let result = classifier.classify("", options: opts())
        #expect(result.contentType == .plainText)
    }

    @Test("Returns reasons array")
    func returnsReasons() {
        let json = #"{"a": 1}"#
        let result = classifier.classify(json, options: opts())
        #expect(!result.reasons.isEmpty)
    }
}
