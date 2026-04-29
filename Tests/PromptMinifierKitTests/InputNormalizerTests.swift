import Testing
@testable import PromptMinifierKit

@Suite("InputNormalizer")
struct InputNormalizerTests {

    let normalizer = InputNormalizer()
    let options = MinificationOptions()

    @Test("CRLF is converted to LF")
    func crlfToLF() {
        let input = "hello\r\nworld\r\n"
        let result = normalizer.normalize(input, options: options)
        #expect(!result.text.contains("\r"))
        #expect(result.text.contains("\n"))
        #expect(result.appliedRules.contains { $0.rule == .normalizedLineEndings })
    }

    @Test("Standalone CR is converted to LF")
    func crToLF() {
        let input = "hello\rworld"
        let result = normalizer.normalize(input, options: options)
        #expect(!result.text.contains("\r"))
        #expect(result.appliedRules.contains { $0.rule == .normalizedLineEndings })
    }

    @Test("UTF-8 BOM is stripped")
    func bomStripped() {
        let input = "\u{FEFF}hello world"
        let result = normalizer.normalize(input, options: options)
        #expect(!result.text.hasPrefix("\u{FEFF}"))
        #expect(result.text == "hello world")
        #expect(result.appliedRules.contains { $0.rule == .strippedBOM })
    }

    @Test("Trailing whitespace is removed when option enabled")
    func trailingWhitespace() {
        var opts = options
        opts.removeTrailingWhitespace = true
        let input = "hello   \nworld  \n"
        let result = normalizer.normalize(input, options: opts)
        let lines = result.text.components(separatedBy: "\n")
        for line in lines {
            #expect(!line.hasSuffix(" "), "Line should not have trailing space: '\(line)'")
        }
        #expect(result.appliedRules.contains { $0.rule == .removedTrailingWhitespace })
    }

    @Test("Clean input produces no applied rules")
    func cleanInput() {
        let input = "hello\nworld\n"
        let result = normalizer.normalize(input, options: options)
        // BOM rule should not fire, CRLF rule should not fire
        #expect(!result.appliedRules.contains { $0.rule == .strippedBOM })
        #expect(!result.appliedRules.contains { $0.rule == .normalizedLineEndings })
    }

    @Test("Empty string is handled without crashing")
    func emptyString() {
        let result = normalizer.normalize("", options: options)
        #expect(result.text.isEmpty)
    }
}
