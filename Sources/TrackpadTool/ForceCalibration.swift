import AppKit
import SwiftUI

/// Measures the trackpad pressure at which macOS gives its force-click buzz.
/// TrackpadTool can't see that moment in other apps, but its own window gets
/// the real force-click stages, so you force click on a pad here a few times.
final class ForceCalibration: ObservableObject {
    /// While calibrating, force presses don't run their action.
    static var isActive = false

    static let needed = 3

    /// Pressure when macOS force-clicked (stage 2), one per force click.
    @Published private(set) var samples: [Float] = []
    /// Pressure of the normal click (stage 1), for comparison.
    @Published private(set) var clickSamples: [Float] = []
    @Published private(set) var stage = 0

    func begin() {
        ForceCalibration.isActive = true
        MultitouchReader.shared.start()
        Log.breadcrumb("Force press calibration started")
    }

    func end() {
        ForceCalibration.isActive = false
        // Stops reading the trackpad again if nothing else needs it.
        GestureEngine.shared.reconfigure()
    }

    func reset() {
        samples = []
        clickSamples = []
    }

    func stageChanged(to newStage: Int) {
        let pressure = MultitouchReader.shared.currentTouches.map { $0.point.pressure }.max() ?? 0
        if newStage >= 1 && stage == 0 && pressure > 0 {
            clickSamples.append(pressure)
        }
        if newStage >= 2 && stage < 2 && pressure > 0 && samples.count < Self.needed {
            samples.append(pressure)
        }
        if stage != newStage { stage = newStage }   // not on every pressure reading
    }

    /// The pressure to use: the middle reading, a touch lower because the
    /// reading arrives just after macOS has already clicked.
    var result: Float? {
        guard samples.count >= Self.needed else { return nil }
        return samples.sorted()[samples.count / 2] * 0.97
    }

    var averageClick: Float? {
        clickSamples.isEmpty ? nil : clickSamples.reduce(0, +) / Float(clickSamples.count)
    }
}

/// A view that receives force-click stages.
final class PressurePadView: NSView {
    var onStage: ((Int) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { onStage?(0) }
    override func pressureChange(with event: NSEvent) { onStage?(event.stage) }
}

struct PressurePad: NSViewRepresentable {
    let onStage: (Int) -> Void

    func makeNSView(context: Context) -> PressurePadView {
        let view = PressurePadView()
        view.onStage = onStage
        return view
    }

    func updateNSView(_ view: PressurePadView, context: Context) {
        view.onStage = onStage
    }
}

struct ForceCalibrationSheet: View {
    @StateObject private var model = ForceCalibration()
    /// The measured pressure, or nil when cancelled.
    let close: (Float?) -> Void

    init(close: @escaping (Float?) -> Void) {
        self.close = close
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Match macOS’s force click").font(.system(size: 17, weight: .semibold))
                Text("Force click on the pad \(ForceCalibration.needed) times: press on until you feel the deeper second click. TrackpadTool notes the pressure at that moment, so your force press action happens together with that buzz.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.opacity(model.stage >= 2 ? 0.35 : model.stage == 1 ? 0.2 : 0.1))
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5)
                PressurePad { stage in model.stageChanged(to: stage) }
                VStack(spacing: 8) {
                    Image(systemName: "hand.point.up.braille")
                        .font(.system(size: 34))
                        .foregroundStyle(Color.accentColor)
                    Text(model.stage >= 2 ? "Force click!" : model.stage == 1 ? "Click… now press harder" : "Force click here")
                        .font(.system(size: 13, weight: .medium))
                }
                .allowsHitTesting(false)
            }
            .frame(height: 170)

            HStack(spacing: 8) {
                ForEach(0..<ForceCalibration.needed, id: \.self) { i in
                    Image(systemName: i < model.samples.count ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(i < model.samples.count ? Color.accentColor : Color.secondary)
                }
                Text("\(model.samples.count) of \(ForceCalibration.needed)")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                if !model.samples.isEmpty {
                    Button("Start over") { model.reset() }.buttonStyle(.link)
                }
            }

            if let result = model.result {
                Text("macOS force-clicks at about \(Int(result.rounded())) on this trackpad\(model.averageClick.map { "; a normal click is about \(Int($0.rounded()))" } ?? ""). Force press will use that from now on (“Force needed: Match macOS”).")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { close(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Use this") { close(model.result) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.result == nil)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { model.begin() }
        .onDisappear { model.end() }
    }
}
