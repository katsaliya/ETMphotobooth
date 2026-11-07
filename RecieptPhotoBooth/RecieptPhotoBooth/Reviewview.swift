import CoreImage.CIFilterBuiltins
import SwiftUI

/// 04 · Printing + photos (one shared screen) — docs/user-flow.md.
///
/// Opens as soon as the last shot is taken. Left: the strip in color,
/// first as stills, then the live video once LiveExporter finishes, with
/// the print status under it. Right: a QR code to the guest's photo page
/// (current phase). The "text me my photos" form + Sent state are kept
/// behind BoothFeatures.textingEnabled. The black & white print starts on
/// appear, exactly as before.
struct ReviewView: View {
    /// Mono, print-matching photos — composed into the printed strip.
    let photos: [UIImage]
    /// Same shots in color — shown on screen and saved.
    let colorPhotos: [UIImage]
    /// The frame the guest picked on the home screen — printed as-is.
    let frame: BoothFrame
    @ObservedObject var liveJob: LiveExportJob
    @ObservedObject var printer: PrintManager
    /// Back to the home screen (Take another, No thanks, Done, auto-return).
    let onDone: () -> Void

    private enum PrintPhase: Equatable {
        case waiting, printing, printed, noPrinter, failed
    }

    @State private var printPhase: PrintPhase = .waiting
    @State private var sentTo: String?
    @State private var showPrinterManagement = false

    var body: some View {
        Boothbackground(backgroundColor: BoothTheme.background) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    stripColumn(size: CGSize(width: geo.size.width / 2, height: geo.size.height))
                        .frame(width: geo.size.width / 2)

                    BoothTheme.divider
                        .frame(width: 1)
                        .padding(.vertical, 56)

                    Group {
                        if !BoothFeatures.textingEnabled {
                            QRPanel(
                                sessionID: liveJob.sessionID,
                                printer: printer,
                                onLogoTap: { showPrinterManagement = true },
                                onDone: onDone
                            )
                        } else if let sentTo {
                            SentPanel(phone: sentTo, onDone: onDone)
                                .transition(.opacity)
                        } else {
                            TextMePanel(
                                printer: printer,
                                onLogoTap: { showPrinterManagement = true },
                                onSubmit: submit,
                                onNoThanks: onDone
                            )
                            .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 56)
                    .padding(.vertical, 36)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .overlay(alignment: .bottomLeading) {
                // The QR panel has its own Take another / Done buttons.
                if BoothFeatures.textingEnabled {
                Button(action: onDone) {
                    Text(BoothCopy.Printing.takeAnother)
                        .font(BoothTheme.body(17))
                        .underline()
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .padding(.leading, 40)
                .padding(.bottom, 24)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: sentTo)
        .onAppear {
            // Keep this session's files on disk while the preview plays them.
            UploadQueue.shared.activeSessionID = liveJob.sessionID
            startPrintAndSave()
        }
        .onDisappear {
            if UploadQueue.shared.activeSessionID == liveJob.sessionID {
                UploadQueue.shared.activeSessionID = nil
            }
        }
        .onChange(of: printer.isPrinting) { wasPrinting, isPrinting in
            if isPrinting {
                printPhase = .printing
            } else if wasPrinting {
                printPhase = printer.lastError == nil ? .printed : .failed
            }
        }
        .sheet(isPresented: $showPrinterManagement) {
            PrinterManagementView(printer: printer)
        }
    }

    // MARK: - Left: live strip + print status

    /// Same geometry as the home and countdown screens, so the strip stays
    /// put from screen to screen.
    private func stripColumn(size: CGSize) -> some View {
        let arrowSpace: CGFloat = 2 * (52 + 20)
        let maxStripHeight = size.height - 80 - 110
        let maxStripWidth = size.width - arrowSpace - 40
        let stripWidth = min(maxStripHeight / StripPreview.heightFactor(for: frame), maxStripWidth)
        let stripSize = CGSize(width: stripWidth, height: stripWidth * StripPreview.heightFactor(for: frame))

        return VStack(spacing: 0) {
            Spacer(minLength: 40)

            ZStack(alignment: .topLeading) {
                // Color stills first — never a blank or spinning strip.
                StripPreview(frame: frame, width: stripWidth) { index, slotSize in
                    AnyView(still(index: index, size: slotSize))
                }

                if let result = liveJob.result {
                    LiveStripVideo(url: result.liveMP4, frame: frame, stripSize: stripSize)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .transition(.opacity)
                }
            }
            .frame(width: stripSize.width, height: stripSize.height)
            .animation(.easeInOut(duration: 0.4), value: liveJob.result != nil)

            printStatus
                // Same height as the home screen's caption block, so the
                // strip doesn't shift between screens.
                .frame(width: max(stripWidth, 300), height: 72)
                .padding(.top, 22)

            Spacer(minLength: 40)
        }
        .frame(width: size.width, height: size.height)
    }

    private func still(index: Int, size: CGSize) -> some View {
        Group {
            if index < colorPhotos.count {
                Image(uiImage: colorPhotos[index])
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height, alignment: .top)
            } else {
                BoothTheme.slotPlaceholder
            }
        }
    }

    private var printStatus: some View {
        VStack(spacing: 8) {
            switch printPhase {
            case .waiting, .printing:
                Text(BoothCopy.Printing.printing)
                    .font(BoothTheme.body(17, weight: .bold))
                    .foregroundStyle(.white)
                Text(BoothCopy.Printing.printingHint)
                    .font(BoothTheme.body(15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                IndeterminateBar()
                    .frame(width: 220, height: 5)
            case .printed:
                Text(BoothCopy.Printing.printed)
                    .font(BoothTheme.body(17, weight: .bold))
                    .foregroundStyle(.white)
                Capsule().fill(BoothTheme.progressActive)
                    .frame(width: 220, height: 5)
            case .noPrinter:
                Text(BoothCopy.Printing.noPrinter)
                    .font(BoothTheme.body(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            case .failed:
                Text(BoothCopy.Printing.printFailed)
                    .font(BoothTheme.body(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: printPhase)
    }

    // MARK: - Print + save (unchanged behavior)

    /// Prints the B&W strip. Saving to Photos (color JPG + live MP4 only)
    /// now happens in LiveExportJob as each file is finished.
    private func startPrintAndSave() {
        let mono = StripComposer.composeStrip(photos: photos, frame: frame)
        autoprint(mono)
    }

    /// Prints automatically as soon as the strip is ready — no manual
    /// "print" button. Waits briefly for autoConnect() to finish finding
    /// the printer over USB/Bluetooth before attempting to print.
    private func autoprint(_ image: UIImage) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard printer.connectedPrinter != nil else {
                printPhase = .noPrinter
                return
            }
            printer.lastError = nil
            printer.printStrip(image)
        }
    }

    // MARK: - Text me

    private func submit(digits: String, formatted: String) {
        Task { await DeliveryService.requestText(to: digits, consentVersion: BoothCopy.TextMe.consentVersion) }
        sentTo = formatted
    }
}

// MARK: - Right: QR code to the photo page (current phase)

private struct QRPanel: View {
    let sessionID: String
    @ObservedObject var printer: PrintManager
    let onLogoTap: () -> Void
    let onDone: () -> Void

    @ObservedObject private var uploads = UploadQueue.shared

    private var pageURL: URL? { DeliveryConfig.shared?.photoPageURL(for: sessionID) }
    private var ready: Bool { uploads.isReady(sessionID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandMark(printer: printer, onTap: onLogoTap)

            Text(BoothCopy.QR.lookingGood)
                .font(BoothTheme.label(15))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.top, 16)

            Text("\(BoothCopy.QR.headlineLead)\(Text(BoothCopy.QR.headlineAccent).italic().foregroundStyle(.white))")
                .font(BoothTheme.headline(44))
                .foregroundStyle(.black)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            Text(BoothCopy.QR.sub)
                .font(BoothTheme.body(18).italic())
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            VStack(spacing: 12) {
                Group {
                    if let pageURL, let qr = QRCode.image(for: pageURL.absoluteString) {
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .aspectRatio(1, contentMode: .fit)
                            .accessibilityLabel("QR code for your photos")
                    } else {
                        Text(BoothCopy.QR.notSetUp)
                            .font(BoothTheme.body(16, weight: .semibold))
                            .foregroundStyle(BoothTheme.primaryButton)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(width: 300, height: 300)
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 24).fill(Color.white))
                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)

                HStack(spacing: 8) {
                    if !ready { ProgressView().tint(.white) }
                    Text(ready ? BoothCopy.QR.ready : BoothCopy.QR.uploading)
                        .font(BoothTheme.body(17, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)
                }
                .animation(.easeInOut(duration: 0.25), value: ready)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 22)

            Spacer(minLength: 16)

            HStack(spacing: 14) {
                Button(action: onDone) {
                    Text(BoothCopy.QR.takeAnother)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(Capsule().strokeBorder(Color.white, lineWidth: 2))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                Button(action: onDone) {
                    Text(BoothCopy.QR.done)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(Capsule().fill(BoothTheme.primaryButton))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Black-on-white QR code, rendered at full resolution so it stays sharp.
private enum QRCode {
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Right: text me my photos (behind BoothFeatures.textingEnabled)

private struct TextMePanel: View {
    @ObservedObject var printer: PrintManager
    let onLogoTap: () -> Void
    let onSubmit: (_ digits: String, _ formatted: String) -> Void
    let onNoThanks: () -> Void

    @State private var digits = ""
    @State private var consented = false

    private var canSubmit: Bool { digits.count == 10 && consented }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandMark(printer: printer, onTap: onLogoTap)

            Text(BoothCopy.TextMe.lookingGood)
                .font(BoothTheme.label(15))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.top, 14)

            Text("\(BoothCopy.TextMe.headlineLead)\(Text(BoothCopy.TextMe.headlineAccent).italic().foregroundStyle(.white))")
                .font(BoothTheme.headline(40))
                .foregroundStyle(.black)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            Text(BoothCopy.TextMe.sub)
                .font(BoothTheme.body(17).italic())
                .foregroundStyle(.white)
                .padding(.top, 6)

            // Phone field
            Text(PhoneFormat.display(digits))
                .font(.system(size: 26, weight: .semibold, design: .monospaced))
                .foregroundStyle(digits.isEmpty ? .white.opacity(0.6) : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Capsule().fill(BoothTheme.tileFill))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5))
                .padding(.top, 14)

            Keypad(digits: $digits)
                .padding(.top, 10)

            // Consent — unchecked by default; fine print always visible.
            Button { consented.toggle() } label: {
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.white, lineWidth: 2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(consented ? Color.white : Color.clear))
                        .overlay {
                            if consented {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .heavy))
                                    .foregroundStyle(BoothTheme.primaryButton)
                            }
                        }
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(BoothCopy.TextMe.consentLabel)
                            .font(BoothTheme.body(15, weight: .bold))
                            .foregroundStyle(.white)
                        Text(BoothCopy.TextMe.consentFinePrint)
                            .font(BoothTheme.body(12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 12)

            Button { onSubmit(digits, PhoneFormat.display(digits)) } label: {
                Text(BoothCopy.TextMe.button)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(Capsule().fill(BoothTheme.primaryButton))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.45)
            .padding(.top, 14)

            Button(action: onNoThanks) {
                Text(BoothCopy.TextMe.noThanks)
                    .font(BoothTheme.body(16))
                    .underline()
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            Spacer(minLength: 0)
        }
    }
}

private struct SentPanel: View {
    let phone: String
    let onDone: () -> Void

    @State private var lastTouch = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Text("\(BoothCopy.TextMe.sentHeadlineLead)\(Text(BoothCopy.TextMe.sentHeadlineAccent).italic().foregroundStyle(.white))")
                .font(BoothTheme.headline(56))
                .foregroundStyle(.black)
                .fixedSize(horizontal: false, vertical: true)
            Text(BoothCopy.TextMe.sentOnTheWay(phone))
                .font(BoothTheme.body(20))
                .foregroundStyle(.white)
                .padding(.top, 16)
            Text(BoothCopy.TextMe.sentOnList)
                .font(BoothTheme.body(20).italic())
                .foregroundStyle(.white)
                .padding(.top, 8)
            Button(action: onDone) {
                Text(BoothCopy.TextMe.done)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 240, height: 64)
                    .background(Capsule().fill(BoothTheme.primaryButton))
            }
            .buttonStyle(.plain)
            .padding(.top, 36)
            Spacer()
        }
        // Back to the home screen after 20 s with no touches; any tap
        // restarts the wait.
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0).onChanged { _ in lastTouch = Date() }
        )
        .task(id: lastTouch) {
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            onDone()
        }
    }
}

/// Logo + PHOTOBOOTH. The logo stays the hidden staff entry to printer
/// settings and dims when the printer is disconnected.
private struct BrandMark: View {
    @ObservedObject var printer: PrintManager
    let onTap: () -> Void

    var body: some View {
        let isConnected = printer.connectedPrinter != nil
        HStack(spacing: 12) {
            Button(action: onTap) {
                Image("Logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 37)
                    .grayscale(isConnected ? 0 : 1)
                    .opacity(isConnected ? 1 : 0.6)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text(BoothCopy.Home.brandLabel)
                .font(BoothTheme.label(15))
                .tracking(3)
                .foregroundStyle(.white)
        }
    }
}

/// 1–9, then Clear · 0 · Delete.
private struct Keypad: View {
    @Binding var digits: String

    private let rows: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["clear", "0", "delete"]]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        Button { press(key) } label: {
                            Text(label(for: key))
                                .font(.system(size: key.count == 1 ? 26 : 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(Capsule().fill(BoothTheme.tileFill))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(KeyStyle())
                    }
                }
            }
        }
    }

    private func label(for key: String) -> String {
        switch key {
        case "clear": return BoothCopy.TextMe.clear
        case "delete": return BoothCopy.TextMe.delete
        default: return key
        }
    }

    private func press(_ key: String) {
        switch key {
        case "clear": digits = ""
        case "delete": if !digits.isEmpty { digits.removeLast() }
        default: if digits.count < 10 { digits.append(key) }
        }
    }

    private struct KeyStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
        }
    }
}

/// US 10-digit number, shown as (___) ___-____ and filled in as you type.
private enum PhoneFormat {
    static func display(_ digits: String) -> String {
        var chars = Array(digits)
        return String(BoothCopy.TextMe.phonePlaceholder.map { ch -> Character in
            guard ch == "_", !chars.isEmpty else { return ch }
            return chars.removeFirst()
        })
    }
}

/// A short bar sliding back and forth — the printer doesn't report progress.
private struct IndeterminateBar: View {
    @State private var phase = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.3))
                Capsule().fill(BoothTheme.progressActive)
                    .frame(width: geo.size.width * 0.35)
                    .offset(x: phase ? geo.size.width * 0.65 : 0)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { phase = true }
        }
    }
}
