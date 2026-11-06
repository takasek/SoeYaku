import Foundation
import SoeYakuTestSupport
import Testing
@testable import SoeYakuCore

struct SourceDocumentLoaderTests {
    @Test func dispatchesLocalPDFAndHTMLWithoutNetworking() async throws {
        let pdf = try MainFixture.write(rightColumnFirst: true)
        defer { try? FileManager.default.removeItem(at: pdf.deletingLastPathComponent()) }
        let html = pdf.deletingLastPathComponent().appendingPathComponent("notes.HTML")
        try Data("<html><title>Notes</title><main><p>A saved HTML document.</p></main></html>".utf8).write(to: html)
        #expect(try SourceDocumentLoader.extractFile(pdf) == PDFExtractor.extract(url: pdf))
        let loaded = try await SourceDocumentLoader.load(html, fetch: { _ in throw UnexpectedFetch() })
        #expect(loaded.title == "Notes")
        #expect(loaded.sentences.map(\.text) == ["A saved HTML document."])
        #expect(try SourceDocumentLoader.format(of: html) == .html)
        #expect(try SourceDocumentLoader.format(of: pdf) == .pdf)
    }

    @Test func acceptsHTMLResponseAndUsesItsEncoding() async throws {
        let url = URL(string: "https://example.com/article#results")!
        let html = "<html><title>Café</title><main><p>The café is open.</p></main></html>"
        let data = try #require(html.data(using: .isoLatin1))
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type":"text/html; charset=iso-8859-1"])!
        let document = try await SourceDocumentLoader.load(url, fetch: { requested in
            #expect(requested == url)
            return (data, response)
        })
        #expect(document.title == "Café")
        #expect(document.sentences.map(\.text) == ["The café is open."])
    }

    @Test func rejectsHTTPFailureNonHTMLAndOversizedData() async throws {
        let url = URL(string: "https://example.com/notes")!
        let body = Data("<main><p>Some text.</p></main>".utf8)
        let unavailable = HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: ["Content-Type":"text/html"])!
        await #expect(throws: DocumentLoadError.httpStatus(403)) {
            try await SourceDocumentLoader.load(url, fetch: { _ in (body, unavailable) })
        }
        let notHTML = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
        await #expect(throws: DocumentLoadError.notHTML) {
            try await SourceDocumentLoader.load(url, fetch: { _ in (body, notHTML) })
        }
        let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"text/html"])!
        let oversized = Data(repeating: 32, count: SourceDocumentLoader.maximumHTMLBytes + 1)
        await #expect(throws: DocumentLoadError.tooLarge) {
            try await SourceDocumentLoader.load(url, fetch: { _ in (oversized, ok) })
        }
    }

    @Test func rejectsUnsupportedSourcesBeforeFetching() async throws {
        for value in ["ftp://example.com/a", "https://user:password@example.com/a", "javascript:alert(1)"] {
            let url = URL(string: value)!
            await #expect(throws: DocumentLoadError.unsupportedSource) {
                try await SourceDocumentLoader.load(url, fetch: { _ in throw UnexpectedFetch() })
            }
        }
        #expect(throws: DocumentLoadError.unsupportedSource) {
            try SourceDocumentLoader.extractFile(URL(filePath: "/tmp/not-a-document.png"))
        }
    }
}

private struct UnexpectedFetch: Error {}
