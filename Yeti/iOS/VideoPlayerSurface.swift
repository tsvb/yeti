import AVKit
import SwiftUI

/// iOS counterpart of the Mac AVPlayerView wrapper: native transport,
/// fullscreen, AirPlay, and PiP via AVPlayerViewController. Same call
/// signature as the macOS VideoPlayerSurface so VideoDetailView stays shared.
///
/// Orientation contract (the YouTube pattern): the app itself is locked to
/// portrait (see OrientationGate); entering video fullscreen opens the gate
/// so the presentation can rotate to landscape, and exiting closes it and
/// snaps the interface back to portrait. The delegate also keeps playback
/// running across the exit transition — AVKit pauses it by default.
///
/// It also reports full screen to `VideoPlayerService` (as the Mac surface
/// does). On iOS that matters more than on the Mac: AVKit's full-screen
/// presentation covers the video page, which fires the page's `onDisappear`
/// — and that stops playback unless the page can see it's only full screen.
struct VideoPlayerSurface: UIViewControllerRepresentable {
    let player: AVPlayer

    @Environment(AppModel.self) private var app

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        context.coordinator.video = app.video
        let vc = AVPlayerViewController()
        vc.player = player
        vc.delegate = context.coordinator
        vc.allowsPictureInPicturePlayback = true
        // Concert videos keep playing in PiP when the user swipes home,
        // matching how the audio side keeps playing in the background.
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        // A finished video shouldn't strand the user in a black fullscreen.
        vc.exitsFullScreenWhenPlaybackEnds = true
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        context.coordinator.video = app.video
        if vc.player !== player { vc.player = player }
    }

    // @preconcurrency: the delegate protocol predates actor annotations;
    // AVKit delivers these callbacks on the main thread, and the runtime
    // check enforces it.
    @MainActor
    final class Coordinator: NSObject, @preconcurrency AVPlayerViewControllerDelegate {
        weak var video: VideoPlayerService?

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willBeginFullScreenPresentationWithAnimationCoordinator
            coordinator: any UIViewControllerTransitionCoordinator
        ) {
            // Set BEFORE the transition: the page's onDisappear fires during
            // it and must already see full screen.
            video?.setFullScreen(true)
            OrientationGate.videoFullscreen = true
            playerViewController.setNeedsUpdateOfSupportedInterfaceOrientations()
            coordinator.animate(alongsideTransition: nil) { [weak self] context in
                MainActor.assumeIsolated {
                    guard context.isCancelled else { return }
                    self?.video?.setFullScreen(false)
                    OrientationGate.videoFullscreen = false
                    playerViewController.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
            }
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willEndFullScreenPresentationWithAnimationCoordinator
            coordinator: any UIViewControllerTransitionCoordinator
        ) {
            // AVKit pauses on exit-fullscreen by default; if the video was
            // playing, keep it playing inline after the transition settles.
            let player = playerViewController.player
            let wasPlaying = (player?.rate ?? 0) > 0
            coordinator.animate(alongsideTransition: nil) { [weak self] context in
                MainActor.assumeIsolated {
                    // A swipe-down the viewer abandoned calls willEnd too, then
                    // cancels: still full screen, so leave everything as is.
                    guard !context.isCancelled else { return }
                    OrientationGate.videoFullscreen = false
                    self?.video?.setFullScreen(false)
                    if wasPlaying { player?.play() }
                    // Snap the interface back to the app's portrait world.
                    let scene = playerViewController.view.window?.windowScene
                        ?? UIApplication.shared.connectedScenes
                            .compactMap { $0 as? UIWindowScene }.first
                    scene?.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
                    playerViewController.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
            }
        }
    }
}

/// App-level orientation policy: the browse/player UI is portrait-only on
/// iPhone (it was never designed for landscape), while fullscreen video may
/// rotate. UIKit consults this on every orientation decision.
final class OrientationGate: NSObject, UIApplicationDelegate {
    @MainActor static var videoFullscreen = false
    #if DEBUG
    /// The DEBUG Pose Probe's "Unlock rotation" toggle: every orientation,
    /// upside-down included, so the probe can see what each Duo pose yields.
    @MainActor static var poseProbeUnlocked = false
    #endif

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?)
        -> UIInterfaceOrientationMask {
        #if DEBUG
        if OrientationGate.poseProbeUnlocked { return .all }
        #endif
        return OrientationGate.videoFullscreen ? .allButUpsideDown : .portrait
    }
}
