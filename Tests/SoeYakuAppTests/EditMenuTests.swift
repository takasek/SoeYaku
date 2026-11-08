import AppKit
import Testing
@testable import SoeYakuApp

@Suite(.serialized) @MainActor struct EditMenuTests {
    @Test func commandVPastesIntoTheTextEditor() throws {
        _ = NSApplication.shared
        let menu = AppDelegate.makeEditMenu()
        let editor = PasteReceiver()
        // AppKit normally resolves the nil target through the active field editor.
        // Bind a text editor directly so this shortcut test needs no key window or clipboard.
        for item in menu.items {
            #expect(item.target == nil)
            item.target = editor
        }
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "v", charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9))

        #expect(menu.performKeyEquivalent(with: event))
        #expect(editor.pasteCount == 1)
    }
}

@MainActor private final class PasteReceiver: NSTextView {
    var pasteCount = 0
    override func paste(_ sender: Any?) { pasteCount += 1 }
}
