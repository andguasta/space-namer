import AppKit
import ApplicationServices

enum SwitchError: Error {
    case noAccessibility
    case noShortcut(Int)
    case cannotGrab(String)
}

/// Switches spaces by pressing the Mission Control keyboard shortcuts configured in
/// System Settings, which is the only way to do it with SIP enabled.
enum SpaceSwitcher {
    private struct Shortcut {
        let keyCode: CGKeyCode
        let flags: CGEventFlags
    }

    private static let domain = "com.apple.symbolichotkeys" as CFString
    private static let moveLeftID = 79, moveRightID = 81
    private static let digitKeyCodes = [18, 19, 20, 21, 23, 22, 26, 28, 25]  // 1...9
    private static let control = 0x40000, arrowFlags = 0x840000             // ⌃, ⌃ + fn

    /// "Switch to Desktop N" is symbolic hotkey 118 + N - 1 (desktops 1...16).
    private static func desktopID(_ number: Int) -> Int { 117 + number }

    static func go(to target: Space, manager: SpaceManager) -> SwitchError? {
        switch presses(to: target, manager: manager) {
        case .failure(let error):
            return error
        case .success(let shortcuts):
            for (i, shortcut) in shortcuts.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.15) { press(shortcut) }
            }
            return nil
        }
    }

    /// Checks that switching to the space is possible without pressing anything.
    static func canSwitch(to target: Space, manager: SpaceManager) -> SwitchError? {
        if case .failure(let error) = presses(to: target, manager: manager) { return error }
        return nil
    }

    private static func presses(to target: Space, manager: SpaceManager) -> Result<[Shortcut], SwitchError> {
        guard AXIsProcessTrusted() else { return .failure(.noAccessibility) }
        manager.refresh()
        guard let target = manager.spaces.first(where: { $0.key == target.key }), !target.isCurrent else {
            return .success([])
        }
        if target.number <= 16, let shortcut = shortcut(id: desktopID(target.number)) {
            return .success([shortcut])
        }
        // Fall back to stepping with "Move left/right a space" on the same display.
        guard let from = manager.currentPosition[target.displayID],
              let shortcut = shortcut(id: target.position < from ? moveLeftID : moveRightID)
        else { return .failure(.noShortcut(target.number)) }
        return .success(Array(repeating: shortcut, count: abs(target.position - from)))
    }

    /// Turns on ⌃1…⌃9 for "Switch to Desktop N" and ⌃←/⌃→ for "Move left/right a space",
    /// keeping any key combination already assigned to them.
    static func enableMissionControlShortcuts(desktops: Int) {
        CFPreferencesAppSynchronize(domain)
        var all = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any] ?? [:]
        func enable(_ id: Int, keyCode: Int, flags: Int) {
            var entry = all[String(id)] as? [String: Any] ?? [:]
            let params = (entry["value"] as? [String: Any])?["parameters"] as? [Int]
            if params == nil || params?.count != 3 || params?[1] == 65535 {
                entry["value"] = ["parameters": [65535, keyCode, flags], "type": "standard"] as [String: Any]
            }
            entry["enabled"] = true
            all[String(id)] = entry
        }
        for n in 1...min(max(desktops, 1), digitKeyCodes.count) {
            enable(desktopID(n), keyCode: digitKeyCodes[n - 1], flags: control)
        }
        enable(moveLeftID, keyCode: 123, flags: arrowFlags)
        enable(moveRightID, keyCode: 124, flags: arrowFlags)
        CFPreferencesSetAppValue("AppleSymbolicHotKeys" as CFString, all as CFDictionary, domain)
        CFPreferencesAppSynchronize(domain)

        // Makes the system reload keyboard shortcuts without logging out.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings")
        task.arguments = ["-u"]
        try? task.run()
        task.waitUntilExit()
    }

    private static func shortcut(id: Int) -> Shortcut? {
        CFPreferencesAppSynchronize(domain)
        let all = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any] ?? [:]
        guard let entry = all[String(id)] as? [String: Any] else {
            // A missing entry means the macOS default: only ⌃←/⌃→ are on.
            switch id {
            case moveLeftID: return Shortcut(keyCode: 123, flags: CGEventFlags(rawValue: UInt64(arrowFlags)))
            case moveRightID: return Shortcut(keyCode: 124, flags: CGEventFlags(rawValue: UInt64(arrowFlags)))
            default: return nil
            }
        }
        guard (entry["enabled"] as? Bool) == true,
              let value = entry["value"] as? [String: Any],
              let params = value["parameters"] as? [Int], params.count == 3, params[1] != 65535
        else { return nil }
        return Shortcut(keyCode: CGKeyCode(params[1]), flags: CGEventFlags(rawValue: UInt64(params[2])))
    }

    /// Presses the shortcut like a keyboard would, modifiers included.
    private static func press(_ shortcut: Shortcut) {
        let source = CGEventSource(stateID: .hidSystemState)
        let modifiers: [(CGEventFlags, CGKeyCode)] = [(.maskControl, 59), (.maskAlternate, 58), (.maskShift, 56), (.maskCommand, 55)]
            .filter { shortcut.flags.contains($0.0) }
        var held: CGEventFlags = []
        func post(_ key: CGKeyCode, down: Bool, flags: CGEventFlags) {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
        for (flag, key) in modifiers {
            held.insert(flag)
            post(key, down: true, flags: held)
        }
        post(shortcut.keyCode, down: true, flags: shortcut.flags)
        post(shortcut.keyCode, down: false, flags: shortcut.flags)
        for (flag, key) in modifiers.reversed() {
            held.remove(flag)
            post(key, down: false, flags: held)
        }
    }
}
