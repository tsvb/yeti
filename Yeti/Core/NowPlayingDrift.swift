import Foundation

/// What the system's Now Playing card was last told, and when. The system
/// extrapolates elapsed time from the rate on its own, so a card only needs
/// re-pushing when it would otherwise be WRONG — not on every player tick.
struct NowPlayingSnapshot: Equatable {
    var elapsed: Double
    var duration: Double
    var rate: Double
    var isLive: Bool
    var pushedAt: Date
}

enum NowPlayingDrift {
    /// How far the real position may wander from the card's extrapolation
    /// before it's re-pushed (a seek from AVKit's own controls, a stall).
    static let tolerance: Double = 2

    /// Whether a tick's state differs from what the card shows:
    /// - nothing pushed yet (or the card was handed back),
    /// - play/pause flipped, or live-ness changed,
    /// - the duration arrived or changed (VOD only),
    /// - the position drifted past `tolerance` from the extrapolated one
    ///   (VOD only — a live card carries no elapsed time).
    static func needsPush(last: NowPlayingSnapshot?,
                          elapsed: Double, duration: Double, rate: Double,
                          isLive: Bool, now: Date) -> Bool {
        guard let last else { return true }
        if last.rate != rate || last.isLive != isLive { return true }
        if isLive { return false }
        if abs(last.duration - duration) > 0.5 { return true }
        let expected = last.elapsed + now.timeIntervalSince(last.pushedAt) * last.rate
        return abs(elapsed - expected) > tolerance
    }
}
