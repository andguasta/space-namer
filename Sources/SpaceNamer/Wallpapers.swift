import AppKit
import Combine

struct WallpaperColor {
    let name: String
    let dark: UInt32   // edge of the gradient
    let light: UInt32  // soft glow toward the top

    static let palette = [
        WallpaperColor(name: "Slate", dark: 0x353C4A, light: 0x606C88),
        WallpaperColor(name: "Teal", dark: 0x24443F, light: 0x508A83),
        WallpaperColor(name: "Plum", dark: 0x3A2E40, light: 0x795A84),
        WallpaperColor(name: "Moss", dark: 0x2F3924, light: 0x667D54),
        WallpaperColor(name: "Umber", dark: 0x3C2D24, light: 0x7C5A46),
        WallpaperColor(name: "Midnight", dark: 0x212840, light: 0x4C5A87),
        WallpaperColor(name: "Rose", dark: 0x422D35, light: 0x895A68),
        WallpaperColor(name: "Ochre", dark: 0x3C3424, light: 0x817048),
    ]

    static func nsColor(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// Gives every space its own soft gradient wallpaper. macOS only sets the wallpaper of the
/// space currently on screen, so each space is painted when it becomes visible.
final class SpaceWallpapers {
    static let enabledKey = "wallpapersEnabled"
    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    private let manager: SpaceManager
    private var cancellable: AnyCancellable?
    private let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("SpaceNamer/Wallpapers", isDirectory: true)
    /// Wallpaper each screen of each space had before SpaceNamer changed it, keyed "space|screen".
    private let originalsKey = "originalWallpapers"

    init(manager: SpaceManager) {
        self.manager = manager
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        cancellable = manager.$spaces.receive(on: RunLoop.main).sink { [weak self] in self?.update($0) }
        for name in [UserDefaults.didChangeNotification, NSApplication.didChangeScreenParametersNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.update(self.manager.spaces)
            }
        }
    }

    private func update(_ spaces: [Space]) {
        var originals = UserDefaults.standard.dictionary(forKey: originalsKey) as? [String: String] ?? [:]
        let before = originals
        for space in spaces where manager.currentPosition[space.displayID] == space.position {
            for (id, screen) in DesktopLabels.screens(for: space) {
                let key = "\(space.key)|\(id)"
                let current = NSWorkspace.shared.desktopImageURL(for: screen)
                if Self.enabled {
                    guard let url = image(WallpaperColor.palette[space.colorIndex], for: screen), url != current else { continue }
                    if let current, !current.path.hasPrefix(folder.path), originals[key] == nil {
                        originals[key] = current.path
                    }
                    try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
                } else if let path = originals[key] {
                    // Turned off: put back what was there before.
                    try? NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: path), for: screen, options: [:])
                    originals[key] = nil
                }
            }
        }
        if originals != before { UserDefaults.standard.set(originals, forKey: originalsKey) }
    }

    /// Renders (once) the gradient for this color at the screen's pixel size.
    private func image(_ color: WallpaperColor, for screen: NSScreen) -> URL? {
        let width = Int(screen.frame.width * screen.backingScaleFactor)
        let height = Int(screen.frame.height * screen.backingScaleFactor)
        // The colors are part of the name, so changing the palette produces new files.
        let url = folder.appendingPathComponent(String(format: "%@-%06X-%06X-%dx%d.png", color.name, color.dark, color.light, width, height))
        if FileManager.default.fileExists(atPath: url.path) { return url }

        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        WallpaperColor.nsColor(color.dark).setFill()
        rect.fill()
        // A wide soft glow from the upper left fading into the dark edges.
        NSGradient(colors: [WallpaperColor.nsColor(color.light), WallpaperColor.nsColor(color.dark)])?
            .draw(in: rect.insetBy(dx: -rect.width * 0.4, dy: -rect.height * 0.4),
                  relativeCenterPosition: NSPoint(x: -0.25, y: 0.35))
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]), (try? data.write(to: url)) != nil else { return nil }
        return url
    }
}
