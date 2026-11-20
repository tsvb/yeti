#if DEBUG
import CoreMotion
import SwiftUI
import UIKit

// The DEBUG Pose Probe's live half: the sensors (both hinge APIs, CoreMotion
// gravity, the window/scene geometry), the store that outlives the sheet, and
// the sheet itself. Reached from the account menu ("Pose Probe (Debug)");
// `-UITestShowPoseProbe` presents it at launch. See PoseProbeLog.swift for why.

/// Holds the log for the whole run, NOT the sheet's `@State`: folding the Duo
/// can move the scene between displays or tear the sheet down, and that is
/// exactly the moment the log must survive.
@MainActor @Observable
final class PoseProbeStore {
    static let shared = PoseProbeStore()

    struct Arm: Equatable {
        var label: String
        var fires: Date
    }

    private(set) var log = PoseProbeLog()
    private(set) var current = PoseSnapshot()
    /// A pose label waiting out its countdown (see `arm(_:)`).
    private(set) var armed: Arm?

    /// Seconds between choosing a pose and the probe stamping it — time to put
    /// the phone down and let go, so the tap never lands inside the reading.
    static let armSeconds: TimeInterval = 5

    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var armTask: Task<Void, Never>?
    @ObservationIgnored private var active = false
    @ObservationIgnored private var savedIdleTimerDisabled = false
    @ObservationIgnored private var savedBatteryMonitoring = false
    /// The sensor view, for reading its window's geometry on a poll.
    @ObservationIgnored weak var sensorView: UIView?

    private init() {}

    // MARK: - Lifecycle

    /// Idempotent: the sheet calls it on every appear, and a fold can make it
    /// reappear without a dismissal.
    func start() {
        guard !active else { return }
        active = true
        let app = UIApplication.shared
        savedIdleTimerDisabled = app.isIdleTimerDisabled
        app.isIdleTimerDisabled = true  // the screen mustn't sleep mid-pose
        let device = UIDevice.current
        savedBatteryMonitoring = device.isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = true
        // Without this, UIDevice.orientation reads .unknown forever.
        device.beginGeneratingDeviceOrientationNotifications()

        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 0.1
            motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                // Pull the plain doubles out here: CMDeviceMotion isn't Sendable.
                guard let g = data?.gravity else { return }
                let (x, y, z) = (g.x, g.y, g.z)
                MainActor.assumeIsolated { self?.gravity(x: x, y: y, z: z) }
            }
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.readGeometry(.poll)
                try? await Task.sleep(for: .seconds(1))
            }
        }
        readGeometry(.poll)
        log.offer(.start, current, note: motion.isDeviceMotionAvailable ? nil : "no device motion",
                  at: .now)
    }

    /// Only on a real dismissal (the sheet's `onDismiss`), so a fold that
    /// briefly tears the sheet down doesn't end the run.
    func stop() {
        guard active else { return }
        active = false
        motion.stopDeviceMotionUpdates()
        pollTask?.cancel()
        pollTask = nil
        armTask?.cancel()
        armTask = nil
        armed = nil
        if current.rotationUnlocked { setRotationUnlocked(false) }
        UIApplication.shared.isIdleTimerDisabled = savedIdleTimerDisabled
        UIDevice.current.isBatteryMonitoringEnabled = savedBatteryMonitoring
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    func clear() {
        log.clear()
        log.offer(.start, current, note: "cleared", at: .now)
    }

    // MARK: - Sources

    func hinge(_ source: PoseSample.Trigger, status: String?, degrees: Double?) {
        current.hingeStatus = status ?? "nil"
        current.hingeDegrees = degrees
        log.offer(source, current, note: status == nil ? "no hinge (left hierarchy?)" : nil,
                  at: .now)
    }

    private func gravity(x: Double, y: Double, z: Double) {
        current.gravity = .init(x: x, y: y, z: z)
        current.deviceOrientation = Self.name(UIDevice.current.orientation)
        log.offer(.gravity, current, at: .now)
        log.offer(.orientation, current, at: .now)
    }

    func scene(_ phase: ScenePhase) {
        current.scenePhase = switch phase {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
        readGeometry(.poll)
        log.offer(.scene, current, note: current.scenePhase, at: .now)
    }

    /// Reads everything the window and scene can say. `.geometry` from the
    /// sensor view's layout passes, `.poll` once a second as a backstop; the
    /// log drops readings that change nothing.
    func readGeometry(_ trigger: PoseSample.Trigger) {
        let device = UIDevice.current
        current.deviceOrientation = Self.name(device.orientation)
        current.battery = switch device.batteryState {
        case .charging: "charging"
        case .full: "full"
        case .unplugged: "unplugged"
        case .unknown: "unknown"
        @unknown default: "?"
        }
        if let window = sensorView?.window {
            current.window = .init(width: window.bounds.width, height: window.bounds.height)
            let s = window.safeAreaInsets
            current.safeArea = .init(top: s.top, leading: s.left, bottom: s.bottom, trailing: s.right)
            let traits = window.traitCollection
            current.sizeClasses = Self.name(traits.horizontalSizeClass) + "/"
                + Self.name(traits.verticalSizeClass)
            if let scene = window.windowScene {
                let screen = scene.screen
                current.screen = .init(width: screen.bounds.width, height: screen.bounds.height)
                current.screenScale = screen.scale
                current.brightness = screen.brightness
                current.interfaceOrientation = Self.name(scene.effectiveGeometry.interfaceOrientation)
            }
        }
        guard active else { return }
        log.offer(trigger, current, at: .now)
    }

    // MARK: - Marks

    /// Tim picks the pose BEFORE getting into it: a light tap now, then after
    /// `armSeconds` a success haptic and the mark row — so neither the tap nor
    /// the screen's position matters (in some poses it may not even be lit).
    func arm(_ label: String) {
        armTask?.cancel()
        armed = Arm(label: label, fires: .now.addingTimeInterval(Self.armSeconds))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        armTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.armSeconds))
            guard !Task.isCancelled, let self else { return }
            self.readGeometry(.poll)
            self.log.offer(.mark, self.current, note: label, at: .now)
            self.armed = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    func cancelArm() {
        armTask?.cancel()
        armTask = nil
        armed = nil
    }

    // MARK: - Rotation

    /// Opens or closes the app's portrait lock for the probe (production stays
    /// locked; the tent player will need landscape). Closing snaps back the
    /// same way the video exit does.
    func setRotationUnlocked(_ unlocked: Bool) {
        OrientationGate.poseProbeUnlocked = unlocked
        current.rotationUnlocked = unlocked
        let scene = sensorView?.window?.windowScene
        if !unlocked {
            scene?.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        }
        var vc = sensorView?.window?.rootViewController
        while let controller = vc {
            controller.setNeedsUpdateOfSupportedInterfaceOrientations()
            vc = controller.presentedViewController
        }
        log.offer(.lock, current, note: unlocked ? "rotation unlocked" : "portrait lock", at: .now)
    }

    // MARK: - Report

    func report() -> String {
        log.report(device: Self.deviceLine, generatedAt: .now)
    }

    static var deviceLine: String {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let bundle = Bundle.main.infoDictionary ?? [:]
        let short = bundle["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle["CFBundleVersion"] as? String ?? "?"
        return "\(machine) · iOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
            + " · Yeti \(short) (\(build))"
    }

    // MARK: - Names

    static func name(_ o: UIDeviceOrientation) -> String {
        switch o {
        case .portrait: "portrait"
        case .portraitUpsideDown: "upsideDown"
        case .landscapeLeft: "landscapeL"
        case .landscapeRight: "landscapeR"
        case .faceUp: "faceUp"
        case .faceDown: "faceDown"
        case .unknown: "unknown"
        @unknown default: "?"
        }
    }

    static func name(_ o: UIInterfaceOrientation) -> String {
        switch o {
        case .portrait: "portrait"
        case .portraitUpsideDown: "upsideDown"
        case .landscapeLeft: "landscapeL"
        case .landscapeRight: "landscapeR"
        case .unknown: "unknown"
        @unknown default: "?"
        }
    }

    static func name(_ c: UIUserInterfaceSizeClass) -> String {
        switch c {
        case .compact: "C"
        case .regular: "R"
        case .unspecified: "-"
        @unknown default: "?"
        }
    }

    @available(iOS 27.1, *)
    static func name(_ s: UIHinge.Status) -> String {
        switch s {
        case .closed: "closed"
        case .partiallyOpen: "partiallyOpen"
        case .fullyOpen: "fullyOpen"
        case .unknown: "unknown"
        @unknown default: "?"
        }
    }

    @available(iOS 27.1, *)
    static func name(_ s: DeviceHinge.Status) -> String {
        if s == .closed { return "closed" }
        if s == .partiallyOpen { return "partiallyOpen" }
        if s == .fullyOpen { return "fullyOpen" }
        return "unknown"
    }
}

/// A transparent view behind the sheet that carries the UIKit hinge
/// interaction (which documents an initial callback; `onHingeChange` doesn't
/// say) and reports every layout pass as a geometry reading.
@available(iOS 27.1, *)
private struct PoseProbeSensors: UIViewRepresentable {
    let store: PoseProbeStore

    func makeUIView(context: Context) -> SensorView {
        let view = SensorView()
        view.store = store
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        store.sensorView = view
        let interaction = UIHingeInteraction { [weak store] _, update in
            MainActor.assumeIsolated {
                let hinge = update.hinge
                store?.hinge(.hingeUIKit,
                             status: hinge.map { PoseProbeStore.name($0.status) },
                             degrees: hinge.map { Double($0.angle) * 180 / .pi })
            }
        }
        view.addInteraction(interaction)
        return view
    }

    func updateUIView(_ view: SensorView, context: Context) {}

    final class SensorView: UIView {
        weak var store: PoseProbeStore?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            store?.readGeometry(.geometry)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            store?.readGeometry(.geometry)
        }
    }
}

/// The probe sheet. iOS 27.1+ (both hinge APIs are new there).
@available(iOS 27.1, *)
struct PoseProbeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var copied = false
    private let store = PoseProbeStore.shared

    /// Tim's ground-truth labels. Placeholder vocabulary — "tent" in
    /// particular — to be corrected to his own words.
    static let poses = ["Closed", "Flat", "Book (propped)", "Tent", "Half-open in hand", "Other"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    readout
                    poseBlock
                    controls
                    logTail
                }
                .padding(20)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Pose Probe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .background(PoseProbeSensors(store: store))
        .onHingeChange { _, new in
            MainActor.assumeIsolated {
                store.hinge(.hingeSwiftUI,
                            status: new.hinge.map { PoseProbeStore.name($0.status) },
                            degrees: new.hinge?.angle.degrees)
            }
        }
        // A swipe while posing the phone must not end the run.
        .interactiveDismissDisabled()
        .onAppear {
            store.start()
            store.scene(scenePhase)
        }
        .onChange(of: scenePhase) { _, phase in store.scene(phase) }
    }

    // MARK: - Blocks

    private var readout: some View {
        let p = store.current
        return VStack(alignment: .leading, spacing: 6) {
            caption("Now")
            line("Hinge", (p.hingeStatus ?? "—")
                 + (p.hingeDegrees.map { "  " + PoseProbeLog.fmt($0, 1) + "°" } ?? ""))
            line("Device", p.deviceOrientation)
            line("UI", p.interfaceOrientation + "  lock " + (p.rotationUnlocked ? "open" : "portrait"))
            line("Gravity", p.gravity.map {
                [$0.x, $0.y, $0.z].map { PoseProbeLog.fmt($0, 2) }.joined(separator: "  ")
            } ?? "—")
            line("Window", p.window.map {
                PoseProbeLog.fmt($0.width, 0) + "×" + PoseProbeLog.fmt($0.height, 0)
            } ?? "—")
            line("Screen", (p.screen.map {
                PoseProbeLog.fmt($0.width, 0) + "×" + PoseProbeLog.fmt($0.height, 0)
            } ?? "—") + "  size " + p.sizeClasses)
            line("Power", p.battery + "  brightness "
                 + (p.brightness.map { PoseProbeLog.fmt($0, 2) } ?? "—"))
            line("Rows", "\(store.log.samples.count)")
        }
    }

    private var poseBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            caption("Mark a pose")
            Text("Tap the pose, then get into it. After 5 s the phone buzzes and the probe stamps it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                ForEach(Self.poses, id: \.self) { pose in
                    Button(pose) { store.arm(pose) }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                }
            }
            if let armed = store.armed {
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    let left = max(0, armed.fires.timeIntervalSince(context.date))
                    HStack {
                        Text("Stamping “\(armed.label)” in \(Int(left.rounded(.up)))…")
                            .font(.callout.weight(.semibold))
                        Spacer()
                        Button("Cancel") { store.cancelArm() }
                    }
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Unlock rotation", isOn: Binding(
                get: { store.current.rotationUnlocked },
                set: { store.setRotationUnlocked($0) }))
            HStack(spacing: 12) {
                Button(copied ? "Copied" : "Copy log") {
                    UIPasteboard.general.string = store.report()
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("Clear", role: .destructive) { store.clear() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var logTail: some View {
        let samples = store.log.samples
        let origin = samples.first?.time ?? .now
        return VStack(alignment: .leading, spacing: 4) {
            caption("Latest rows")
            ForEach(Array(samples.suffix(40).reversed().enumerated()), id: \.offset) { _, sample in
                Text(PoseProbeLog.line(sample, origin: origin))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(sample.trigger == .mark ? .primary : .secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func line(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name)
                .font(.caption.weight(.semibold))
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}
#endif
