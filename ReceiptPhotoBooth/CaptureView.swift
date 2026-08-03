import SwiftUI
import AVFoundation

struct CaptureView: View {
    @StateObject private var camera = CameraCaptureManager()
    @StateObject private var printer = PrintManager()
    @ObservedObject private var frameStore = FrameConfigStore.shared

    @State private var showAdmin = false
    @State private var tapCount = 0
    @State private var lastTapTime = Date()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            if !camera.countdownText.isEmpty {
                Text(camera.countdownText)
                    .font(.system(size: 120, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(radius: 20)
            }

            VStack {
                Spacer()
                Button(action: startBooth) {
                    Text(camera.isRunningSequence ? "Say cheese!" : "Tap to start")
                        .font(.title.bold())
                        .padding(.horizontal, 48)
                        .padding(.vertical, 20)
                        .background(.white.opacity(0.9))
                        .foregroundStyle(.black)
                        .clipShape(Capsule())
                }
                .disabled(camera.isRunningSequence || printer.isPrinting)
                .padding(.bottom, 60)
            }

            if printer.isPrinting {
                VStack {
                    ProgressView("Printing…")
                        .padding()
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            // Invisible corner target: 5 taps within 2s opens the admin panel.
            // Not a documented gesture, no visible affordance — this is the
            // "customizable but hidden from users" entry point.
            VStack {
                HStack {
                    Spacer()
                    Color.clear
                        .frame(width: 60, height: 60)
                        .contentShape(Rectangle())
                        .onTapGesture { registerAdminTap() }
                }
                Spacer()
            }
        }
        .onAppear {
            camera.start()
            printer.reconnectSavedPrinter()
        }
        .sheet(isPresented: $showAdmin) {
            FrameSettingsView(printer: printer)
        }
    }

    private func startBooth() {
        camera.runBoothSequence(
            shotCount: frameStore.config.shotCount,
            interval: frameStore.config.secondsBetweenShots
        ) { photos in
            guard !photos.isEmpty else { return }
            let strip = StripComposer.composeStrip(photos: photos, config: frameStore.config)
            printer.printStrip(strip)
        }
    }

    private func registerAdminTap() {
        let now = Date()
        if now.timeIntervalSince(lastTapTime) > 2 {
            tapCount = 0
        }
        lastTapTime = now
        tapCount += 1
        if tapCount >= 5 {
            tapCount = 0
            showAdmin = true
        }
    }
}

/// Thin UIViewRepresentable wrapper to show the live AVCaptureSession.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
