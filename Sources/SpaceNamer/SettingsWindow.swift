import AppKit
import SwiftUI

final class SettingsWindow {
    private var window: NSWindow?
    private let onPreview: () -> Void

    init(onPreview: @escaping () -> Void) {
        self.onPreview = onPreview
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "SpaceNamer Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(onPreview: onPreview))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    let onPreview: () -> Void
    @AppStorage(HUDSettings.enabledKey) private var enabled = HUDSettings.enabled
    @AppStorage(HUDSettings.opacityKey) private var opacity = HUDSettings.opacity
    @AppStorage(HUDSettings.durationKey) private var duration = HUDSettings.duration
    @AppStorage(SpaceWallpapers.enabledKey) private var wallpapers = SpaceWallpapers.enabled

    var body: some View {
        Form {
            Section("Name when switching Space") {
                Toggle("Show the Space name in the middle of the screen", isOn: $enabled)
                LabeledContent("Opacity") {
                    HStack {
                        Slider(value: $opacity, in: 0.2...1, step: 0.05)
                        Text("\(Int(opacity * 100))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                .disabled(!enabled)
                LabeledContent("Duration") {
                    HStack {
                        Slider(value: $duration, in: 0.3...5, step: 0.1)
                        Text(String(format: "%.1f s", duration)).monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                .disabled(!enabled)
                HStack {
                    Spacer()
                    Button("Preview", action: onPreview).disabled(!enabled)
                }
            }
            Section("Wallpapers") {
                Toggle("Give each Space its own wallpaper", isOn: $wallpapers)
                Text("Choose a Space’s color with ⌘I in the switcher. Turning this off restores your previous wallpaper on each Space as you visit it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }
}
