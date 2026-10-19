import AppKit
import Combine

struct Space: Identifiable, Equatable {
    let id: Int             // ManagedSpaceID, changes across reboots
    let key: String         // stable key used to store the name
    let number: Int         // "Desktop N" as Mission Control counts it
    let displayID: String
    let position: Int       // index among all spaces on its display, full-screen apps included
    let customName: String?
    let emoji: String?
    let colorIndex: Int     // wallpaper color from WallpaperColor.palette
    let isCurrent: Bool

    var name: String { customName ?? "Desktop \(number)" }
    var title: String { [emoji, name].compactMap { $0 }.joined(separator: " ") }
}

final class SpaceManager: ObservableObject {
    @Published private(set) var spaces: [Space] = []
    /// Position of the visible space on each display, used for left/right switching.
    private(set) var currentPosition: [String: Int] = [:]
    private(set) var activeSpaceID: Int = 0
    /// Fires once each time the active space changes.
    let activeSpaceChanged = PassthroughSubject<Void, Never>()
    private var pollTimer: Timer?

    private let namesKey = "spaceNames"
    private let emojisKey = "spaceEmojis"
    private let colorsKey = "spaceColors"

    private func stored(_ defaultsKey: String) -> [String: String] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    private func store(_ value: String?, for space: Space, in defaultsKey: String) {
        var values = stored(defaultsKey)
        values[space.key] = value
        UserDefaults.standard.set(values, forKey: defaultsKey)
        refresh()
    }

    var current: Space? { spaces.first { $0.isCurrent } }

    init() {
        refresh()
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        // The notification only arrives after the switch animation; polling the (cheap)
        // active space ID notices the change sooner.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, Int(CGSGetActiveSpace(CGSMainConnectionID())) != self.activeSpaceID else { return }
            self.refresh()
        }
        pollTimer?.tolerance = 0.01
    }

    func refresh() {
        let cid = CGSMainConnectionID()
        let active = Int(CGSGetActiveSpace(cid))
        let displays = CGSCopyManagedDisplaySpaces(cid)?.takeRetainedValue() as? [[String: Any]] ?? []
        let names = stored(namesKey)
        let emojis = stored(emojisKey)
        let colors = stored(colorsKey)

        var result: [Space] = []
        var positions: [String: Int] = [:]
        var number = 0
        for display in displays {
            let displayID = display["Display Identifier"] as? String ?? ""
            let visibleID = (display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int
            let list = display["Spaces"] as? [[String: Any]] ?? []
            for (position, info) in list.enumerated() {
                let sid = info["ManagedSpaceID"] as? Int ?? 0
                if sid == visibleID { positions[displayID] = position }
                // type 0 is a regular desktop, 4 is a full-screen app
                guard (info["type"] as? Int) == 0 else { continue }
                number += 1
                var key = info["uuid"] as? String ?? ""
                if key.isEmpty { key = "default-\(displayID)" } // the first desktop has no uuid
                result.append(Space(id: sid, key: key, number: number, displayID: displayID,
                                    position: position, customName: names[key], emoji: emojis[key],
                                    colorIndex: colors[key].flatMap { Int($0) } ?? (number - 1) % WallpaperColor.palette.count,
                                    isCurrent: sid == active))
            }
        }
        currentPosition = positions
        let changed = active != activeSpaceID
        activeSpaceID = active
        if result != spaces { spaces = result }
        if changed { activeSpaceChanged.send() }
    }

    func rename(_ space: Space, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        store(trimmed.isEmpty ? nil : trimmed, for: space, in: namesKey)
    }

    func setColor(_ space: Space, to index: Int) {
        store(String(index), for: space, in: colorsKey)
    }

    /// Keeps only the first character (one emoji, flags and skin tones included); nil removes it.
    func setEmoji(_ space: Space, to emoji: String?) {
        let first = emoji?.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init)
        store(first, for: space, in: emojisKey)
    }
}
