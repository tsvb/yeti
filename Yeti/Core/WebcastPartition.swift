import Foundation

/// The slice of a webcast the schedule partition needs — protocol'd so the
/// pure logic tests without dragging the catalog models in. Only the feed's
/// DATES decide the rails: `VideoSummary.isLive` is the product format, true
/// for every /livestreams item, so it can't say "on air now" (reading it put
/// two weeks of finished shows ahead of today, oldest first).
protocol WebcastLike {
    var eventStart: Date? { get }
    /// Feed `endDate`: when the broadcast goes off air.
    var eventEnd: Date? { get }
    /// Feed `saleWindowEndDate`, read as when the replay window closes. That
    /// reading is inferred, not documented: free audio's window closes at the
    /// broadcast's end (no replay), free video's 1–3 days later, exclusives'
    /// and PPV's 1–2 weeks later.
    var replayEnd: Date? { get }
}

/// How long a webcast counts as on air when the feed gives no usable end.
let webcastAssumedLength: TimeInterval = 6 * 3_600

/// The longest broadcast an `endDate` can describe. PPV items carry their
/// SALE window as `endDate` (8–10 days out, equal to `saleWindowEndDate`), so
/// an end further than this from the start isn't when the show goes off air;
/// every exclusive's end sits within ~5h (live feed, 2026-11-21).
let webcastMaxLength: TimeInterval = 12 * 3_600

extension WebcastLike {
    /// The end the partition uses: the feed's when it's a plausible broadcast
    /// end, else start + the assumed length.
    var effectiveEnd: Date? {
        guard let start = eventStart else { return nil }
        if let end = eventEnd, end.timeIntervalSince(start) <= webcastMaxLength { return end }
        return start.addingTimeInterval(webcastAssumedLength)
    }

    /// Started and not yet over.
    func isOnAir(at now: Date) -> Bool {
        guard let start = eventStart, let end = effectiveEnd else { return false }
        return start <= now && now < end
    }
}

/// Split a livestream feed (queried from a couple of weeks back) into the
/// two rails the Videos page shows:
/// - `upcoming`: on air now first, then scheduled events soonest-first — so
///   the rail opens on today. Undated items stay here — before the partition
///   existed the whole feed showed under Live & Upcoming, and an item we
///   can't date shouldn't be presented as "recent".
/// - `recent`: over, newest first ("last chance" replays). An item whose
///   replay window has closed is dropped from both rails.
func partitionWebcasts<V: WebcastLike>(_ items: [V], now: Date)
    -> (upcoming: [V], recent: [V]) {
    var upcoming: [V] = []
    var recent: [V] = []
    for item in items {
        guard let start = item.eventStart else {
            upcoming.append(item)
            continue
        }
        if start > now || item.isOnAir(at: now) {
            upcoming.append(item)
        } else if (item.replayEnd ?? .distantFuture) > now {
            recent.append(item)
        }
    }
    upcoming.sort {
        let (a, b) = ($0.isOnAir(at: now), $1.isOnAir(at: now))
        if a != b { return a }
        return ($0.eventStart ?? .distantFuture) < ($1.eventStart ?? .distantFuture)
    }
    recent.sort {
        ($0.eventStart ?? .distantPast) > ($1.eventStart ?? .distantPast)
    }
    return (upcoming, recent)
}
