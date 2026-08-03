import SwiftUI
import Combine

/// Everything an admin can customize about the printed strip.
/// Regular users never see this — it's only reachable via the hidden
/// gesture in FrameSettingsView.
struct FrameConfig: Codable, Equatable {
    var headerText: String = "EMPORIUM THAI MARKET"
    var footerText: String = "thanks for stopping by :)"
    var showDateTime: Bool = true
    var showBorder: Bool = true
    var logoImageData: Data? = nil   // stored as PNG data
    var shotCount: Int = 4
    var secondsBetweenShots: Double = 2.5
    var savedPrinterIdentifier: String? = nil  // set once via PrinterSetupView, then auto-reconnects on launch

    static let storageKey = "frameConfig.v1"
}

/// Loads/saves the config to disk and publishes changes to the capture UI.
final class FrameConfigStore: ObservableObject {
    @Published var config: FrameConfig {
        didSet { persist() }
    }

    static let shared = FrameConfigStore()

    private init() {
        if let data = UserDefaults.standard.data(forKey: FrameConfig.storageKey),
           let decoded = try? JSONDecoder().decode(FrameConfig.self, from: data) {
            self.config = decoded
        } else {
            self.config = FrameConfig()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: FrameConfig.storageKey)
        }
    }
}
