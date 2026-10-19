import AppKit
import Combine
import SwiftUI

enum HUDSettings {
    static let enabledKey = "hudEnabled"
    static let opacityKey = "hudOpacity"
    static let durationKey = "hudDuration"

    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    static var opacity: Double { UserDefaults.standard.object(forKey: opacityKey) as? Double ?? 0.5 }
    static var duration: Double { UserDefaults.standard.object(forKey: durationKey) as? Double ?? 0.8 }
}

/// Shows the name of the space just landed on in the middle of the screen for a moment.
final class SpaceHUD {
    private let manager: SpaceManager
    private let panel: NSPanel
    private var generation = 0  // lets a newer switch cancel the pending fade-out
    private var cancellable: AnyCancellable?
    private var shownKey: String?
    private var shownAt = Date.distantPast
    private let hosting: NSHostingView<HUDView>

    init(manager: SpaceManager) {
        self.manager = manager
        hosting = NSHostingView(rootView: HUDView(emoji: nil, name: ""))
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 160),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = hosting

        cancellable = manager.activeSpaceChanged.sink { [weak self] in
            guard let self, HUDSettings.enabled, let space = self.manager.current else { return }
            // Already announced when the switch started.
            if space.key == self.shownKey, Date().timeIntervalSince(self.shownAt) < HUDSettings.duration + 0.8 { return }
            self.show(space)
        }
    }

    func showCurrent() {
        manager.refresh()
        guard let space = manager.current else { return }  // full-screen apps have no name
        show(space)
    }

    /// Shows a space that is about to become active, before macOS finishes switching.
    func announce(_ space: Space) {
        guard HUDSettings.enabled else { return }
        show(space)
    }

    private func show(_ space: Space) {
        shownKey = space.key
        shownAt = Date()
        generation += 1
        let current = generation

        hosting.rootView = HUDView(emoji: space.emoji, name: space.name)
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let frame = screen?.frame {
            panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                                  width: size.width, height: size.height), display: true)
        }

        panel.alphaValue = HUDSettings.opacity
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + HUDSettings.duration) { [weak self] in
            guard let self, self.generation == current else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                self.panel.animator().alphaValue = 0
            }, completionHandler: {
                if self.generation == current { self.panel.orderOut(nil) }
            })
        }
    }
}

private struct HUDView: View {
    let emoji: String?
    let name: String

    var body: some View {
        VStack(spacing: 6) {
            if let emoji {
                Text(emoji).font(.system(size: 64))
            }
            Text(name)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
        .frame(minWidth: 220)
        .background(RoundedRectangle(cornerRadius: 24).fill(.black.opacity(0.75)))
    }
}
