import AppKit

/// Installs the responder-chain commands used by native text fields and windows.
@MainActor
final class MainMenuController: NSObject, NSMenuItemValidation {
    private let openSettings: () -> Void
    private let canQuit: () -> Bool

    init(canQuit: @escaping () -> Bool, openSettings: @escaping () -> Void) {
        self.canQuit = canQuit
        self.openSettings = openSettings
        super.init()

        let menu = NSMenu()
        let app = submenu("Palpebra", in: menu)
        app.addItem(
            withTitle: "About Palpebra", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
        app.addItem(.separator())
        let settings = app.addItem(withTitle: "Settings…", action: #selector(settingsTapped), keyEquivalent: ",")
        settings.target = self
        app.addItem(.separator())
        let quit = app.addItem(withTitle: "Quit Palpebra", action: #selector(quitTapped), keyEquivalent: "q")
        quit.target = self

        let edit = submenu("Edit", in: menu)
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let window = submenu("Window", in: menu)
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        NSApp.windowsMenu = window
        NSApp.mainMenu = menu
    }

    private func submenu(_ title: String, in menu: NSMenu) -> NSMenu {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        item.submenu = submenu
        menu.addItem(item)
        return submenu
    }

    @objc private func settingsTapped() { openSettings() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action == #selector(quitTapped) ? canQuit() : true
    }

    @objc private func quitTapped() {
        guard canQuit() else { return }
        NSApp.terminate(nil)
    }
}
