import SwiftUI

/// Welcome screen — built directly from Figma Dev Mode specs. Shared
/// pieces (logo/connection button, title, tag-us, consent notice) now
/// live in BoothBackground.swift and are referenced here rather than
/// duplicated inline.
struct WelcomeView: View {
    @ObservedObject var camera: CameraCaptureManager
    @ObservedObject var printer: PrintManager
    let onStart: () -> Void

    @State private var showPrinterManagement = false

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
                    .frame(width: 603, height: 398.00992)
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

                        Text("get receipt")
                            .font(.epilogue(size: 18, weight: .bold))
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
