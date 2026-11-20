#if DEBUG
import XCTest

final class PoseProbeLogTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func hinge(_ status: String?, _ degrees: Double?) -> PoseSnapshot {
        var s = PoseSnapshot()
        s.hingeStatus = status
        s.hingeDegrees = degrees
        return s
    }

    // MARK: - Hinge de-noising

    func testFirstHingeReadingAlwaysLogs() {
        var log = PoseProbeLog()
        XCTAssertTrue(log.offer(.hingeUIKit, hinge("partiallyOpen", 90), at: t0))
    }

    func testSmallAngleMovesAreDroppedButCounted() {
        var log = PoseProbeLog()
        log.offer(.hingeUIKit, hinge("partiallyOpen", 90), at: t0)
        XCTAssertFalse(log.offer(.hingeUIKit, hinge("partiallyOpen", 91), at: t0 + 0.1))
        XCTAssertFalse(log.offer(.hingeUIKit, hinge("partiallyOpen", 91.5), at: t0 + 0.2))
        XCTAssertTrue(log.offer(.hingeUIKit, hinge("partiallyOpen", 92), at: t0 + 0.3),
                      "2° from the last LOGGED angle, not the last reading")
        XCTAssertEqual(log.samples.count, 2)
        XCTAssertEqual(log.uiKitCounters.callbacks, 4, "the counters see every callback")
        XCTAssertEqual(log.uiKitCounters.smallestStep ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(log.uiKitCounters.medianInterval ?? -1, 0.1, accuracy: 1e-6)
    }

    func testStatusChangeLogsEvenWithoutAngleMove() {
        var log = PoseProbeLog()
        log.offer(.hingeUIKit, hinge("partiallyOpen", 179.5), at: t0)
        XCTAssertTrue(log.offer(.hingeUIKit, hinge("fullyOpen", 180), at: t0 + 1))
    }

    func testNilHingeIsItsOwnRow() {
        var log = PoseProbeLog()
        log.offer(.hingeUIKit, hinge("closed", 0), at: t0)
        XCTAssertTrue(log.offer(.hingeUIKit, hinge("nil", nil), at: t0 + 1))
        XCTAssertEqual(log.uiKitCounters.nilCallbacks, 1)
    }

    func testTheTwoHingeSourcesAreFilteredAndCountedSeparately() {
        var log = PoseProbeLog()
        log.offer(.hingeUIKit, hinge("partiallyOpen", 90), at: t0)
        XCTAssertTrue(log.offer(.hingeSwiftUI, hinge("partiallyOpen", 90), at: t0),
                      "the SwiftUI source's first reading is new for it")
        XCTAssertEqual(log.uiKitCounters.callbacks, 1)
        XCTAssertEqual(log.swiftUICounters.callbacks, 1)
    }

    // MARK: - Gravity, geometry, marks

    func testGravityNeedsAMeaningfulMove() {
        var log = PoseProbeLog()
        var s = PoseSnapshot()
        s.gravity = .init(x: 0, y: -1, z: 0)
        XCTAssertTrue(log.offer(.gravity, s, at: t0))
        s.gravity = .init(x: 0.1, y: -0.95, z: 0.05)
        XCTAssertFalse(log.offer(.gravity, s, at: t0 + 0.1))
        s.gravity = .init(x: 0.2, y: -0.95, z: 0.05)
        XCTAssertTrue(log.offer(.gravity, s, at: t0 + 0.2))
    }

    func testNoGravityNeverLogsAGravityRow() {
        var log = PoseProbeLog()
        XCTAssertFalse(log.offer(.gravity, PoseSnapshot(), at: t0), "the simulator has no motion")
    }

    func testPollLogsOnlyChanges() {
        var log = PoseProbeLog()
        var s = PoseSnapshot()
        s.window = .init(width: 951, height: 669)
        XCTAssertTrue(log.offer(.poll, s, at: t0))
        XCTAssertFalse(log.offer(.poll, s, at: t0 + 1))
        s.window = .init(width: 390, height: 844)
        XCTAssertTrue(log.offer(.geometry, s, at: t0 + 2), "a fold to the outer display")
        s.rotationUnlocked = true
        XCTAssertTrue(log.offer(.lock, s, note: "rotation unlocked", at: t0 + 3))
    }

    func testMarksAndScenesAlwaysLog() {
        var log = PoseProbeLog()
        let s = PoseSnapshot()
        XCTAssertTrue(log.offer(.mark, s, note: "Tent", at: t0))
        XCTAssertTrue(log.offer(.mark, s, note: "Tent", at: t0))
        XCTAssertTrue(log.offer(.scene, s, note: "inactive", at: t0))
        XCTAssertTrue(log.offer(.sensor, s, note: "sensor detached", at: t0))
    }

    func testTheCapShedsNonMarksFirst() {
        var log = PoseProbeLog()
        log.offer(.mark, PoseSnapshot(), note: "Flat", at: t0)
        for i in 0..<PoseProbeLog.rowCap {
            log.offer(.scene, PoseSnapshot(), at: t0 + Double(i))
        }
        XCTAssertEqual(log.samples.count, PoseProbeLog.rowCap)
        XCTAssertEqual(log.samples.first?.note, "Flat", "the mark survives")
        XCTAssertEqual(log.dropped, 1)
    }

    // MARK: - Report

    func testReportCarriesCountersAndOneLinePerRow() {
        var log = PoseProbeLog()
        var s = hinge("partiallyOpen", 112.4)
        s.gravity = .init(x: 0.01, y: -0.98, z: 0.12)
        s.window = .init(width: 951, height: 669)
        log.offer(.hingeUIKit, s, at: t0)
        log.offer(.mark, s, note: "Book (propped)", at: t0 + 12.3)
        let text = log.report(device: "iPhone19,1 · iOS 27.2.0 · Yeti 1.6 (7)", generatedAt: t0 + 20)
        let lines = text.components(separatedBy: "\n")
        XCTAssertEqual(lines[1], "iPhone19,1 · iOS 27.2.0 · Yeti 1.6 (7)")
        XCTAssertTrue(lines[2].hasPrefix("hinge-sui (onHingeChange): no callbacks"))
        XCTAssertTrue(lines[3].contains("1 callbacks"))
        XCTAssertTrue(lines[3].contains("range 112.4–112.4°"))
        let mark = lines.last ?? ""
        XCTAssertTrue(mark.hasPrefix("+12.3s mark \"Book (propped)\" hinge=partiallyOpen 112.4°"), mark)
        XCTAssertTrue(mark.contains("g=(+0.01,-0.98,+0.12)"), mark)
        XCTAssertTrue(mark.contains("win=951×669"), mark)
        XCTAssertTrue(mark.hasSuffix("lock=portrait"), mark)
    }
}
#endif
