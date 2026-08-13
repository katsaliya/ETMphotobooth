import SwiftUI
import Photos

/// Shown right after the 3 photos are captured. Same header (logo +
/// title) and box styling as Welcome/Capture. Auto-saves to Photos and
/// auto-prints the strip immediately on appear — no manual print step.
/// Combines the strip preview with a thank-you message so the guest can
/// read it while optionally AirDropping to themselves, then taps "done"
/// to return to Welcome.
struct ReviewView: View {
    let photos: [UIImage]
    @ObservedObject var printer: PrintManager
    /// Called when the guest taps "done" — RootView returns to Welcome.
    let onDone: () -> Void

    @ObservedObject private var frameStore = FrameConfigStore.shared

    @State private var strip: UIImage?
    @State private var showShareSheet = false
    @State private var saveMessage: String?
    @State private var printMessage: String?
    @State private var showPrinterManagement = false

    var body: some View {
        Boothbackground(backgroundColor: EmporiumStyle.accentPink) {
            VStack(spacing: 0) {
                Spacer().frame(height: 40)

                EmporiumLogoButton(isConnected: printer.connectedPrinter != nil) {
                    showPrinterManagement = true
                }

                // Title, boxed in white like the printed template's header —
                // distinct from EmporiumTitleText (plain text) used elsewhere.
                Spacer()

                // Thank you! (left) — strip preview, boxed in white and
                // centered with the logo above — See you soon <3 (right).
                // Both side texts get equal-width containers so the strip
                // sits at the true center regardless of text length, and
                // the strip itself uses an exact (not max) height so its
                // white background hugs the image with no extra whitespace.
                HStack(alignment: .center, spacing: 40) {
                    Text("Thank you!")
                        .font(.pinyonScript(size: 64))
                        .foregroundColor(.white)
                        .frame(width: 260)
                        .padding(.top, 70)

                    Group {
                        if let strip {
                            Image(uiImage: strip)
                                .resizable()
                                .scaledToFit()
                        } else {
                            EmporiumStyle.boxFill
                                .frame(width: 260, height: 480)
                        }
                    }
                    .frame(height: 480)
                    .background(Color.white)

                    Text("See you \nsoon <3")
                        .font(.pinyonScript(size: 64))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .frame(width: 260)
                        .padding(.bottom, 70)
                }
                .padding(.horizontal, 70)

                if printer.isPrinting {
                    Text("printing…")
                        .font(.epilogue(size: 13, weight: .light))
                        .foregroundColor(.white)
                        .padding(.top, 10)
                }
                if let printMessage {
                    Text(printMessage)
                        .font(.epilogue(size: 13, weight: .light))
                        .foregroundColor(.white)
                        .padding(.top, 10)
                }
                if let saveMessage {
                    Text(saveMessage)
                        .font(.epilogue(size: 11, weight: .light))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top, 4)
                }

                Spacer()

                HStack(spacing: 70) {
                    Button {
                        showShareSheet = true
                    } label: {
                        textButton(label: "airdrop", enabled: strip != nil)
                    }
                    .disabled(strip == nil)

                    Button(action: onDone) {
                        textButton(label: "done", enabled: true)
                    }
                }
                .padding(.bottom, 75)
            }
        }
        // No TagUsText here — this screen's Figma mockup doesn't include the
        // "tag us" corner that Welcome/Capture show.
        .onAppear {
            let composed = StripComposer.composeStrip(photos: photos, config: frameStore.config)
            strip = composed
            saveStripLocally(composed)
            autoprint(composed)
        }
        .sheet(isPresented: $showShareSheet) {
            if let strip {
                ShareSheet(items: [strip])
            }
        }
        .sheet(isPresented: $showPrinterManagement) {
            PrinterManagementView(printer: printer)
        }
    }

    /// Plain bold text link, no pill chrome — matches the Figma redesign's
    /// bottom-corner "airdrop" / "done" treatment.
    private func textButton(label: String, enabled: Bool) -> some View {
        Text(label)
            .font(.cossetteTitre(size: 39.78751, weight: .bold))
            .tracking(-1)
            .foregroundColor(.white)
            .opacity(enabled ? 1 : 0.4)
    }

    /// Prints automatically as soon as the strip is ready — no manual
    /// "print" button. Waits briefly for autoConnect() to finish finding
    /// the printer over USB/Bluetooth before attempting to print.
    private func autoprint(_ image: UIImage) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard printer.connectedPrinter != nil else {
                printMessage = "printer not connected"
                return
            }
            printer.printStrip(image)
        }
    }

    /// Every strip auto-saves to the iPad's Photos library on appear,
    /// independent of AirDrop or printing.
    private func saveStripLocally(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { saveMessage = "photo library access not granted" }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    saveMessage = success ? "saved to photos" : "couldn't save: \(error?.localizedDescription ?? "unknown error")"
                }
            }
        }
    }
}
