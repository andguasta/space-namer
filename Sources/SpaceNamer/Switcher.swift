import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

final class SwitcherModel: ObservableObject {
    static let columns = 3

    let manager: SpaceManager
    @Published var query = "" { didSet { selection = 0 } }
    @Published var selection = 0
    @Published var editingKey: String?
    @Published var editText = ""
    @Published var emojiKey: String?       // space whose emoji is being picked
    @Published var emojiText = ""
    @Published var focusToken = 0
    var onSwitch: ((Space) -> Void)?
    private var cancellable: AnyCancellable?

    init(manager: SpaceManager) {
        self.manager = manager
        cancellable = manager.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }

    var filtered: [Space] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return manager.spaces }
        return manager.spaces.filter { $0.name.lowercased().contains(q) || String($0.number) == q }
    }

    var selected: Space? { filtered.indices.contains(selection) ? filtered[selection] : nil }

    func move(_ delta: Int) {
        let count = filtered.count
        guard count > 0 else { return }
        selection = min(max(selection + delta, 0), count - 1)
    }

    func activateSelection() {
        if let selected { onSwitch?(selected) }
    }

    func beginRename(_ space: Space? = nil) {
        guard let space = space ?? selected else { return }
        editText = space.customName ?? ""
        editingKey = space.key
    }

    func commitRename() {
        if let key = editingKey, let space = manager.spaces.first(where: { $0.key == key }) {
            manager.rename(space, to: editText)
        }
        editingKey = nil
    }

    func cancelRename() { editingKey = nil }

    var emojiSpace: Space? { manager.spaces.first { $0.key == emojiKey } }

    func beginEmoji(_ space: Space? = nil) {
        guard let space = space ?? selected else { return }
        editingKey = nil
        emojiText = ""
        emojiKey = space.key
    }

    func setEmoji(_ emoji: String?) {
        if let space = emojiSpace { manager.setEmoji(space, to: emoji) }
        emojiKey = nil
    }

    func commitEmojiText() { setEmoji(emojiText.isEmpty ? emojiSpace?.emoji : emojiText) }

    func cancelEmoji() { emojiKey = nil }

    func setColor(_ index: Int) {
        if let space = emojiSpace { manager.setColor(space, to: index) }
    }
}

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    @FocusState private var focus: Field?
    private enum Field { case search, rename, emoji }

    var body: some View {
        Group {
            if let space = model.emojiSpace {
                EmojiPicker(model: model, space: space, focus: $focus, field: .emoji)
            } else {
                grid
            }
        }
        .padding(16)
        .frame(width: 580, height: 380)
        .onAppear(perform: updateFocus)
        .onChange(of: model.editingKey) { _, _ in updateFocus() }
        .onChange(of: model.emojiKey) { _, _ in updateFocus() }
        .onChange(of: model.focusToken) { _, _ in updateFocus() }
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search spaces…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.title2)
                .focused($focus, equals: .search)
            Divider()
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: SwitcherModel.columns),
                          spacing: 10) {
                    ForEach(Array(model.filtered.enumerated()), id: \.element.id) { index, space in
                        card(space, selected: index == model.selection)
                            .onTapGesture { model.onSwitch?(space) }
                    }
                }
                .padding(2)
            }
            Text("↩ go   ⇥ or ⌘E rename   ⌘I emoji   ⌘1–9 jump   esc close")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func card(_ space: Space, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(space.number)")
                    .font(.caption.monospacedDigit().bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.2)))
                Button { model.beginEmoji(space) } label: {
                    if let emoji = space.emoji {
                        Text(emoji).font(.title3)
                    } else {
                        Image(systemName: "face.smiling").font(.system(size: 15))
                    }
                }
                .buttonStyle(.borderless)
                .help("Choose emoji")
                Spacer()
                if space.isCurrent {
                    Text("current").font(.caption2).foregroundStyle(.secondary)
                }
                Button { model.beginRename(space) } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.secondary.opacity(0.15)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Rename")
            }
            if model.editingKey == space.key {
                TextField("Desktop \(space.number)", text: $model.editText)
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .rename)
            } else {
                Text(space.name)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(space.customName == nil ? .secondary : .primary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(Rectangle())
    }

    private func updateFocus() {
        DispatchQueue.main.async {
            focus = model.emojiKey != nil ? .emoji : model.editingKey != nil ? .rename : .search
        }
    }
}

private final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class SwitcherController: NSObject, NSWindowDelegate {
    private let manager: SpaceManager
    private let model: SwitcherModel
    private let panel: SwitcherPanel
    private var monitor: Any?
    var onSwitch: ((Space) -> Void)?

    init(manager: SpaceManager) {
        self.manager = manager
        model = SwitcherModel(manager: manager)
        panel = SwitcherPanel(contentRect: NSRect(x: 0, y: 0, width: 580, height: 380),
                              styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                              backing: .buffered, defer: true)
        super.init()

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { panel.standardWindowButton($0)?.isHidden = true }
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.delegate = self

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        let hosting = NSHostingView(rootView: SwitcherView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        panel.contentView = effect

        model.onSwitch = { [weak self] space in self?.finish(with: space) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            return self.handle(event) ? nil : event
        }
    }

    enum Mode { case browse, renameCurrent, emojiForCurrent }

    var isVisible: Bool { panel.isVisible }

    func show(_ mode: Mode = .browse) {
        manager.refresh()
        model.editingKey = nil
        model.emojiKey = nil
        model.query = ""
        model.selection = manager.spaces.firstIndex(where: \.isCurrent) ?? 0
        switch mode {
        case .browse: break
        case .renameCurrent: model.beginRename(manager.current)
        case .emojiForCurrent: model.beginEmoji(manager.current)
        }
        model.focusToken += 1

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2,
                                         y: frame.midY - panel.frame.height / 2 + frame.height * 0.1))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        model.editingKey = nil
        model.emojiKey = nil
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) { hide() }

    private func finish(with space: Space) {
        hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.onSwitch?(space) }
    }

    private func handle(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.contains(.command)
        if model.emojiKey != nil {
            switch Int(event.keyCode) {
            case kVK_Escape: model.cancelEmoji(); return true
            case kVK_Return, kVK_ANSI_KeypadEnter: model.commitEmojiText(); return true
            default: return false
            }
        }
        let editing = model.editingKey != nil
        switch Int(event.keyCode) {
        case kVK_Escape:
            editing ? model.cancelRename() : hide()
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            editing ? model.commitRename() : model.activateSelection()
            return true
        case kVK_Tab where !editing:
            model.beginRename()
            return true
        case kVK_LeftArrow where !editing: model.move(-1); return true
        case kVK_RightArrow where !editing: model.move(1); return true
        case kVK_UpArrow where !editing: model.move(-SwitcherModel.columns); return true
        case kVK_DownArrow where !editing: model.move(SwitcherModel.columns); return true
        default: break
        }
        guard command, !editing, let chars = event.charactersIgnoringModifiers else { return false }
        if chars == "e" {
            model.beginRename()
            return true
        }
        if chars == "i" {
            model.beginEmoji()
            return true
        }
        if let n = Int(chars), let space = manager.spaces.first(where: { $0.number == n }) {
            finish(with: space)
            return true
        }
        return false
    }
}
