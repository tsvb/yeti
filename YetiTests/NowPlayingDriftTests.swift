import XCTest

final class NowPlayingDriftTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func snap(elapsed: Double = 100, duration: Double = 3_600,
                      rate: Double = 1, isLive: Bool = false) -> NowPlayingSnapshot {
        NowPlayingSnapshot(elapsed: elapsed, duration: duration, rate: rate,
                           isLive: isLive, pushedAt: t0)
    }

    private func needs(_ last: NowPlayingSnapshot?, elapsed: Double, duration: Double = 3_600,
                       rate: Double = 1, isLive: Bool = false, after seconds: Double) -> Bool {
        NowPlayingDrift.needsPush(last: last, elapsed: elapsed, duration: duration,
                                  rate: rate, isLive: isLive,
                                  now: t0.addingTimeInterval(seconds))
    }

    func testFirstPushAlwaysGoes() {
        XCTAssertTrue(needs(nil, elapsed: 0, after: 0))
    }

    /// The point of the helper: steady playback needs no ticks at all.
    func testSteadyPlaybackIsNotRepushed() {
        XCTAssertFalse(needs(snap(), elapsed: 100.5, after: 0.5))
        XCTAssertFalse(needs(snap(), elapsed: 400, after: 300))
    }

    func testPauseOrResumeRepushes() {
        XCTAssertTrue(needs(snap(rate: 1), elapsed: 101, rate: 0, after: 1))
        XCTAssertTrue(needs(snap(rate: 0), elapsed: 100, rate: 1, after: 30))
    }

    func testPausedCardStaysPutWithoutRepush() {
        XCTAssertFalse(needs(snap(rate: 0), elapsed: 100, rate: 0, after: 600))
    }

    /// AVKit's own scrubber seeks without calling our seek(): position drift.
    func testScrubOrStallBeyondToleranceRepushes() {
        XCTAssertTrue(needs(snap(), elapsed: 900, after: 1))      // scrubbed ahead
        XCTAssertTrue(needs(snap(), elapsed: 100, after: 10))     // stalled 10s
        XCTAssertFalse(needs(snap(), elapsed: 109, after: 10))    // within 2s
    }

    func testDurationArrivingRepushes() {
        XCTAssertTrue(needs(snap(duration: 0), elapsed: 100.5, duration: 3_600, after: 0.5))
    }

    func testLiveCardRepushesOnlyOnRateOrLivenessChange() {
        let live = snap(elapsed: 0, duration: 0, isLive: true)
        XCTAssertFalse(needs(live, elapsed: 5_000, duration: 0, isLive: true, after: 1))
        XCTAssertTrue(needs(live, elapsed: 5_000, duration: 0, rate: 0, isLive: true, after: 1))
        XCTAssertTrue(needs(live, elapsed: 0, duration: 3_600, isLive: false, after: 1))
    }
}
