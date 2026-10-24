#if os(iOS)
import SwiftUI

/// Keeps the panel in step with the settings and the library, whoever changes them.
final class AtmosphereModel: ObservableObject {
    let settings: WriterSettings
    let library: Library
    @Published private(set) var revision = 0

    init(settings: WriterSettings, library: Library) {
        self.settings = settings
        self.library = library
        NotificationCenter.default.addObserver(
            self, selector: #selector(changed), name: WriterSettings.didChange, object: settings)
        NotificationCenter.default.addObserver(
            self, selector: #selector(changed), name: Library.didChange, object: library)
    }

    @objc private func changed() { revision += 1 }
}

/// The speaker button's popover, as on the Mac: the scene behind the text, which ambient sound
/// and keystroke sounds play, and how loud. Every change is saved at once.
struct AtmospherePanel: View {
    @ObservedObject var model: AtmosphereModel

    private var settings: WriterSettings { model.settings }
    private var library: Library { model.library }

    struct Option: Identifiable {
        let title: String
        /// Nil for Off.
        let id: String?
        let isLocked: Bool
    }

    var body: some View {
        let _ = model.revision
        VStack(alignment: .leading, spacing: 18) {
            section("Scene") {
                choices(sceneOptions, chosen: library.resolvedSceneID(settings.sceneChoice)) { id in
                    if let id { library.chooseScene(id, in: settings) }
                }
            }
            section("Ambient") {
                choices(soundOptions(library.ambiences.map { ($0.title, $0.id) }),
                        chosen: settings.ambientSound ? library.ambience(for: settings.ambientChoice).id : nil) { id in
                    library.chooseAmbience(id, in: settings)
                }
                volume("Ambient volume", Binding(
                    get: { Double(settings.ambientVolume) }, set: { settings.ambientVolume = Float($0) }))
            }
            section("Keystrokes") {
                choices(soundOptions(library.keystrokeSets.map { ($0.title, $0.id) }),
                        chosen: settings.keystrokeSounds ? library.keystrokeSet(for: settings.keystrokeChoice).id : nil) { id in
                    library.chooseKeystrokes(id, in: settings)
                }
                volume("Keystroke volume", Binding(
                    get: { Double(settings.keystrokeVolume) }, set: { settings.keystrokeVolume = Float($0) }))
            }
            // The system keyboard's own clicks play under Fallow's, and only Settings can turn them off.
            Text("Sounds best with headphones, and with keyboard sound off in Settings › Sounds & Haptics")
                .font(Font(settings.chromeFont(size: 12)).italic())
                .foregroundStyle(Color(Palette.secondary))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(width: 320, alignment: .leading)
    }

    private var sceneOptions: [Option] {
        library.scenes.map { Option(title: $0.title, id: $0.id, isLocked: !library.isAvailable($0.id)) }
            + [Option(title: "Drift", id: Library.driftID, isLocked: false)]
    }

    private func soundOptions(_ items: [(title: String, id: String)]) -> [Option] {
        items.map { Option(title: $0.title, id: $0.id, isLocked: !library.isAvailable($0.id)) }
            + [Option(title: "Off", id: nil, isLocked: false)]
    }

    /// A small letter-spaced heading over its controls.
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(Font(settings.chromeFont(size: 10, weight: .semibold)))
                .tracking(1.2)
                .foregroundStyle(Color(Palette.secondary))
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    /// The choices as words separated by dots, the chosen one darker. Long rows wrap.
    private func choices(_ options: [Option], chosen: String?, choose: @escaping (String?) -> Void) -> some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                HStack(spacing: 6) {
                    Button {
                        choose(option.id)
                    } label: {
                        HStack(spacing: 3) {
                            Text(option.title)
                            if option.isLocked {
                                Image(systemName: "lock.fill").imageScale(.small).accessibilityLabel("Locked")
                            }
                        }
                        .foregroundStyle(Color(option.id == chosen ? Palette.text : Palette.secondary))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(option.id == chosen ? .isSelected : [])
                    if index < options.count - 1 {
                        Text("·").foregroundStyle(Color(Palette.secondary)).accessibilityHidden(true)
                    }
                }
            }
        }
        .font(Font(settings.chromeFont(size: 16)))
    }

    private func volume(_ label: String, _ value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill").imageScale(.small)
            Slider(value: value, in: 0...1).tint(Color(Palette.caret)).accessibilityLabel(label)
            Image(systemName: "speaker.wave.3.fill").imageScale(.small)
        }
        .foregroundStyle(Color(Palette.secondary))
        .padding(.top, 2)
    }
}

/// Lays its views out in rows, wrapping to a new row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : spacing + size.width
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let added = rows[rows.count - 1].indices.isEmpty ? size.width : spacing + size.width
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += added
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
#endif
