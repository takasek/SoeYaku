import Foundation
import Testing

@testable import SoeYakuCLIKit

struct ArgumentsTests {
    @Test func translateAcceptsAModelFileAndRejectsConflictingIdentityOptions() throws {
        #expect(try Command.parse(["translate", "a.pdf", "--port", "8080", "--model-file", "/tmp/a.gguf"])
            == .translate(TranslateOptions(file: "a.pdf", port: 8080, modelFile: "/tmp/a.gguf")))
        #expect(usageMessage(["translate", "a.pdf", "--port", "8080", "--model-file", "a.gguf", "--model", "v1"]) != nil)
    }

    private func usageMessage(_ arguments: [String]) -> String? {
        do {
            _ = try Command.parse(arguments)
            return nil
        } catch let error as UsageError {
            return error.message
        } catch {
            return "other: \(error)"
        }
    }

    @Test func extractTakesOneFile() throws {
        #expect(try Command.parse(["extract", "a.pdf"]) == .extract(file: "a.pdf"))
    }

    @Test func translateWithOnlyTheRequiredPort() throws {
        let command = try Command.parse(["translate", "a.pdf", "--port", "8080"])
        #expect(command == .translate(TranslateOptions(file: "a.pdf", port: 8080)))
        guard case .translate(let options) = command else { return }
        #expect(options.apiKey == nil && options.glossaries.isEmpty && options.memory == nil && options.model == nil)
    }

    @Test func translateReadsEveryOptionAndKeepsGlossaryOrder() throws {
        let command = try Command.parse([
            "translate", "--glossary", "one.txt", "a.pdf", "--port", "9000", "--api-key", "secret",
            "--glossary", "two.txt", "--memory", "m.json", "--model", "x.gguf",
        ])
        #expect(
            command
                == .translate(
                    TranslateOptions(
                        file: "a.pdf", port: 9000, apiKey: "secret", glossaries: ["one.txt", "two.txt"],
                        memory: "m.json", model: "x.gguf")))
    }

    @Test func locateReadsFileImageAndPointerInPixels() throws {
        #expect(
            try Command.parse(["locate", "a.pdf", "shot.png", "--pointer", "120.5,48"])
                == .locate(file: "a.pdf", image: "shot.png", pointer: CGPoint(x: 120.5, y: 48)))
    }

    @Test func missingOrUnknownCommandIsAUsageError() {
        #expect(usageMessage([]) != nil)
        #expect(usageMessage(["frobnicate", "a.pdf"]) != nil)
    }

    @Test func wrongNumberOfFilesIsAUsageError() {
        #expect(usageMessage(["extract"]) != nil)
        #expect(usageMessage(["extract", "a.pdf", "b.pdf"]) != nil)
        #expect(usageMessage(["locate", "a.pdf", "--pointer", "1,2"]) != nil)
    }

    @Test func translateRequiresAValidPort() {
        #expect(usageMessage(["translate", "a.pdf"]) != nil)
        #expect(usageMessage(["translate", "a.pdf", "--port", "eighty"]) != nil)
        #expect(usageMessage(["translate", "a.pdf", "--port", "0"]) != nil)
        #expect(usageMessage(["translate", "a.pdf", "--port", "70000"]) != nil)
    }

    @Test func locateRequiresAValidPointer() {
        #expect(usageMessage(["locate", "a.pdf", "s.png"]) != nil)
        #expect(usageMessage(["locate", "a.pdf", "s.png", "--pointer", "12"]) != nil)
        #expect(usageMessage(["locate", "a.pdf", "s.png", "--pointer", "a,b"]) != nil)
        #expect(usageMessage(["locate", "a.pdf", "s.png", "--pointer", "-1,5"]) != nil)
    }

    @Test func anOptionWithoutAValueOrAnUnknownOptionIsAUsageError() {
        #expect(usageMessage(["translate", "a.pdf", "--port"]) != nil)
        #expect(usageMessage(["extract", "a.pdf", "--port", "1"]) != nil)
        #expect(usageMessage(["translate", "a.pdf", "--port", "1", "--bogus", "x"]) != nil)
    }
}
