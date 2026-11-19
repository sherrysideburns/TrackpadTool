import AppKit
import SwiftUI
import SystemConfiguration
import UniformTypeIdentifiers

/// "Report a problem": builds a short report about this Mac and the last log
/// lines, with personal details taken out, and lets the person send it by
/// email or as a GitHub issue. Nothing is sent without them seeing it first.
enum ProblemReport {
    /// Where email reports go. Empty: the person types the address.
    static let supportEmail = ""
    static let issuesURL = AppInfo.website.appendingPathComponent("issues/new")

    /// The report text. Settings (which include app identifiers) only when asked.
    static func build(description: String, includeSettings: Bool) -> String {
        let store = SettingsStore.shared
        let s = store.settings
        let modulesOn = ModuleID.allCases.filter { store.isOn($0) }.map(\.title)
        let usedGestures = Gesture.allCases.filter { store.isUsed($0) }.count
        var lines: [String] = []
        lines.append("TrackpadTool problem report")
        lines.append("")
        lines.append("What happened:")
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append(text.isEmpty ? "(no description)" : scrub(text))
        lines.append("")
        lines.append("TrackpadTool \(AppInfo.version) (build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
        lines.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Mac model: \(macModel()) · \(NSScreen.screens.count) display(s) · \(MultitouchReader.shared.deviceCount) trackpad(s)")
        lines.append("Accessibility: \(AX.isTrusted ? "allowed" : "not allowed")")
        lines.append("Gestures: \(s.enabled ? "on" : "paused") · Advanced mode: \(s.advancedMode ? "on" : "off")")
        lines.append("Modules on: \(modulesOn.joined(separator: ", "))")
        lines.append("Gestures with an action: \(usedGestures) · per-app setups: \(s.apps.count) · keyboard shortcuts: \(s.keyShortcuts.count)")
        lines.append("Stopped unexpectedly last time: \(Log.previousSessionEndedUnexpectedly ? "yes" : "no")")
        if includeSettings, let data = try? encoder.encode(s), let json = String(data: data, encoding: .utf8) {
            lines.append("")
            lines.append("Settings:")
            lines.append(scrub(json))
        }
        lines.append("")
        lines.append("Last log lines:")
        lines.append(scrub(Log.tail(lines: 300)))
        return lines.joined(separator: "\n")
    }

    /// A shorter version that fits in a GitHub link.
    static func short(description: String) -> String {
        let full = build(description: description, includeSettings: false)
        let head = full.components(separatedBy: "\nLast log lines:")[0]
        let log = scrub(Log.tail(lines: 40))
        var body = head + "\nLast log lines:\n```\n" + log + "\n```\n\n(Shortened. You can attach the full report file here as well.)"
        if body.count > 6000 { body = String(body.suffix(6000)) }
        return body
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    /// Takes out the home folder, the user's account and full name, and the
    /// Mac's name.
    static func scrub(_ text: String) -> String {
        var out = text.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        // (Host.current() can wait on the network; these answer at once.)
        let computerName = SCDynamicStoreCopyComputerName(nil, nil) as String? ?? ""
        let localName = SCDynamicStoreCopyLocalHostName(nil) as String? ?? ""
        let personal = [NSFullUserName(), NSUserName(), computerName, localName]
        for word in personal where word.count >= 3 {
            out = out.replacingOccurrences(of: word, with: "[removed]", options: .caseInsensitive)
        }
        return out
    }

    /// The model identifier, like "Mac15,3" (not the serial number).
    private static func macModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "unknown" }
        var chars = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &chars, &size, nil, 0)
        return String(cString: chars)
    }

    /// Writes the report to a temporary file to attach.
    static func file(_ text: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TrackpadTool report.txt")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            Log.error("Couldn’t write the report file: \(error.localizedDescription)")
            return nil
        }
    }
}

/// What's typed and ticked in the report window.
final class ReportModel: ObservableObject {
    @Published var description = ""
    @Published var includeSettings = false
    @Published var showPreview = false
    @Published var message: String?

    var report: String { ProblemReport.build(description: description, includeSettings: includeSettings) }
}

struct ReportView: View {
    @StateObject private var model = ReportModel()
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Report a problem").font(.title2.weight(.semibold))
            Text("What went wrong? The more you tell, the easier it is to fix.")
                .foregroundStyle(.secondary)
            TextEditor(text: $model.description)
                .font(.body)
                .frame(height: 110)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))

            VStack(alignment: .leading, spacing: 6) {
                Text("The report also holds your TrackpadTool and macOS version, Mac model, which modules are on, and the last lines of the error log. Your name, your Mac's name and your home folder are taken out.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Include my settings (which gestures do what, and the apps with their own setup)",
                       isOn: $model.includeSettings)
                    .font(.caption)
                DisclosureGroup("See exactly what's sent", isExpanded: $model.showPreview) {
                    if model.showPreview {
                        ScrollView {
                            Text(model.report)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 180)
                    }
                }
                .font(.caption)
            }

            if let message = model.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.report, forType: .string)
                    model.message = "Report copied. Paste it in a message to the developer."
                }
                Button("Save as file…") { save() }
                Spacer()
                Button("GitHub issue…") { openIssue() }
                    .help("Needs a GitHub account with access to the TrackpadTool repository")
                Button("Email…") { email() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 560)
    }

    private func email() {
        guard let file = ProblemReport.file(model.report),
              let service = NSSharingService(named: .composeEmail) else {
            model.message = "No email app is set up. Use Copy or Save as file instead."
            return
        }
        if !ProblemReport.supportEmail.isEmpty { service.recipients = [ProblemReport.supportEmail] }
        service.subject = "TrackpadTool \(AppInfo.version): problem report"
        let text = model.description.trimmingCharacters(in: .whitespacesAndNewlines)
        service.perform(withItems: [text.isEmpty ? "The report is attached." : text, file])
        Log.info("Problem report: opened in Mail")
        onClose()
    }

    private func openIssue() {
        var parts = URLComponents(url: ProblemReport.issuesURL, resolvingAgainstBaseURL: false)
        let firstLine = model.description.split(separator: "\n").first.map(String.init) ?? ""
        parts?.queryItems = [
            URLQueryItem(name: "title", value: firstLine.isEmpty ? "Problem report (\(AppInfo.version))" : String(firstLine.prefix(80))),
            URLQueryItem(name: "body", value: ProblemReport.short(description: model.description)),
        ]
        if let url = parts?.url {
            NSWorkspace.shared.open(url)
            Log.info("Problem report: opened a GitHub issue")
            onClose()
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "TrackpadTool report.txt"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try model.report.write(to: url, atomically: true, encoding: .utf8)
                model.message = "Saved. Send the file to the developer."
            } catch {
                model.message = "Couldn’t save: \(error.localizedDescription)"
            }
        }
    }
}
