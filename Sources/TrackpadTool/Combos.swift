import AppKit

/// A combo (saved or shared setup) is made of parts. You choose which parts
/// go into an exported combo, and which parts of a combo to use.
enum ComboPart: String, CaseIterable, Identifiable, Codable {
    case threeFingers, fourFingers, tipTap, edgeSwipes, cornerClicks, forcePress, stageManager, perApp, shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .threeFingers: return "Three fingers"
        case .fourFingers: return "Four fingers"
        case .tipTap: return "TipTap"
        case .edgeSwipes: return "Edge swipes"
        case .cornerClicks: return "Corner clicks"
        case .forcePress: return "Force press"
        case .stageManager: return "Stage Manager"
        case .perApp: return "Per-app setups"
        case .shortcuts: return "Keyboard shortcuts"
        }
    }

    var symbol: String {
        switch self {
        case .threeFingers: return "3.square"
        case .fourFingers: return "4.square"
        case .tipTap: return "hand.tap"
        case .edgeSwipes: return "rectangle.portrait.and.arrow.right"
        case .cornerClicks: return "square.dashed"
        case .forcePress: return "hand.point.up.braille"
        case .stageManager: return "squares.leading.rectangle"
        case .perApp: return "app.badge"
        case .shortcuts: return "command"
        }
    }

    /// The gestures this part holds (Stage Manager and per-app parts hold
    /// their own copies of any gesture).
    var group: GestureGroup? {
        switch self {
        case .threeFingers: return .threeFingers
        case .fourFingers: return .fourFingers
        case .tipTap: return .tipTap
        case .edgeSwipes: return .edgeSwipes
        case .cornerClicks: return .cornerClicks
        case .forcePress: return .forcePress
        case .stageManager, .perApp, .shortcuts: return nil
        }
    }

    var gestures: [Gesture] { group?.gestures ?? [] }

    /// The module that makes this kind of gesture or setup work.
    var module: ModuleID? {
        switch self {
        case .stageManager: return .stageManager
        case .perApp: return .perAppGestures
        case .shortcuts: return nil
        default: return group?.module
        }
    }

}

extension ProfileFile {
    /// The parts this file holds. Files from before 0.7 hold everything they
    /// have content for (every gesture group counts: a missing gesture there
    /// means "macOS default").
    var partSet: Set<ComboPart> {
        if let parts = parts {
            return Set(parts.compactMap(ComboPart.init(rawValue:)))
        }
        var set = Set(ComboPart.allCases.filter { $0.group != nil })
        if stageSetOn == true || !(stageBindings ?? [:]).isEmpty { set.insert(.stageManager) }
        if !apps.isEmpty { set.insert(.perApp) }
        if !(keyShortcuts ?? []).isEmpty { set.insert(.shortcuts) }
        return set
    }

    /// Parts in a fixed, readable order.
    var orderedParts: [ComboPart] {
        let parts = partSet   // worked out once, not once per part
        return ComboPart.allCases.filter { parts.contains($0) }
    }

    /// How many gestures (or apps) a part sets.
    func count(_ part: ComboPart) -> Int {
        switch part {
        case .stageManager:
            return (stageBindings ?? [:]).count
        case .perApp:
            return apps.count
        case .shortcuts:
            return (keyShortcuts ?? []).filter { $0.shortcut != nil && $0.action.kind != .macDefault }.count
        default:
            return part.gestures.filter { (bindings[$0.key]?.kind ?? .macDefault) != .macDefault }.count
        }
    }

    func hasContent(_ part: ComboPart) -> Bool {
        if count(part) > 0 { return true }
        switch part {
        case .cornerClicks: return !(cornerSizes ?? [:]).isEmpty
        case .stageManager: return stageSetOn == true
        default: return false
        }
    }

    /// Modules the combo needs: the kinds of gestures it uses and the
    /// modules of every action in it.
    var neededModules: [ModuleID] {
        var needed = Set<ModuleID>()
        for part in partSet where hasContent(part) {
            if let m = part.module { needed.insert(m) }
        }
        var configs = Array(bindings.values) + Array((stageBindings ?? [:]).values)
        for app in apps.values { configs += Array(app.bindings.values) }
        configs += (keyShortcuts ?? []).map(\.action)
        for c in configs where c.kind != .macDefault {
            if let m = c.kind.module { needed.insert(m) }
        }
        return ModuleID.allCases.filter { needed.contains($0) }
    }

    /// A copy holding only the given parts.
    func keeping(_ wanted: Set<ComboPart>) -> ProfileFile {
        let keep = wanted.intersection(partSet)
        var f = self
        let gestureKeys = Set(keep.flatMap { $0.gestures.map(\.key) })
        f.bindings = bindings.filter { gestureKeys.contains($0.key) }
        f.cornerSizes = keep.contains(.cornerClicks) ? cornerSizes : nil
        if !keep.contains(.stageManager) {
            f.stageSetOn = nil
            f.stageBindings = nil
        }
        if !keep.contains(.perApp) { f.apps = [:] }
        if !keep.contains(.shortcuts) { f.keyShortcuts = nil }
        f.parts = ComboPart.allCases.filter { keep.contains($0) }.map(\.rawValue)
        // A complete combo keeps every module switch; a partial one only
        // records the modules it needs.
        if keep != Set(ComboPart.allCases) {
            f.modules = Dictionary(uniqueKeysWithValues: f.neededModules.map { ($0.rawValue, true) })
        }
        return f
    }

    /// "Corner clicks (4, sizes) · Three fingers (3)"
    func describe(_ part: ComboPart) -> String {
        switch part {
        case .perApp:
            let n = count(part)
            let missing = apps.keys.filter { !AppPresence.isInstalled($0) }.count
            return "\(part.title) (\(n) app\(n == 1 ? "" : "s")\(missing > 0 ? ", \(missing) not on this Mac" : ""))"
        case .cornerClicks:
            let n = count(part)
            let sizes = (cornerSizes ?? [:]).isEmpty ? "" : ", sizes"
            return "\(part.title) (\(n)\(sizes))"
        case .stageManager:
            return "\(part.title) (\(count(part)) gesture\(count(part) == 1 ? "" : "s"))"
        default:
            return "\(part.title) (\(count(part)))"
        }
    }

    /// One line for lists and the export sheet.
    var contentsSummary: String {
        let parts = orderedParts.filter { hasContent($0) }
        if parts.isEmpty { return "Holds nothing yet: every gesture stays macOS default." }
        var text = "Holds " + parts.map(describe).joined(separator: " · ") + "."
        let modules = neededModules
        if !modules.isEmpty { text += " Needs " + modules.map(\.title).joined(separator: ", ") + "." }
        return text
    }
}
