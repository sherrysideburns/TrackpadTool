import SwiftUI

/// Corner sizes, one per corner, with a drawing of the trackpad showing
/// exactly which area counts as each corner.
struct CornerSettingsRow: View {
    @EnvironmentObject var store: SettingsStore

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            TrackpadCornersDrawing()
                .frame(width: 168, height: 108)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("All corners").fontWeight(.medium)
                    Picker("", selection: allBinding) {
                        if store.sharedCornerSize == nil {
                            Text("Mixed").tag("mixed")
                            Divider()
                        }
                        ForEach(CornerSize.allCases) { size in
                            Text(size.title).tag(size.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                Divider()
                ForEach(Corner.allCases) { corner in
                    GridRow {
                        Text(corner.title).foregroundStyle(.secondary)
                        Picker("", selection: binding(corner)) {
                            ForEach(CornerSize.allCases) { size in
                                Text(size.title).tag(size)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    /// "mixed" while the corners differ; picking a size sets all four.
    private var allBinding: Binding<String> {
        Binding(
            get: { store.sharedCornerSize?.rawValue ?? "mixed" },
            set: { value in
                if let size = CornerSize(rawValue: value) { store.setAllCornerSizes(size) }
            }
        )
    }

    private func binding(_ corner: Corner) -> Binding<CornerSize> {
        Binding(get: { store.cornerSize(corner) }, set: { store.setCornerSize(corner, $0) })
    }
}

private struct TrackpadCornersDrawing: View {
    @EnvironmentObject var store: SettingsStore

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
                ForEach(Corner.allCases) { corner in
                    let size = store.cornerSize(corner)
                    if size != .off {
                        let zw = w * CGFloat(size.width)
                        let zh = h * CGFloat(size.height)
                        let used = store.isUsed(corner.gesture)
                        Rectangle()
                            .fill(Color.accentColor.opacity(used ? 0.45 : 0.18))
                            .frame(width: zw, height: zh)
                            .offset(x: corner.isLeft ? 0 : w - zw, y: corner.isTop ? 0 : h - zh)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityLabel("Trackpad corners")
    }
}
