import SwiftUI
import Photos

/// Shown right after the 3 photos are captured. Same header (logo +
/// title) and box styling as Welcome/Capture. Auto-saves to Photos and
/// auto-prints the strip immediately on appear — no manual print step.
/// Combines the strip preview with a thank-you message so the guest can
/// read it while optionally AirDropping to themselves, reprinting, or
/// tapping "take more!" to return to Welcome for another round.
struct ReviewView: View {
    /// Mono, print-matching photos — composed into `strip`, what's shown
    /// on screen and what actually prints.
    let photos: [UIImage]
    /// Same shots in color — composed into `colorStrip`, what gets saved
    /// to Photos and AirDropped, alongside the mono version.
    let colorPhotos: [UIImage]
    @ObservedObject var printer: PrintManager
    /// Called when the guest taps "take more!" — RootView returns to Welcome.
    let onDone: () -> Void

    @ObservedObject private var frameStore = FrameConfigStore.shared

    @State private var strip: UIImage?
    @State private var colorStrip: UIImage?
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

                // Thank you! (left) — color + b&w strip previews, boxed in
                // white and centered with the logo above — See you soon <3
                // (right). Both side texts get equal-width containers so
                // the pair of previews sits at the true center regardless
                // of text length. Showing both here even though only the
                // b&w one ever prints (thermal printer, no color output) —
                // it's the color one that actually gets kept/shared most.
                HStack(alignment: .center, spacing: 40) {
                    Text("Thank you!")
                        .font(.pinyonScript(size: 64))
                        .foregroundColor(.white)
                        .frame(width: 260)
                        .padding(.top, 70)

                    HStack(spacing: 20) {
                        stripPreview(caption: "color", image: colorStrip)
                        stripPreview(caption: "b&w", image: strip)
                    }

                    Text("See you \nsoon <3")
                        .font(.pinyonScript(size: 64))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .frame(width: 260)
                        .padding(.bottom, 70)
                }
                .padding(.horizontal, 50)

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

                HStack(spacing: 55) {
                    Button {
                        showShareSheet = true
                    } label: {
                        textButton(label: "airdrop", enabled: strip != nil && colorStrip != nil)
                    }
                    .disabled(strip == nil || colorStrip == nil)

                    Button {
                        if let strip {
                            printer.printStrip(strip)
                        }
                    } label: {
                        textButton(label: "reprint", enabled: strip != nil)
                    }
                    .disabled(strip == nil)

                    Button(action: onDone) {
                        textButton(label: "take more!", enabled: true)
                    }
                }
                .padding(.bottom, 75)
            }
        }
        // No TagUsText here — this screen's Figma mockup doesn't include the
        // "tag us" corner that Welcome/Capture show.
        .onAppear {
            let composed = StripComposer.composeStrip(photos: photos, config: frameStore.config)
            let composedColor = StripComposer.composeStrip(photos: colorPhotos, config: frameStore.config)
            strip = composed
            colorStrip = composedColor
            saveStripLocally(mono: composed, color: composedColor)
            autoprint(composed)
        }
        .sheet(isPresented: $showShareSheet) {
            if let strip, let colorStrip {
                ShareSheet(items: [colorStrip, strip])
            }
        }
        .sheet(isPresented: $showPrinterManagement) {
            PrinterManagementView(printer: printer)
        }
    }

    /// One labeled strip preview box — used twice (color, then b&w) in the
    /// middle band. Exact (not max) height so the white background hugs
    /// the image with no extra whitespace, same trick as the single-preview
    /// version before this.
    private func stripPreview(caption: String, image: UIImage?) -> some View {
        VStack(spacing: 6) {
            Text(caption)
                .font(.epilogue(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.85))

            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    EmporiumStyle.boxFill
                        .frame(width: 200, height: 380)
                }
            }
            .frame(height: 380)
            .background(Color.white)
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

    /// Both the mono (print-matching) and color strips auto-save to the
    /// iPad's Photos library on appear, independent of AirDrop or printing.
    private func saveStripLocally(mono: UIImage, color: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { saveMessage = "photo library access not granted" }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: color)
                PHAssetChangeRequest.creationRequestForAsset(from: mono)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    saveMessage = success ? "saved to photos" : "couldn't save: \(error?.localizedDescription ?? "unknown error")"
                }
            }
        }
    }
}
