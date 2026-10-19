import AppKit
import ApplicationServices
import Combine
import ServiceManagement

final class StatusBarController: NSObject, NSMenuDelegate {
    private let manager: SpaceManager
    private let labels: DesktopLabels
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cancellable: AnyCancellable?
    var onSwitch: ((Space) -> Void)?
    var onShowSwitcher: ((SwitcherController.Mode) -> Void)?
    var onSetUpShortcuts: (() -> Void)?
    var onShowSettings: (() -> Void)?
    var onMoveWindow: ((WindowMover.Target, Space) -> Void)?
    private var focusedWindow: WindowMover.Target?

    init(manager: SpaceManager, labels: DesktopLabels) {
        self.manager = manager
        self.labels = labels
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        cancellable = manager.$spaces.receive(on: RunLoop.main).sink { [weak self] spaces in
            self?.updateButton(current: spaces.first(where: \.isCurrent))
        }
    }

    private func updateButton(current: Space?) {
        guard let button = item.button else { return }
        if let emoji = current?.emoji {
            button.image = nil
            button.title = "\(emoji) \(current?.name ?? "")"
        } else {
            button.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "Spaces")
            button.imagePosition = .imageLeading
            button.title = " " + (current?.name ?? "Full Screen")
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        manager.refresh()
        // Read before the menu takes focus, so it is the window the user was working in.
        focusedWindow = WindowMover.focusedWindow()
        menu.removeAllItems()
        for space in manager.spaces {
            let entry = NSMenuItem(title: "\(space.number)  \(space.title)", action: #selector(switchSpace(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = space.key
            entry.state = space.isCurrent ? .on : .off
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let moveItem = NSMenuItem(title: focusedWindow.map { "Move \($0.appName) Window to" } ?? "Move Window to",
                                  action: nil, keyEquivalent: "")
        let moveMenu = NSMenu()
        for space in manager.spaces {
            let entry = NSMenuItem(title: "\(space.number)  \(space.title)",
                                   action: space.isCurrent || focusedWindow == nil ? nil : #selector(moveWindow(_:)),
                                   keyEquivalent: "")
            entry.target = self
            entry.representedObject = space.key
            entry.state = space.isCurrent ? .on : .off
            moveMenu.addItem(entry)
        }
        moveItem.submenu = moveMenu
        moveItem.isEnabled = focusedWindow != nil
        menu.addItem(moveItem)
        menu.addItem(.separator())
        add(to: menu, "Open Switcher…", #selector(openSwitcher), key: " ")
        add(to: menu, "Rename Current Space…", #selector(renameCurrent), key: "r")
        add(to: menu, "Choose Emoji for Current Space…", #selector(chooseEmoji), key: "e")
        menu.addItem(.separator())
        add(to: menu, "Show Names on Desktops", #selector(toggleLabels)).state = labels.enabled ? .on : .off
        add(to: menu, "Launch at Login", #selector(toggleLogin)).state = SMAppService.mainApp.status == .enabled ? .on : .off
        if !AXIsProcessTrusted() {
            add(to: menu, "Grant Accessibility Access…", #selector(grantAccessibility))
        }
        add(to: menu, "Set Up Mission Control Shortcuts", #selector(setUpShortcuts))
        add(to: menu, "Mission Control Shortcut Settings…", #selector(openShortcutSettings))
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem(title: "Quit SpaceNamer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @discardableResult
    private func add(to menu: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if !key.isEmpty { entry.keyEquivalentModifierMask = [.control, .option] }
        entry.target = self
        menu.addItem(entry)
        return entry
    }

    @objc private func switchSpace(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let space = manager.spaces.first(where: { $0.key == key }) else { return }
        // Let the menu close before pressing the shortcut.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.onSwitch?(space) }
    }

    @objc private func moveWindow(_ sender: NSMenuItem) {
        guard let window = focusedWindow, let key = sender.representedObject as? String,
              let space = manager.spaces.first(where: { $0.key == key }) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.onMoveWindow?(window, space) }
    }

    @objc private func openSwitcher() { onShowSwitcher?(.browse) }
    @objc private func renameCurrent() { onShowSwitcher?(.renameCurrent) }
    @objc private func chooseEmoji() { onShowSwitcher?(.emojiForCurrent) }
    @objc private func toggleLabels() { labels.enabled.toggle() }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
    }

    @objc private func grantAccessibility() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    @objc private func showSettings() { onShowSettings?() }
    @objc private func setUpShortcuts() { onSetUpShortcuts?() }
    @objc private func openShortcutSettings() { AppDelegate.openShortcutSettings() }
}
