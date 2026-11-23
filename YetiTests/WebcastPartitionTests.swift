import XCTest

final class WebcastPartitionTests: XCTestCase {

    private struct Cast: WebcastLike, Equatable {
        let name: String
        let eventStart: Date?
        var eventEnd: Date? = nil
        var replayEnd: Date? = nil
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func days(_ d: Double) -> Date { now.addingTimeInterval(d * 86_400) }
    private func hours(_ h: Double) -> Date { now.addingTimeInterval(h * 3_600) }

    func testFutureEventsAreUpcomingSoonestFirst() {
        let items = [
            Cast(name: "later", eventStart: days(5), eventEnd: days(5.2)),
            Cast(name: "sooner", eventStart: days(1), eventEnd: days(1.2)),
        ]
        let split = partitionWebcasts(items, now: now)
        XCTAssertEqual(split.upcoming.map(\.name), ["sooner", "later"])
        XCTAssertTrue(split.recent.isEmpty)
    }

    func testEndedEventsAreRecentNewestFirst() {
        let items = [
            Cast(name: "older", eventStart: days(-10), eventEnd: days(-9.8)),
            Cast(name: "newer", eventStart: days(-1), eventEnd: days(-0.8)),
        ]
        let split = partitionWebcasts(items, now: now)
        XCTAssertTrue(split.upcoming.isEmpty)
        XCTAssertEqual(split.recent.map(\.name), ["newer", "older"])
    }

    func testOnAirIsUpcomingAndLeadsTheRail() {
        let items = [
            Cast(name: "tonight", eventStart: hours(5), eventEnd: hours(9)),
            Cast(name: "on-air", eventStart: hours(-1), eventEnd: hours(2)),
        ]
        let split = partitionWebcasts(items, now: now)
        XCTAssertEqual(split.upcoming.map(\.name), ["on-air", "tonight"])
        XCTAssertTrue(split.recent.isEmpty)
    }

    /// The real feed's shape, which the old partition got wrong: two weeks of
    /// finished shows plus the schedule, queried oldest-first. Today has to
    /// lead Live & Upcoming; the finished shows go to Just streamed.
    func testFeedFromTwoWeeksBackOpensOnToday() {
        let items = [
            Cast(name: "nov-7", eventStart: days(-14), eventEnd: days(-13.8), replayEnd: days(1)),
            Cast(name: "last-night", eventStart: hours(-20), eventEnd: hours(-16), replayEnd: days(9)),
            Cast(name: "on-air", eventStart: hours(-1), eventEnd: hours(2)),
            Cast(name: "next-week", eventStart: days(7), eventEnd: days(7.2)),
        ]
        let split = partitionWebcasts(items, now: now)
        XCTAssertEqual(split.upcoming.map(\.name), ["on-air", "next-week"])
        XCTAssertEqual(split.recent.map(\.name), ["last-night", "nov-7"])
    }

    func testEndedPastItsReplayWindowIsDropped() {
        let items = [
            Cast(name: "closed", eventStart: days(-13), eventEnd: days(-12.8), replayEnd: days(-11)),
            Cast(name: "open", eventStart: days(-2), eventEnd: days(-1.8), replayEnd: days(3)),
            Cast(name: "no-window", eventStart: days(-3), eventEnd: days(-2.8)),
        ]
        let split = partitionWebcasts(items, now: now)
        XCTAssertTrue(split.upcoming.isEmpty)
        XCTAssertEqual(split.recent.map(\.name), ["open", "no-window"])
    }

    func testReplayWindowDoesNotHideAnUpcomingShow() {
        // A sale window that has already closed on a future show is a feed
        // oddity, not a reason to hide the show.
        let items = [Cast(name: "future", eventStart: days(2), eventEnd: days(2.2), replayEnd: days(-1))]
        XCTAssertEqual(partitionWebcasts(items, now: now).upcoming.map(\.name), ["future"])
    }

    func testMissingEndAssumesAShowLength() {
        let items = [
            Cast(name: "started-an-hour-ago", eventStart: hours(-1)),
            Cast(name: "started-yesterday", eventStart: days(-1)),
        ]
        let split = partitionWebcasts(items, now: now)
        XCTAssertEqual(split.upcoming.map(\.name), ["started-an-hour-ago"])
        XCTAssertEqual(split.recent.map(\.name), ["started-yesterday"])
    }

    /// PPV items carry their sale window as `endDate` (days out). Last night's
    /// PPV is over, not on air for a week ahead of tonight's show.
    func testSaleWindowEndDateIsNotABroadcastEnd() {
        let items = [
            Cast(name: "tonight", eventStart: hours(3), eventEnd: hours(7)),
            Cast(name: "last-night-ppv", eventStart: hours(-20), eventEnd: days(9), replayEnd: days(9)),
        ]
        let split = partitionWebcasts(items, now: now)
        XCTAssertEqual(split.upcoming.map(\.name), ["tonight"])
        XCTAssertEqual(split.recent.map(\.name), ["last-night-ppv"])

        let tonightPPV = Cast(name: "ppv-on-air", eventStart: hours(-1), eventEnd: days(9))
        XCTAssertTrue(tonightPPV.isOnAir(at: now))
    }

    func testNilStartDateStaysUpcoming() {
        // Odd feed items without a schedule keep the pre-partition behavior
        // (they were always shown under Live & Upcoming), after the dated ones.
        let items = [
            Cast(name: "undated", eventStart: nil),
            Cast(name: "tomorrow", eventStart: days(1), eventEnd: days(1.2)),
        ]
        let split = partitionWebcasts(items, now: now)
        XCTAssertEqual(split.upcoming.map(\.name), ["tomorrow", "undated"])
        XCTAssertTrue(split.recent.isEmpty)
    }
}
