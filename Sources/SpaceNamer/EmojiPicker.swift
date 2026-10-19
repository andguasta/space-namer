import SwiftUI

private let suggestedEmojis = Array(
    "💼🏠💻🧑‍💻📧💬📅📝📚🎓🔬🧪🎨🎵🎧🎬🎮📷✈️🛒💰📈📊🗂️⚙️🛠️🐛🚀🌐🔒⭐️🔥💡🎯❤️🌿☕️🍕⚽️🏃🐶🌙☀️🧘🗓️📦🔴🟠🟡🟢🔵🟣"
).map(String.init)

struct EmojiPicker<Field: Hashable>: View {
    @ObservedObject var model: SwitcherModel
    let space: Space
    var focus: FocusState<Field?>.Binding
    let field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Emoji for \(space.name)").font(.title2)
                Spacer()
                TextField("Type or paste any emoji", text: $model.emojiText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .focused(focus, equals: field)
            }
            HStack(spacing: 10) {
                Text("Wallpaper").foregroundStyle(.secondary)
                ForEach(WallpaperColor.palette.indices, id: \.self) { index in
                    let color = WallpaperColor.palette[index]
                    Button { model.setColor(index) } label: {
                        Circle()
                            .fill(LinearGradient(colors: [Color(nsColor: WallpaperColor.nsColor(color.light)),
                                                          Color(nsColor: WallpaperColor.nsColor(color.dark))],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 26, height: 26)
                            .overlay(Circle().stroke(Color.accentColor, lineWidth: index == space.colorIndex ? 3 : 0))
                    }
                    .buttonStyle(.plain)
                    .help(color.name)
                }
            }
            Divider()
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 6), count: 11), spacing: 6) {
                    ForEach(suggestedEmojis, id: \.self) { emoji in
                        Button { model.setEmoji(emoji) } label: {
                            Text(emoji)
                                .font(.system(size: 26))
                                .frame(width: 44, height: 40)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(emoji == space.emoji ? Color.accentColor.opacity(0.3) : .clear))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Text("↩ use typed emoji   ⌃⌘Space all emoji   esc back")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if space.emoji != nil {
                    Button("Remove Emoji") { model.setEmoji(nil) }
                }
            }
        }
    }
}
