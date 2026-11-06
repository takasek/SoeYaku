import Foundation
import Testing
@testable import SoeYakuCore

struct HTMLExtractorTests {
    private func extract(_ html: String) throws -> SourceDocument {
        try HTMLExtractor.extract(data: Data(html.utf8), fallbackTitle: "saved-page")
    }

    @Test func readsMainInDOMOrderAndPreservesParagraphsWithoutSiteNavigation() throws {
        let document = try extract("""
            <!doctype html><html><head><title>A reader &amp; a page</title></head><body>
            <header>Site navigation</header><nav>Menu</nav><aside>Related links</aside>
            <main><article><h1>Reading a page</h1><p>The <em>first</em> sentence. The second sentence.</p>
            <h2>Results</h2><p>The final paragraph.</p></article></main><footer>Copyright</footer>
            </body></html>
            """)
        #expect(document.title == "A reader & a page")
        #expect(document.sentences.map(\.text) == ["Reading a page", "The first sentence.", "The second sentence.", "Results", "The final paragraph."])
        #expect(document.sentences.map(\.paragraph) == [0, 1, 1, 2, 3])
        #expect(document.sentences.map(\.id) == Array(0..<5))
        #expect(document.sentences.allSatisfy { $0.page == 0 })
    }

    @Test func fallsBackToArticleThenBodyAndHandlesUnclosedParagraphs() throws {
        let article = try extract("<body><div>Outside</div><article><p>An article paragraph.<p>Another paragraph.</article></body>")
        #expect(article.sentences.map(\.text) == ["An article paragraph.", "Another paragraph."])
        let body = try extract("<body><h1>Notes</h1><p>Rock &amp; roll uses nonbreaking&nbsp;spaces.<p>A \u{FB01}nal paragraph.</body>")
        #expect(body.title == "saved-page")
        #expect(body.sentences.map(\.text) == ["Notes", "Rock & roll uses nonbreaking spaces.", "A final paragraph."])
        #expect(body.sentences.map(\.paragraph) == [0, 1, 2])
    }

    @Test func excludesScriptsTemplatesControlsAndExplicitlyHiddenTextBeforeChoosingMain() throws {
        let document = try extract("""
            <body><main hidden><p>Hidden main.</p></main><main>
            <script>document.write('Do not run this.')</script><style>.x { color:red }</style>
            <template><p>A template.</p></template><noscript>Enable scripts.</noscript>
            <p hidden>Hidden attribute.</p><div aria-hidden="true"><p>ARIA hidden.</p></div>
            <p style="DISPLAY : none !important">Display hidden.</p><p style="visibility: hidden">Invisible.</p>
            <form><input value="Private field"><button>Send</button></form>
            <p>A visible <span hidden>secret</span>sentence.</p>
            </main></body>
            """)
        #expect(document.sentences.map(\.text) == ["A visible sentence."])
    }

    @Test func nestedBlocksListsAndTablesDoNotDuplicateTheirChildren() throws {
        let document = try extract("""
            <main><div><p>Introductory text.</p><section><h2>Checklist</h2>
            <ul><li>First item.</li><li>Second <strong>item</strong>.</li></ul></section></div>
            <table><tr><th>Name</th><th>Value</th></tr><tr><td>Alpha</td><td>Twenty</td></tr></table>
            <pre>let value = 42</pre></main>
            """)
        #expect(document.sentences.map(\.text) == ["Introductory text.", "Checklist", "First item.", "Second item.", "Name Value", "Alpha Twenty", "let value = 42"])
        #expect(document.sentences.map(\.paragraph) == Array(0..<7))
    }

    @Test func keepsDocumentHeaderAndFootnotesInsideTheMainArticle() throws {
        let document = try extract("""
            <body><header>Site links</header><main><article><header><h1>Survey report</h1></header>
            <p>The survey is complete.</p><footer><p>Footnote: measurements use meters.</p></footer>
            </article></main><footer>Site copyright</footer></body>
            """)
        #expect(document.sentences.map(\.text) == ["Survey report", "The survey is complete.", "Footnote: measurements use meters."])
    }

    @Test func identifiesOriginalBytesAndHonorsEncoding() throws {
        let html = "<html><head><meta charset=iso-8859-1><title>Café notes</title></head><body><p>The café is open.</p></body></html>"
        let data = try #require(html.data(using: .isoLatin1))
        let document = try HTMLExtractor.extract(data: data, fallbackTitle: "fallback", textEncodingName: "iso-8859-1")
        #expect(document.title == "Café notes")
        #expect(document.sentences.map(\.text) == ["The café is open."])
        #expect(document.fingerprint == SourceDocument.fingerprint(of: data))
        let metaOnly = try HTMLExtractor.extract(data: data, fallbackTitle: "fallback")
        #expect(metaOnly.sentences == document.sentences)
    }

    @Test func reportsEmptyAndUnsupportedEncodingInsteadOfAFalseDocument() throws {
        #expect(throws: HTMLExtractionError.noText) { try extract("<body><script>Some text.</script></body>") }
        #expect(throws: HTMLExtractionError.unreadable) {
            try HTMLExtractor.extract(data: Data([0xFF, 0x00]), fallbackTitle: "broken", textEncodingName: "unsupported-encoding")
        }
    }

    @Test func honorsXMLDeclarationsAndQuotedMetaCharsetParameters() throws {
        for (charset, encoding, name) in [("Shift_JIS", String.Encoding.shiftJIS, "日本語"), ("windows-1251", .windowsCP1251, "Пример")] {
            for declaration in [
                "<?xml version=\"1.0\" encoding=\"\(charset)\"?>",
                "<meta http-equiv=\"Content-Type\" content=\"text/html; charset='\(charset)'\">"
            ] {
                let html = "\(declaration)<html><head><title>Notes</title></head><body><p>The name is \(name).</p></body></html>"
                let data = try #require(html.data(using: encoding))
                let document = try HTMLExtractor.extract(data: data, fallbackTitle: "notes")
                #expect(document.sentences.map(\.text) == ["The name is \(name)."])
            }
        }
    }

    @Test func latin1AndASCIILabelsUseTheBrowsersWindows1252Mapping() throws {
        for label in ["iso-8859-1", "ascii", "latin1"] {
            var data = Data("<meta charset=\(label)><main><p>The note says ".utf8)
            data.append(0x93)
            data.append(Data("hello".utf8))
            data.append(0x94)
            data.append(Data(".</p></main>".utf8))
            let document = try HTMLExtractor.extract(data: data, fallbackTitle: "notes")
            #expect(document.sentences.map(\.text) == ["The note says “hello”."])
        }
    }
}
