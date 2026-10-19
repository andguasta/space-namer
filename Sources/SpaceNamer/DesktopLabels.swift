import AppKit
import Combine
import SwiftUI

/// Puts the space's name on its desktop, under all normal windows, on every screen the space
/// shows on. A window belongs to the space it is created on, so a space's labels are created
/// the first time it becomes visible.
final class DesktopLabels {
    private let manager: SpaceManager
    private var windows: [String: [CGDirectDisplayID: NSWindow]] = [:]  // space key -> screen -> label
    private var cancellable: AnyCancellable?

    static let enabledKey = "desktopLabelsEnabled"
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            if !newValue {
                windows.values.flatMap(\.values).forEach { $0.close() }
                windows.removeAll()
            }
            update(manager.spaces)
        }
    }

    init(manager: SpaceManager) {
        self.manager = manager
        cancellable = manager.$spaces.receive(on: RunLoop.main).sink { [weak self] in self?.update($0) }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.update(self.manager.spaces)
        }
    }

    private func update(_ spaces: [Space]) {
        guard enabled else { return }
        let keys = Set(spaces.map(\.key))
        for (key, labels) in windows where !keys.contains(key) {
            labels.values.forEach { $0.close() }
            windows[key] = nil
        }
        for space in spaces {
            let screens = Self.screens(for: space)
            var labels = windows[space.key] ?? [:]
            // Drop labels of screens that are gone.
            for (id, window) in labels where !screens.keys.contains(id) {
                window.close()
                labels[id] = nil
            }
            let visible = manager.currentPosition[space.displayID] == space.position
            for (id, screen) in screens {
                if let window = labels[id] {
                    window.setFrame(screen.frame, display: false)
                    (window.contentView as? NSHostingView<LabelView>)?.rootView = LabelView(name: space.title)
                } else if visible {
                    labels[id] = makeWindow(for: space, on: screen)
                }
            }
            windows[space.key] = labels.isEmpty ? nil : labels
        }
    }

    /// With "Displays have separate Spaces" a space belongs to one screen; otherwise it spans all of them.
    static func screens(for space: Space) -> [CGDirectDisplayID: NSScreen] {
        var result: [CGDirectDisplayID: NSScreen] = [:]
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            result[id] = screen
        }
        let own = result.filter { id, _ in
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return false }
            return CFUUIDCreateString(nil, uuid) as String == space.displayID
        }
        return own.isEmpty ? result : own
    }

    private func makeWindow(for space: Space, on screen: NSScreen) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.collectionBehavior = [.stationary, .ignoresCycle]
        window.contentView = NSHostingView(rootView: LabelView(name: space.title))
        window.setFrame(screen.frame, display: true)
        window.orderFront(nil)
        return window
    }
}

struct LabelView: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.system(size: 120, weight: .heavy, design: .rounded))
            .foregroundStyle(.white.opacity(0.85))
            .shadow(color: .black.opacity(0.5), radius: 12)
            .lineLimit(1)
            .minimumScaleFactor(0.3)
            .padding(60)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}
