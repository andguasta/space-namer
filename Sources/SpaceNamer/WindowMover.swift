import AppKit
import ApplicationServices

/// Moves a window to another space without SIP: holds the window by its title bar while
/// pressing the Mission Control shortcut, so the window travels along like a manual drag.
enum WindowMover {
    struct Target {
        let window: AXUIElement
        let appName: String
    }

    /// Controls under the cursor that would react to a click instead of dragging the window.
    private static let clickableRoles: Set<String> = [
        "AXButton", "AXRadioButton", "AXTab", "AXTextField", "AXSearchField", "AXComboBox",
        "AXPopUpButton", "AXMenuButton", "AXCheckBox", "AXSlider", "AXLink", "AXTextArea",
    ]

    static func focusedWindow() -> Target? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let window: AXUIElement = attribute(axApp, kAXFocusedWindowAttribute) else { return nil }
        return Target(window: window, appName: app.localizedName ?? "Window")
    }

    static func move(_ target: Target, to space: Space, manager: SpaceManager) -> SwitchError? {
        guard AXIsProcessTrusted() else { return .noAccessibility }
        if (attribute(target.window, "AXFullScreen") as Bool?) == true { return .cannotGrab(target.appName) }
        if let error = SpaceSwitcher.canSwitch(to: space, manager: manager) { return error }
        guard let grab = grabPoint(target.window) else { return .cannotGrab(target.appName) }

        let original = CGEvent(source: nil)?.location ?? grab
        mouse(.mouseMoved, at: grab)
        mouse(.leftMouseDown, at: grab)
        // Apps that drag their window themselves (like Aseprite) only start once the mouse moves.
        mouse(.leftMouseDragged, at: CGPoint(x: grab.x + 4, y: grab.y))
        mouse(.leftMouseDragged, at: grab)

        let steps = max(1, abs(space.position - (manager.currentPosition[space.displayID] ?? space.position)))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let error = SpaceSwitcher.go(to: space, manager: manager)
            // Keep holding the window until the space change animation is over.
            let wait = error == nil ? 0.5 + Double(steps) * 0.15 : 0
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                mouse(.leftMouseUp, at: grab)
                mouse(.mouseMoved, at: original)
            }
        }
        return nil
    }

    /// An empty spot of the title bar: right of the window buttons, else the middle of the bar.
    private static func grabPoint(_ window: AXUIElement) -> CGPoint? {
        guard let frame = frame(of: window) else { return nil }
        let buttons = [kAXZoomButtonAttribute, kAXMinimizeButtonAttribute, kAXCloseButtonAttribute]
            .compactMap { attribute(window, $0) as AXUIElement? }.compactMap(frame(of:))
        let barY = buttons.first?.midY ?? frame.minY + 14
        let afterButtons = (buttons.map(\.maxX).max() ?? frame.minX + 70) + 12
        let candidates = [afterButtons, frame.midX, frame.minX + frame.width * 0.7, frame.minX + frame.width * 0.3]
            .map { CGPoint(x: $0, y: barY) }
        let systemWide = AXUIElementCreateSystemWide()
        return candidates.first { point in
            var element: AXUIElement?
            guard frame.contains(point),
                  AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element) == .success,
                  let element else { return false }
            let role: String = attribute(element, kAXRoleAttribute) ?? ""
            return !clickableRoles.contains(role)
        }
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let position: AXValue = attribute(element, kAXPositionAttribute),
              let size: AXValue = attribute(element, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position, .cgPoint, &origin)
        AXValueGetValue(size, .cgSize, &extent)
        return CGRect(origin: origin, size: extent)
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private static func mouse(_ type: CGEventType, at point: CGPoint) {
        CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: type,
                mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
}
