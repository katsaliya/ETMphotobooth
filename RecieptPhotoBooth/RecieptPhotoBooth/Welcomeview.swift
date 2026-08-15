import SwiftUI

/// Welcome screen — built directly from Figma Dev Mode specs. Shared
/// pieces (logo/connection button, title, tag-us, consent notice) now
/// live in BoothBackground.swift and are referenced here rather than
/// duplicated inline.
struct WelcomeView: View {
    @ObservedObject var camera: CameraCaptureManager
    @ObservedObject var printer: PrintManager
    let onStart: () -> Void

    @ObservedObject private var frameStore = FrameConfigStore.shared
    @State private var showPrinterManagement = false

    /// Fixed width, height derived from the actual print slot's aspect
    /// ratio — keeps the live preview honest about what will survive into
    /// the printed photo instead of showing a taller crop than gets kept.
    private let previewWidth: CGFloat = 855
    private var previewHeight: CGFloat {
        previewWidth / StripComposer.photoSlotAspectRatio(for: frameStore.config.resolvedTemplateMode)
    }

    var body: some View {
        Boothbackground {
            VStack(spacing: 0) {
                Spacer().frame(height: 20)

                EmporiumLogoButton(isConnected: printer.connectedPrinter != nil) {
                    showPrinterManagement = true
                }

                EmporiumTitleText(text: "EMPORIUM THAI MARKET")
                    .padding(.top, 6)

                FilteredCameraPreview(session: camera.session)
                    .frame(width: previewWidth, height: previewHeight)
                    .clipped()
                    .background(EmporiumStyle.boxFill)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .inset(by: 0.5)
                            .stroke(EmporiumStyle.accentPink, lineWidth: 1)
                    )
                    .padding(.top, 20)

                Button(action: onStart) {
                    ZStack {
                        Ellipse()
                            .fill(EmporiumStyle.buttonFill)
                            .overlay(
                                Ellipse().stroke(EmporiumStyle.accentPink, lineWidth: 1)
                            )
                            .frame(width: 252, height: 57)

                        Text("start")
                            .font(.epilogue(size: 24, weight: .bold))
                            .fontWeight(.bold)
                            .tracking(-2)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.black)
                    }
                }
                .padding(.top, 18)

                Spacer()
            }

            ConsentNoticeText()
            TagUsText()
        }
        .onAppear {
            camera.start()
            printer.autoConnect()
        }
        .sheet(isPresented: $showPrinterManagement) {
            PrinterManagementView(printer: printer)
        }
    }
}

#Preview {
    WelcomeView(camera: CameraCaptureManager(), printer: PrintManager(), onStart: {})
}
