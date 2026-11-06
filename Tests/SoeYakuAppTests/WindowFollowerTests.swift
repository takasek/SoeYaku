import AppKit
import SoeYakuCore
import Testing
@testable import SoeYakuApp

@MainActor struct WindowFollowerTests {
    @Test func viewerSelectionSkipsSharingChromeAndUsesTheFrontDocument() throws {
        let toolbar = windowInfo(1, title: "Window", frame: CGRect(x: 16, y: 56, width: 66, height: 20))
        let document = windowInfo(2, title: "Book.pdf", frame: CGRect(x: 0, y: 40, width: 900, height: 1129))
        let match = try #require(WindowFollower.frontDocumentWindow(in: [toolbar, document], pid: 10, documentName: "Book.pdf"))
        #expect(match.0 == 2)
        #expect(match.1 == CGRect(x: 0, y: 40, width: 900, height: 1129))
        let otherPDF = windowInfo(3, title: "Other.pdf", frame: CGRect(x: 0, y: 40, width: 900, height: 1129))
        #expect(WindowFollower.frontDocumentWindow(in: [toolbar, otherPDF, document], pid: 10, documentName: "Book.pdf") == nil)
        let image = windowInfo(4, title: "Photo.png", frame: CGRect(x: 0, y: 40, width: 900, height: 1129))
        #expect(WindowFollower.frontDocumentWindow(in: [toolbar, image, document], pid: 10, documentName: "Book.pdf") == nil)
    }

    private func windowInfo(_ id: CGWindowID, title: String, frame: CGRect) -> [String: Any] {
        [kCGWindowNumber as String: id, kCGWindowOwnerPID as String: pid_t(10), kCGWindowLayer as String: 0,
         kCGWindowName as String: title, kCGWindowBounds as String: frame.dictionaryRepresentation]
    }

    @Test func thePointerOverTheTranslationPanelDoesNotFollowThePreviewBehindIt() {
        _ = NSApplication.shared
        let translation = SpacePanel(contentRect: CGRect(x: 600, y: 400, width: 300, height: 300),
                                  styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        defer { translation.orderOut(nil) }
        let document = SourceDocument(fingerprint: "f", title: "T", sentences: [])
        let follower = WindowFollower(document: document, excludedWindows: [translation])
        let viewer = CGRect(x: 100, y: 200, width: 1000, height: 800)
        let mouse = CGPoint(x: 700, y: 500)
        translation.orderFrontRegardless()
        #expect(follower.normalizedPointer(mouse: mouse, primaryScreenHeight: 1200, viewerFrame: viewer) == nil)
        #expect(follower.normalizedPointer(mouse: CGPoint(x: 300, y: 500), primaryScreenHeight: 1200, viewerFrame: viewer) == CGPoint(x: 0.2, y: 0.625))
        translation.simulatedActiveSpace = false
        #expect(follower.normalizedPointer(mouse: mouse, primaryScreenHeight: 1200, viewerFrame: viewer) == CGPoint(x: 0.6, y: 0.625))
        translation.simulatedActiveSpace = true
        translation.orderOut(nil)
        #expect(follower.normalizedPointer(mouse: mouse, primaryScreenHeight: 1200, viewerFrame: viewer) == CGPoint(x: 0.6, y: 0.625))
    }
}

@MainActor private final class SpacePanel: NSPanel {
    var simulatedActiveSpace = true
    override var isOnActiveSpace: Bool { simulatedActiveSpace }
}
