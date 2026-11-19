import AppKit
import SwiftUI

// Short confirmation bubble (e.g. "Stage Manager on"), shown near the
// bottom of the screen for about a second.

final class GlassHUD {
    static let shared = GlassHUD()

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    private init() {}

    func show(symbol: String, text: String) {
        let host = NSHostingView(rootView: HUDView(symbol: symbol, text: text))
        let size = host.fittingSize

        if panel == nil {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.isFloatingPanel = true
            p.level = .popUpMenu
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = true
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel = p
        }
        guard let panel = panel else { return }
        panel.contentView = host

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.minY + frame.height * 0.14,
                              width: size.width, height: size.height), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                self?.panel?.animator().alphaValue = 0
            }, completionHandler: {
                self?.panel?.orderOut(nil)
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }
}

private struct HUDView: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(text).font(.system(size: 14, weight: .semibold))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
        .padding(12)
    }
}
