import Foundation

/// Turns raw touch frames into gestures:
/// - 3/4-finger swipes (plus "steps" while fingers keep moving sideways,
///   used to browse a switcher)
/// - TipTap: one finger resting, a second finger taps beside it
/// - Edge swipes: two fingers starting at an edge, moving inward
/// Clicks, corner clicks and force press come from the click watcher instead.
final class GestureRecognizer {
    enum Event {
        case trigger(Gesture)
        case step(Int)          // +1 = moved right, -1 = moved left
        case ended              // all fingers lifted after a swipe
    }

    var onEvent: ((Event) -> Void)?

    /// Only look for these when a gesture of that kind is in use.
    var detectTipTap = false
    var detectEdges = false

    /// How far the fingers must travel (fraction of the trackpad) to count as a swipe.
    var swipeThreshold: Float = 0.10
    /// Sideways travel for each extra step in a switcher.
    var stepDistance: Float = 0.07

    private struct Track {
        var startX: Float, startY: Float, startTime: Double
        var x: Float, y: Float
    }
    private var tracks: [Int32: Track] = [:]

    // Multi-finger swipe state
    private var activeCount = 0
    private var anchor = (x: Float(0), y: Float(0))
    private var sessionFingers = 0
    private var fired = false
    private var horizontal = false
    private var stepAnchorX: Float = 0
    private var dead = false

    // TipTap state
    private var tipRest: Int32?
    private var tipFinger: Int32?
    private var tipStart: Double = 0
    private var tipRestPos = (x: Float(0), y: Float(0))

    // Edge swipe state
    private var edgeCandidate: Gesture?
    private var edgeStart = (x: Float(0), y: Float(0))
    private var edgeFired = false

    func process(_ points: [TouchPoint], timestamp t: Double) {
        let ids = Set(points.map { $0.id })
        let previous = Set(tracks.keys)
        let added = ids.subtracting(previous)
        let removed = previous.subtracting(ids)
        for p in points {
            if var tr = tracks[p.id] {
                tr.x = p.x; tr.y = p.y
                tracks[p.id] = tr
            } else {
                tracks[p.id] = Track(startX: p.x, startY: p.y, startTime: t, x: p.x, y: p.y)
            }
        }

        if detectTipTap { tipTapStep(points, added: added, removed: removed, t: t) }
        if detectEdges { edgeStep(points, added: added, t: t) }
        swipeStep(points)

        for id in removed { tracks[id] = nil }
    }

    // MARK: TipTap

    private func tipTapStep(_ points: [TouchPoint], added: Set<Int32>, removed: Set<Int32>, t: Double) {
        let n = points.count
        if tipFinger == nil {
            // A second finger lands while the first has been resting for a moment.
            if n == 2, added.count == 1, let newID = added.first,
               let rest = points.first(where: { $0.id != newID }),
               let restTrack = tracks[rest.id], t - restTrack.startTime > 0.15 {
                tipRest = rest.id
                tipFinger = newID
                tipStart = t
                tipRestPos = (rest.x, rest.y)
            }
            return
        }
        guard let tap = tipFinger, let restID = tipRest else { return }

        if n == 1, removed.contains(tap), let rest = points.first, rest.id == restID {
            // The tapping finger lifted quickly, without sliding; the resting one stayed put.
            if let tapTrack = tracks[tap], t - tipStart < 0.35,
               distance(tapTrack.x - tapTrack.startX, tapTrack.y - tapTrack.startY) < 0.05,
               distance(rest.x - tipRestPos.x, rest.y - tipRestPos.y) < 0.03 {
                onEvent?(.trigger(tapTrack.startX < rest.x ? .tipTapLeft : .tipTapRight))
            }
            resetTipTap()
        } else if n != 2 || !points.contains(where: { $0.id == restID }) || t - tipStart > 0.5 {
            resetTipTap()
        }
    }

    private func resetTipTap() {
        tipRest = nil
        tipFinger = nil
    }

    // MARK: Edge swipes

    private func edgeStep(_ points: [TouchPoint], added: Set<Int32>, t: Double) {
        let n = points.count
        if n != 2 {
            edgeCandidate = nil
            if n == 0 { edgeFired = false }
            return
        }
        let c = centroid(points)

        if edgeCandidate == nil && !edgeFired && !added.isEmpty {
            // Both fingers must land together, near one edge.
            let starts = points.compactMap { tracks[$0.id]?.startTime }
            if let first = starts.min(), let last = starts.max(), last - first < 0.2, t - first < 0.25 {
                let margin: Float = 0.10
                var best: (gesture: Gesture, distance: Float)?
                func consider(_ g: Gesture, _ d: Float) {
                    if d < margin, best == nil || d < best!.distance { best = (g, d) }
                }
                consider(.edgeLeft, c.x)
                consider(.edgeRight, 1 - c.x)
                consider(.edgeTop, 1 - c.y)
                consider(.edgeBottom, c.y)
                edgeCandidate = best?.gesture
                edgeStart = c
            }
        }

        guard let candidate = edgeCandidate, !edgeFired else { return }
        let dx = c.x - edgeStart.x, dy = c.y - edgeStart.y
        var along: Float = dy, across: Float = dx      // bottom edge: moving up
        switch candidate {
        case .edgeLeft: along = dx; across = dy
        case .edgeRight: along = -dx; across = dy
        case .edgeTop: along = -dy; across = dx
        default: break
        }
        if along > 0.12 && along > abs(across) * 1.5 {
            edgeFired = true
            edgeCandidate = nil
            onEvent?(.trigger(candidate))
        }
    }

    // MARK: Three/four-finger swipes

    private func swipeStep(_ points: [TouchPoint]) {
        let n = points.count

        if n == 0 {
            if fired { onEvent?(.ended) }
            resetSwipe()
            return
        }
        if dead { return }
        if n > 4 {
            // Five fingers: not ours. Ignore until all fingers lift.
            dead = true
            return
        }

        let c = centroid(points)

        if n != activeCount {
            // Finger count changed: re-anchor so the centroid jump isn't read as movement.
            activeCount = n
            anchor = c
            stepAnchorX = c.x
            if !fired { sessionFingers = n }
            return
        }

        guard sessionFingers == 3 || sessionFingers == 4 else { return }

        if horizontal {
            let dx = c.x - stepAnchorX
            if abs(dx) >= stepDistance {
                onEvent?(.step(dx > 0 ? 1 : -1))
                stepAnchorX = c.x
            }
            return
        }
        if fired { return }

        let dx = c.x - anchor.x
        let dy = c.y - anchor.y
        if abs(dx) > swipeThreshold && abs(dx) > abs(dy) * 1.5 {
            fired = true
            horizontal = true
            stepAnchorX = c.x
            if let g = Gesture.swipe(fingers: sessionFingers, dx: dx, dy: dy, horizontal: true) {
                onEvent?(.trigger(g))
            }
        } else if abs(dy) > swipeThreshold && abs(dy) > abs(dx) * 1.5 {
            fired = true
            if let g = Gesture.swipe(fingers: sessionFingers, dx: dx, dy: dy, horizontal: false) {
                onEvent?(.trigger(g))
            }
        }
    }

    private func resetSwipe() {
        activeCount = 0
        sessionFingers = 0
        fired = false
        horizontal = false
        dead = false
    }

    // MARK: Helpers

    private func centroid(_ points: [TouchPoint]) -> (x: Float, y: Float) {
        var x: Float = 0, y: Float = 0
        for p in points { x += p.x; y += p.y }
        let n = Float(points.count)
        return (x / n, y / n)
    }

    private func distance(_ dx: Float, _ dy: Float) -> Float {
        (dx * dx + dy * dy).squareRoot()
    }
}
