import SwiftUI

/// Every screen in the booth flow, in order.
enum BoothScreen {
    case welcome
    /// frame: the strip the guest picked on the home screen.
    case capture(frame: BoothFrame)
    /// 04 · Printing + text me. photos: mono, print-matching set.
    /// colorPhotos: same shots, color. frame: the strip they picked.
    /// liveJob: the color JPG + live MP4 being written in the background.
    case review(photos: [UIImage], colorPhotos: [UIImage], frame: BoothFrame, liveJob: LiveExportJob)
}

/// Owns which screen is currently showing and hands navigation control
/// down to each screen via simple closures — no NavigationStack, since
/// a kiosk app shouldn't expose back buttons or swipe-back gestures.
struct RootView: View {
    @State private var currentScreen: BoothScreen = .welcome
    // Owned here (not in WelcomeView/CaptureView individually) so the
    // camera session stays continuous across the transition — the guest
    // sees the same running feed before and after tapping "start" instead
    // of it restarting.
    @StateObject private var camera = CameraCaptureManager()
    @StateObject private var printer = PrintManager()

    // MARK: - Idle auto-reset
    //
    // If nobody touches the screen for a while, snap back to Welcome so an
    // abandoned session doesn't block the next guest: 15s on Welcome, 30s
    // on Printing/Text me (any tap, including keypad presses, resets it, so
    // nobody gets kicked out mid-typing). Exempt while Capture's automatic
    // countdown sequence is running — that screen is *meant* to go several
    // seconds with zero touches.
    private var idleTimeout: TimeInterval {
        // Screen 04: 45 s while it shows the QR code (time to scan),
        // 30 s for the texting form.
        if case .review = currentScreen { return BoothFeatures.textingEnabled ? 30 : 45 }
        return 15
    }
    @State private var lastInteraction = Date()

    var body: some View {
        Group {
            switch currentScreen {
            case .welcome:
                WelcomeView(camera: camera, printer: printer, onStart: { frame in
                    currentScreen = .capture(frame: frame)
                })

            case .capture(let frame):
                CaptureView(
                    camera: camera,
                    frame: frame,
                    onComplete: { photos, colorPhotos in
                        let config = FrameConfigStore.shared.config
                        // The photo page id exists from the last shot on,
                        // so the QR shows immediately — before any upload.
                        let job = LiveExportJob(
                            sessionID: SessionID.make(),
                            frame: frame,
                            colorPhotos: colorPhotos,
                            runUps: camera.capturedRunUps,
                            runUpSeconds: config.resolvedLiveRunUpSeconds,
                            freezeSeconds: config.resolvedLiveFreezeSeconds
                        )
                        currentScreen = .review(photos: photos, colorPhotos: colorPhotos, frame: frame, liveJob: job)
                    }
                )

            case .review(let photos, let colorPhotos, let frame, let liveJob):
                ReviewView(photos: photos, colorPhotos: colorPhotos, frame: frame, liveJob: liveJob,
                           printer: printer, onDone: { currentScreen = .welcome })
            }
        }
        // simultaneousGesture (not gesture) so this never steals touches
        // from buttons underneath — it only observes.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in lastInteraction = Date() }
        )
        // Resume any unfinished uploads from earlier sessions.
        .onAppear { UploadQueue.shared.start() }
        .task(id: idleTaskID) {
            guard idleResetEnabled else { return }
            try? await Task.sleep(for: .seconds(idleTimeout))
            guard !Task.isCancelled else { return }
            currentScreen = .welcome
        }
    }

    /// False while Capture's automatic sequence is running.
    private var idleResetEnabled: Bool {
        if case .capture = currentScreen { return false }
        return true
    }

    /// .task(id:) cancels and restarts its sleep whenever this changes —
    /// so a fresh value on every touch (lastInteraction) or every screen
    /// change (screenKey) gives a clean, self-restarting idle timer with
    /// no manual DispatchWorkItem bookkeeping.
    private var idleTaskID: String {
        "\(screenKey)-\(lastInteraction.timeIntervalSinceReferenceDate)"
    }

    private var screenKey: String {
        switch currentScreen {
        case .welcome: return "welcome"
        case .capture: return "capture"
        case .review: return "review"
        }
    }
}
