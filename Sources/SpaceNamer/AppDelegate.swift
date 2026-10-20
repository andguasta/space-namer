import AppKit
import ApplicationServices
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var manager: SpaceManager!
    private var labels: DesktopLabels!
    private var statusBar: StatusBarController!
    private var switcher: SwitcherController!
    private var hud: SpaceHUD!
    private var wallpapers: SpaceWallpapers!
    private var settings: SettingsWindow!
    private var hotKeys: [HotKey] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        manager = SpaceManager()
        labels = DesktopLabels(manager: manager)
        switcher = SwitcherController(manager: manager)
        statusBar = StatusBarController(manager: manager, labels: labels)
        hud = SpaceHUD(manager: manager)
        wallpapers = SpaceWallpapers(manager: manager)
        settings = SettingsWindow { [weak self] in self?.hud.showCurrent() }
        statusBar.onShowSettings = { [weak self] in self?.settings.show() }

        switcher.onSwitch = { [weak self] in self?.go(to: $0) }
        statusBar.onSwitch = { [weak self] in self?.go(to: $0) }
        statusBar.onShowSwitcher = { [weak self] mode in self?.switcher.show(mode) }
        statusBar.onSetUpShortcuts = { [weak self] in self?.setUpShortcuts() }
        statusBar.onMoveWindow = { [weak self] in self?.move($0, to: $1) }
        switcher.onMoveWindow = { [weak self] in self?.move($0, to: $1) }

        let mods = controlKey | optionKey
        hotKeys = [
            HotKey(keyCode: kVK_Space, modifiers: mods) { [weak self] in
                guard let self else { return }
                self.switcher.isVisible ? self.switcher.hide() : self.switcher.show()
            },
            HotKey(keyCode: kVK_ANSI_R, modifiers: mods) { [weak self] in self?.switcher.show(.renameCurrent) },
            HotKey(keyCode: kVK_ANSI_E, modifiers: mods) { [weak self] in self?.switcher.show(.emojiForCurrent) },
            HotKey(keyCode: kVK_Space, modifiers: mods | cmdKey) { [weak self] in
                guard let self else { return }
                self.switcher.isVisible ? self.switcher.hide() : self.switcher.show(.moveWindow)
            },
        ]

        if !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }
    }

    private func go(to space: Space) {
        let error = SpaceSwitcher.go(to: space, manager: manager)
        if error == nil, !space.isCurrent { hud.announce(space) }
        report(error) { self.go(to: space) }
    }

    private func move(_ window: WindowMover.Target, to space: Space) {
        report(WindowMover.move(window, to: space, manager: manager)) { self.move(window, to: space) }
    }

    /// Explains a failed switch; `retry` runs after the shortcuts have been set up.
    private func report(_ error: SwitchError?, retry: @escaping () -> Void) {
        guard let error else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        switch error {
        case .noAccessibility:
            alert.messageText = "SpaceNamer needs Accessibility access"
            alert.informativeText = "macOS only lets apps switch Spaces by pressing the Mission Control shortcuts. Allow SpaceNamer in System Settings → Privacy & Security → Accessibility."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            }
        case .noShortcut(let number):
            alert.messageText = "Mission Control shortcut for Desktop \(number) is off"
            alert.informativeText = "SpaceNamer switches Spaces by pressing the Mission Control shortcuts, and “Switch to Desktop \(number)” is turned off. Set Up Shortcuts turns on ⌃1…⌃9 for Desktops 1–9 and ⌃←/⌃→ to move between Spaces."
            alert.addButton(withTitle: "Set Up Shortcuts")
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                setUpShortcuts()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: retry)
            case .alertSecondButtonReturn:
                Self.openShortcutSettings()
            default:
                break
            }
        case .cannotGrab(let appName):
            alert.messageText = "Can’t move this \(appName) window"
            alert.informativeText = "SpaceNamer moves windows by holding them by the title bar, and this window has no free spot there (or it is full screen). Drag it in Mission Control instead."
            alert.runModal()
        }
    }

    func setUpShortcuts() {
        SpaceSwitcher.enableMissionControlShortcuts(desktops: manager.spaces.count)
    }

    static func openShortcutSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
