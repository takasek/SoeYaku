import AppKit
import SoeYakuCore
import SoeYakuVision
import SwiftUI

@main @MainActor struct SoeYakuApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let reader = Reader()
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let root = NSMenuItem()
        root.submenu = NSMenu()
        menu.addItem(root)
        root.submenu?.addItem(withTitle: "SoeYaku を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let file = NSMenuItem()
        file.submenu = NSMenu(title: "ファイル")
        menu.addItem(file)
        file.submenu?.addItem(withTitle: "PDF・HTML を開く…", action: #selector(openDocument), keyEquivalent: "o").target = self
        file.submenu?.addItem(withTitle: "URL を開く…", action: #selector(openURL), keyEquivalent: "u").target = self
        let edit = NSMenuItem()
        edit.submenu = Self.makeEditMenu()
        menu.addItem(edit)
        let windows = NSMenuItem()
        let windowsMenu = NSMenu(title: "ウインドウ")
        windows.submenu = windowsMenu
        windowsMenu.addItem(withTitle: "操作ウインドウ", action: #selector(showControls), keyEquivalent: "1").target = self
        windowsMenu.addItem(withTitle: "訳文ウインドウ", action: #selector(showTranslation), keyEquivalent: "2").target = self
        windowsMenu.addItem(.separator())
        windowsMenu.addItem(withTitle: "しまう", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowsMenu.addItem(withTitle: "すべてを手前に移動", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        menu.addItem(windows)
        NSApp.windowsMenu = windowsMenu
        NSApp.mainMenu = menu

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 560),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "SoeYaku"
        window.contentView = NSHostingView(rootView: ControlView(reader: reader))
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("SoeYakuControls")
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        // Vision loads its text recognition model on first use, which takes tens of seconds. Load it before following starts.
        Task.detached(priority: .utility) { await TextRecognizer.warmUp() }
        if let path = CommandLine.arguments.dropFirst().first(where: { ["pdf", "html", "htm", "xhtml"].contains(($0 as NSString).pathExtension.lowercased()) }) {
            reader.open(URL(filePath: path))
        }
    }

    static func makeEditMenu() -> NSMenu {
        let menu = NSMenu(title: "編集")
        for (title, action, key) in [("コピー", "copy:", "c"), ("すべてを選択", "selectAll:", "a")] {
            menu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        return menu
    }

    @objc private func openDocument() { reader.chooseDocument() }
    @objc private func openURL() { reader.chooseURL() }
    @objc private func showControls() { window.makeKeyAndOrderFront(nil) }
    @objc private func showTranslation() { reader.showPanel() }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let source = urls.first(where: { (try? SourceDocumentLoader.format(of: $0)) != nil }) { reader.open(source) }
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) == window { NSApp.terminate(nil) }
    }

    func applicationWillTerminate(_ notification: Notification) { reader.shutdown() }
}
