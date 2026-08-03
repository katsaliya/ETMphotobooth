import SwiftUI

@main
struct PhotoBoothApp: App {

    init() {
        // Never let the screen dim or lock while the booth is running.
        UIApplication.shared.isIdleTimerDisabled = true
    }

    var body: some Scene {
        WindowGroup {
            CaptureView()
                .persistentSystemOverlays(.hidden) // hides home indicator on newer iPadOS
                .statusBarHidden(true)
                .onAppear {
                    // Belt-and-suspenders: re-assert on every appear in case
                    // something (e.g. a system alert) resets it.
                    UIApplication.shared.isIdleTimerDisabled = true
                }
        }
    }
}

/*
 KIOSK LOCKDOWN (do this once, outside the app, on the iPad itself):

 1. Settings > Accessibility > Guided Access > turn ON, set a passcode.
 2. Open this app, triple-click the side/home button to start Guided Access.
    - This disables the physical Home/App-Switcher gesture, Control Center,
      and (optionally) touch on specific screen regions.
 3. For a permanent/unattended install, use Apple Configurator or an MDM
    profile to put the device in "Single App Mode" instead — this survives
    reboots and doesn't require a person to triple-click to re-enter.

 Neither of these is app code; they're device configuration, but they're
 required for "user can never leave the app / change settings."
*/
