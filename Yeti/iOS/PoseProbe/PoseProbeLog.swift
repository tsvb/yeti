#if DEBUG
import Foundation

// The DEBUG Pose Probe's pure half: what one reading of the Duo's pose looks
// like, which readings are worth a log row, the raw hinge counters that sit
// OUTSIDE that filter, and the plain-text report Tim copies back to the Mac.
// Pure Foundation so the host-free tests can cover it; the sensors and the
// sheet are in PoseProbeView.swift.
//
// Why a probe: `onHingeChange` reports only a status and an angle — there is
// no posture enum — so "propped on a nightstand", "tent" and "half-open in a
// hand" have to be derived from hinge + gravity + which display we're on. The
// nightstand spec is written from this log, not from guesses.

/// Everything the probe knows about the device at one instant. Each field is
/// optional or defaulted because the sources arrive independently (hinge,
/// motion, window) and the simulator has no motion at all.
struct PoseSnapshot: Equatable, Sendable {
    struct Gravity: Equatable, Sendable {
        var x: Double, y: Double, z: Double
    }
    struct Size: Equatable, Sendable {
        var width: Double, height: Double
    }
    struct Insets: Equatable, Sendable {
        var top: Double, leading: Double, bottom: Double, trailing: Double
    }

    /// "closed" / "partiallyOpen" / "fullyOpen" / "unknown", or "nil" when the
    /// interaction left a hierarchy that provides hinge updates.
    var hingeStatus: String?
    var hingeDegrees: Double?
    var deviceOrientation = "?"
    var interfaceOrientation = "?"
    var gravity: Gravity?
    var window: Size?
    var safeArea: Insets?
    var screen: Size?
    var screenScale: Double?
    /// "R/C" = horizontal regular, vertical compact.
    var sizeClasses = "?"
    var battery = "?"
    var brightness: Double?
    var scenePhase = "?"
    /// Whether the probe has opened the portrait lock. Production is locked,
    /// so every row says which world its geometry came from.
    var rotationUnlocked = false
}

/// One log row: why it was written, plus the snapshot at that moment.
struct PoseSample: Equatable, Sendable {
    enum Trigger: String, Sendable, CaseIterable {
        case start
        case hingeSwiftUI = "hinge-sui"
        case hingeUIKit = "hinge-uik"
        case gravity
        case orientation
        case geometry
        case scene
        case lock
        case mark
        case poll
    }

    var time: Date
    var trigger: Trigger
    /// The pose label for a mark; free text for anything else worth saying.
    var note: String?
    var snapshot: PoseSnapshot
}

/// Raw hinge-callback counters for ONE source, kept outside the de-noise
/// filter: the log drops sub-2° moves, so the update rate and granularity
/// (spec question 1) have to be measured here.
struct HingeCounters: Equatable, Sendable {
    private(set) var callbacks = 0
    private(set) var nilCallbacks = 0
    private(set) var minDegrees: Double?
    private(set) var maxDegrees: Double?
    /// The smallest non-zero change between consecutive callbacks.
    private(set) var smallestStep: Double?
    private(set) var intervals: [TimeInterval] = []
    private var lastDegrees: Double?
    private var lastTime: Date?

    /// Cap on retained intervals — plenty for a median, bounded for a long run.
    static let intervalCap = 5_000

    mutating func record(degrees: Double?, at time: Date) {
        callbacks += 1
        if let last = lastTime {
            let gap = time.timeIntervalSince(last)
            if gap >= 0, intervals.count < Self.intervalCap { intervals.append(gap) }
        }
        lastTime = time
        guard let degrees else {
            nilCallbacks += 1
            return
        }
        minDegrees = min(minDegrees ?? degrees, degrees)
        maxDegrees = max(maxDegrees ?? degrees, degrees)
        if let previous = lastDegrees {
            let step = abs(degrees - previous)
            if step > 0 { smallestStep = min(smallestStep ?? step, step) }
        }
        lastDegrees = degrees
    }

    var medianInterval: TimeInterval? {
        guard !intervals.isEmpty else { return nil }
        let sorted = intervals.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }
}

/// The probe's log: decides which readings earn a row, keeps the counters,
/// and renders the report.
struct PoseProbeLog: Equatable, Sendable {
    /// A hinge row needs this much movement (or a status change).
    static let angleThreshold = 2.0
    /// A gravity row needs one component to move this far, in g.
    static let gravityThreshold = 0.15
    /// Hard cap on rows; the oldest non-mark rows go first.
    static let rowCap = 2_000

    private(set) var samples: [PoseSample] = []
    private(set) var swiftUICounters = HingeCounters()
    private(set) var uiKitCounters = HingeCounters()
    /// Rows the cap pushed out, reported in the header so a truncated log is
    /// never mistaken for a complete one.
    private(set) var dropped = 0

    /// The last snapshot that made it into the log, per trigger family.
    private struct HingeReading: Equatable, Sendable {
        var status: String?
        var degrees: Double?
    }
    private var lastHinge: [PoseSample.Trigger: HingeReading] = [:]
    private var lastGravity: PoseSnapshot.Gravity?
    private var lastLogged: PoseSnapshot?

    /// Offer a reading. Hinge readings always reach the counters; the row is
    /// written only when `shouldLog` says the reading says something new.
    /// Returns whether a row was written.
    @discardableResult
    mutating func offer(_ trigger: PoseSample.Trigger, _ snapshot: PoseSnapshot,
                        note: String? = nil, at time: Date) -> Bool {
        switch trigger {
        case .hingeSwiftUI: swiftUICounters.record(degrees: snapshot.hingeDegrees, at: time)
        case .hingeUIKit: uiKitCounters.record(degrees: snapshot.hingeDegrees, at: time)
        default: break
        }
        guard shouldLog(trigger, snapshot) else { return false }
        append(PoseSample(time: time, trigger: trigger, note: note, snapshot: snapshot))
        switch trigger {
        case .hingeSwiftUI, .hingeUIKit:
            lastHinge[trigger] = HingeReading(status: snapshot.hingeStatus,
                                              degrees: snapshot.hingeDegrees)
        default: break
        }
        if let g = snapshot.gravity, trigger == .gravity || lastGravity == nil { lastGravity = g }
        lastLogged = snapshot
        return true
    }

    func shouldLog(_ trigger: PoseSample.Trigger, _ snapshot: PoseSnapshot) -> Bool {
        switch trigger {
        case .start, .scene, .lock, .mark:
            return true
        case .hingeSwiftUI, .hingeUIKit:
            guard let last = lastHinge[trigger] else { return true }
            if last.status != snapshot.hingeStatus { return true }
            switch (last.degrees, snapshot.hingeDegrees) {
            case (nil, nil): return false
            case (let a?, let b?): return abs(a - b) >= Self.angleThreshold
            default: return true
            }
        case .gravity:
            guard let g = snapshot.gravity else { return false }
            guard let last = lastGravity else { return true }
            return abs(g.x - last.x) >= Self.gravityThreshold
                || abs(g.y - last.y) >= Self.gravityThreshold
                || abs(g.z - last.z) >= Self.gravityThreshold
        case .orientation:
            guard let last = lastLogged else { return true }
            return last.deviceOrientation != snapshot.deviceOrientation
                || last.interfaceOrientation != snapshot.interfaceOrientation
        case .geometry, .poll:
            guard let last = lastLogged else { return true }
            return last.window != snapshot.window
                || last.safeArea != snapshot.safeArea
                || last.screen != snapshot.screen
                || last.screenScale != snapshot.screenScale
                || last.sizeClasses != snapshot.sizeClasses
                || last.interfaceOrientation != snapshot.interfaceOrientation
                || last.deviceOrientation != snapshot.deviceOrientation
                || last.battery != snapshot.battery
                || Self.brightnessMoved(last.brightness, snapshot.brightness)
        }
    }

    mutating func clear() { self = PoseProbeLog() }

    private static func brightnessMoved(_ a: Double?, _ b: Double?) -> Bool {
        switch (a, b) {
        case (nil, nil): return false
        case (let a?, let b?): return abs(a - b) >= 0.05
        default: return true
        }
    }

    private mutating func append(_ sample: PoseSample) {
        samples.append(sample)
        guard samples.count > Self.rowCap else { return }
        // Marks are Tim's ground truth; shed anything else first.
        if let i = samples.firstIndex(where: { $0.trigger != .mark }) {
            samples.remove(at: i)
        } else {
            samples.removeFirst()
        }
        dropped += 1
    }

    // MARK: - Report

    /// The whole log as plain text: a header (who/when, the raw counters) and
    /// one line per row, times relative to the first row.
    func report(device: String, generatedAt now: Date) -> String {
        var out: [String] = []
        out.append("Yeti pose probe — \(Self.stamp(now))")
        out.append(device)
        out.append(Self.counterLine("hinge-sui (onHingeChange)", swiftUICounters))
        out.append(Self.counterLine("hinge-uik (UIHingeInteraction)", uiKitCounters))
        out.append("rows \(samples.count)" + (dropped > 0 ? " (\(dropped) older rows dropped)" : ""))
        out.append("thresholds: hinge ≥ \(Self.fmt(Self.angleThreshold, 0))°, gravity ≥ "
                   + "\(Self.fmt(Self.gravityThreshold, 2))g")
        out.append("")
        let origin = samples.first?.time ?? now
        for sample in samples {
            out.append(Self.line(sample, origin: origin))
        }
        return out.joined(separator: "\n")
    }

    static func counterLine(_ name: String, _ c: HingeCounters) -> String {
        guard c.callbacks > 0 else { return "\(name): no callbacks" }
        var parts = ["\(c.callbacks) callbacks"]
        if c.nilCallbacks > 0 { parts.append("\(c.nilCallbacks) nil") }
        if let lo = c.minDegrees, let hi = c.maxDegrees {
            parts.append("range \(fmt(lo, 1))–\(fmt(hi, 1))°")
        }
        parts.append("min step " + (c.smallestStep.map { fmt($0, 2) + "°" } ?? "—"))
        parts.append("median gap " + (c.medianInterval.map { fmt($0, 3) + "s" } ?? "—"))
        return "\(name): " + parts.joined(separator: " · ")
    }

    /// One row, key=value so it survives a paste into anything.
    static func line(_ s: PoseSample, origin: Date) -> String {
        let p = s.snapshot
        var parts: [String] = []
        parts.append("+" + fmt(s.time.timeIntervalSince(origin), 1) + "s")
        parts.append(s.trigger.rawValue)
        if let note = s.note { parts.append("\"\(note)\"") }
        let hinge = (p.hingeStatus ?? "—") + (p.hingeDegrees.map { " " + fmt($0, 1) + "°" } ?? "")
        parts.append("hinge=" + hinge)
        parts.append("dev=" + p.deviceOrientation)
        parts.append("ui=" + p.interfaceOrientation)
        parts.append("g=" + (p.gravity.map {
            "(\(signed($0.x)),\(signed($0.y)),\(signed($0.z)))"
        } ?? "—"))
        parts.append("win=" + (p.window.map(size) ?? "—"))
        parts.append("safe=" + (p.safeArea.map {
            [fmt($0.top, 0), fmt($0.leading, 0), fmt($0.bottom, 0), fmt($0.trailing, 0)]
                .joined(separator: ",")
        } ?? "—"))
        parts.append("scr=" + (p.screen.map(size) ?? "—")
                     + (p.screenScale.map { "@" + fmt($0, 0) } ?? ""))
        parts.append("cls=" + p.sizeClasses)
        parts.append("batt=" + p.battery)
        parts.append("bri=" + (p.brightness.map { fmt($0, 2) } ?? "—"))
        parts.append("phase=" + p.scenePhase)
        parts.append("lock=" + (p.rotationUnlocked ? "open" : "portrait"))
        return parts.joined(separator: " ")
    }

    private static func size(_ s: PoseSnapshot.Size) -> String {
        fmt(s.width, 0) + "×" + fmt(s.height, 0)
    }

    private static func signed(_ v: Double) -> String {
        (v >= 0 ? "+" : "") + fmt(v, 2)
    }

    static func fmt(_ v: Double, _ digits: Int) -> String {
        String(format: "%.\(digits)f", v)
    }

    private static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }
}
#endif
