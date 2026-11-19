import AppKit
import SwiftUI

/// What a new user starts with.
enum StartingSetup: String, CaseIterable, Identifiable {
    case windowsStyle, empty
    var id: String { rawValue }

    var title: String {
        switch self {
        case .windowsStyle: return "Windows-style setup"
        case .empty: return "Start empty"
        }
    }

    var symbol: String {
        switch self {
        case .windowsStyle: return "macwindow.on.rectangle"
        case .empty: return "square.dashed"
        }
    }

    var summary: String {
        switch self {
        case .windowsStyle:
            return "Three fingers down hides all apps, up brings them back, left or right switches apps like ⌘Tab. Four fingers work Stage Manager, and TipTap switches tabs."
        case .empty:
            return "Every gesture keeps doing what macOS does. Pick the actions you want yourself."
        }
    }

    var settings: Settings {
        switch self {
        case .windowsStyle: return .windowsStyle
        case .empty: return .empty
        }
    }
}

/// The choice on the welcome window (a class, because the @State macro
/// needs full Xcode).
final class WelcomeModel: ObservableObject {
    @Published var choice: StartingSetup = .windowsStyle
}

/// Shown once, the first time TrackpadTool opens: what it does, the
/// Accessibility permission, and how to start.
struct WelcomeView: View {
    @ObservedObject var status: StatusWatcher
    @StateObject private var model = WelcomeModel()
    /// Only on first launch: shown again later, it must not replace your setup.
    let choosesSetup: Bool
    let onDone: (StartingSetup?) -> Void

    init(status: StatusWatcher, choosesSetup: Bool, onDone: @escaping (StartingSetup?) -> Void) {
        self.status = status
        self.choosesSetup = choosesSetup
        self.onDone = onDone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to TrackpadTool").font(.title2.weight(.semibold))
                    Text("Choose what your trackpad gestures do: snap and switch windows, switch tabs, copy and paste, take screenshots and more.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            step(1, "Allow Accessibility") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("TrackpadTool needs this to move windows, press shortcuts for you and notice clicks. It doesn't read what you type or what's on screen.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if status.accessibilityTrusted {
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        HStack {
                            Button("Open Accessibility settings") {
                                AX.requestTrust()
                                ConflictChecker.openAccessibilitySettings()
                            }
                            Text("Switch TrackpadTool on in the list.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if choosesSetup {
                step(2, "Choose how to start") {
                    VStack(spacing: 8) {
                        ForEach(StartingSetup.allCases) { setup in
                            choiceRow(setup)
                        }
                        Text("You can change every gesture later, or switch setups on the Combos page.")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            step(choosesSetup ? 3 : 2, "Check for clashes") {
                Text("If macOS uses the same gestures, both react. The Gestures page tells you which ones to switch off in Trackpad settings.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(choosesSetup ? "Get started" : "Done") { onDone(choosesSetup ? model.choice : nil) }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func step<Content: View>(_ number: Int, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.accentColor.opacity(0.18)))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                content()
            }
        }
    }

    private func choiceRow(_ setup: StartingSetup) -> some View {
        let selected = model.choice == setup
        return Button {
            model.choice = setup
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Label(setup.title, systemImage: setup.symbol).font(.body.weight(.medium))
                    Text(setup.summary).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
