import SwiftUI
import Combine

/// Which print layout StripComposer should use. Kept as a config switch
/// (rather than deleting the 3-photo code) so we can flip back easily.
enum TemplateMode: String, Codable {
    case singlePhoto
    case threePhotoStrip
}

/// Everything an admin can customize about the printed strip.
/// Regular users never see this — it's only reachable via the hidden
/// gesture in FrameSettingsView.
struct FrameConfig: Codable, Equatable {
    var headerText: String = "EMPORIUM THAI MARKET"
    var addressText: String = "1653 Sawtelle Blvd"
    var footerText: String = "THANK YOU!"
    var showDateTime: Bool = false
    var showBorder: Bool = false
    var showBarcode: Bool = true
    var logoImageData: Data? = nil   // stored as PNG data
    var shotCount: Int = 3
    var secondsBetweenShots: Double = 2.5
    var savedPrinterIdentifier: String? = nil  // set once via PrinterSetupView, then auto-reconnects on launch

    /// Optional (rather than a plain default) so decoding a config saved
    /// before this field existed doesn't fail and silently reset the whole
    /// saved config, including savedPrinterIdentifier. nil = current default.
    var templateMode: TemplateMode? = nil
    var resolvedTemplateMode: TemplateMode { templateMode ?? .threePhotoStrip }

    static let storageKey = "frameConfig.v2"
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
