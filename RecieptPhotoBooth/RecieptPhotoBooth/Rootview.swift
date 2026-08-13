import SwiftUI

/// Every screen in the booth flow, in order.
/// thankYou was merged into ReviewView — the message now shows
/// alongside the photo strip so guests can read it while AirDropping.
enum BoothScreen {
    case welcome
    case capture
    case review(photos: [UIImage])
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
    
    var body: some View {
        switch currentScreen {
        case .welcome:
            WelcomeView(camera: camera, printer: printer, onStart: { currentScreen = .capture })
            
        case .capture:
            CaptureView(camera: camera, onComplete: { photos in
                currentScreen = .review(photos: photos)
            })

        case .review(let photos):
            ReviewView(photos: photos, printer: printer, onDone: { currentScreen = .welcome })
        }
    }
}
