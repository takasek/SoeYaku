import AppKit
import Testing
@testable import SoeYakuApp

@MainActor struct ViewerTests {
    @Test func previewIsAppleSPreviewAndBrowserIsTheChosenOne() {
        #expect(Viewer.preview(documentName: "Book.pdf").bundleID == "com.apple.Preview")
        #expect(Viewer.preview(documentName: nil).name == "プレビュー")
        #expect(Viewer.browser(bundleID: "com.google.Chrome", titles: []).bundleID == "com.google.Chrome")
        #expect(Viewer.browser(bundleID: "com.google.Chrome", titles: []).name == "ブラウザ")
    }

    @Test func previewMatchesTheDocumentWindowAndBrowserMatchesThePageTitle() {
        let pdf = windowInfo(1, title: "Reading.pdf")
        let page = windowInfo(2, title: "Reading – Google Chrome")
        #expect(Viewer.preview(documentName: "Reading.pdf").frontWindow(in: [pdf], pid: 10)?.0 == 1)
        #expect(Viewer.preview(documentName: "Reading.pdf").frontWindow(in: [page, pdf], pid: 10)?.0 == 1)
        #expect(Viewer.browser(bundleID: "com.google.Chrome", titles: ["Reading"]).frontWindow(in: [page], pid: 10)?.0 == 2)
        #expect(Viewer.browser(bundleID: "com.google.Chrome", titles: ["Reading"]).frontWindow(in: [pdf, page], pid: 10) == nil)
    }

    private func windowInfo(_ id: CGWindowID, title: String) -> [String: Any] {
        [kCGWindowNumber as String: id, kCGWindowOwnerPID as String: pid_t(10), kCGWindowLayer as String: 0,
         kCGWindowName as String: title, kCGWindowBounds as String: CGRect(x: 0, y: 40, width: 900, height: 1000).dictionaryRepresentation]
    }
}
