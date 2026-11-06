import Foundation
import Testing
@testable import SoeYakuCore

struct DocumentTests {
    @Test func fingerprintIsLowercaseSHA256OfFileBytes() {
        #expect(SourceDocument.fingerprint(of: Data("abc".utf8))
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func documentRoundTripsThroughJSON() throws {
        let document = SourceDocument(fingerprint: "f", title: "T", sentences: [
            Sentence(id: 0, paragraph: 0, page: 0, text: "One."),
            Sentence(id: 1, paragraph: 1, page: 2, text: "Two.")
        ])
        let data = try JSONEncoder().encode(document)
        #expect(try JSONDecoder().decode(SourceDocument.self, from: data) == document)
    }
}
