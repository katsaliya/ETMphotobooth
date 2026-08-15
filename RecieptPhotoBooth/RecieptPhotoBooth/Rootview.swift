import SwiftUI

/// Every screen in the booth flow, in order.
/// thankYou was merged into ReviewView — the message now shows
/// alongside the photo strip so guests can read it while AirDropping.
enum BoothScreen {
    case welcome
    case capture
    /// photos: mono, print-matching set. colorPhotos: same shots, color —
    /// used for the digital save/AirDrop copy.
    case review(photos: [UIImage], colorPhotos: [UIImage])
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
    // If nobody touches the screen for 15s, snap back to Welcome so an
    // abandoned session (guest walked off after Review, or tapped Start
    // and wandered away) doesn't block the next guest. Exempt while
    // Capture's automatic countdown sequence is running — that screen is
    // *meant* to go several seconds with zero touches, so the idle timer
    // would otherwise abort a perfectly normal countdown.
    private let idleTimeout: TimeInterval = 15
    @State private var lastInteraction = Date()

    var body: some View {
        Group {
            switch currentScreen {
            case .welcome:
                WelcomeView(camera: camera, printer: printer, onStart: { currentScreen = .capture })

            case .capture:
                CaptureView(camera: camera, onComplete: { photos, colorPhotos in
                    currentScreen = .review(photos: photos, colorPhotos: colorPhotos)
                })

            case .review(let photos, let colorPhotos):
                ReviewView(photos: photos, colorPhotos: colorPhotos, printer: printer, onDone: { currentScreen = .welcome })
            }
        }
        // simultaneousGesture (not gesture) so this never steals touches
        // from buttons underneath — it only observes.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in lastInteraction = Date() }
        )
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
