import SwiftUI
import Combine

/// Which print layout StripComposer should use. Kept as a config switch
/// (rather than deleting the 3-photo code) so we can flip back easily.
nonisolated enum TemplateMode: String, Codable, Sendable {
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

    /// Live video settings. Optional for the same reason as templateMode:
    /// older saved configs decode fine and fall back to the defaults.
    /// Run-up: seconds of motion before each shutter (1–2 s).
    var liveRunUpSeconds: Double? = nil
    /// Freeze: seconds each slot holds on its captured photo before the loop resets.
    var liveFreezeSeconds: Double? = nil

    static let liveRunUpRange: ClosedRange<Double> = 1.0...2.0
    static let liveFreezeRange: ClosedRange<Double> = 0.5...4.0

    var resolvedLiveRunUpSeconds: Double {
        min(max(liveRunUpSeconds ?? 1.5, Self.liveRunUpRange.lowerBound), Self.liveRunUpRange.upperBound)
    }
    var resolvedLiveFreezeSeconds: Double {
        min(max(liveFreezeSeconds ?? 1.5, Self.liveFreezeRange.lowerBound), Self.liveFreezeRange.upperBound)
    }

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
