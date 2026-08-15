import SwiftUI
import AVFoundation
import MetalKit
import CoreImage

/// Live camera preview WITH the booth's color filter (contrast/bloom/grain,
/// no desaturation) applied in real time — guests see the color look live;
/// the black-and-white conversion only happens for what actually prints.
///
/// AVCaptureVideoPreviewLayer (the simple approach used before) shows the
/// raw hardware feed directly and can't have a Core Image filter applied
/// to it. To get a genuinely filtered live preview, this instead:
///   1. Captures raw video frames via AVCaptureVideoDataOutput
///   2. Runs each frame through BoothFilter.applyColor
///   3. Renders the filtered result into an MTKView (Metal-backed) —
///      Metal is used here purely as an efficient way to draw the
///      already-filtered image each frame, not for the filtering itself.
struct FilteredCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.metalDevice)
        view.framebufferOnly = false
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.delegate = context.coordinator
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        context.coordinator.attachOutput(to: session)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}

    // Welcome and Capture each mount their own FilteredCameraPreview against
    // the same long-lived session, and RootView's screen switch fully tears
    // down/recreates that subtree on every transition (no NavigationStack
    // reuse). Without removing the output here, every trip through
    // Welcome/Capture would permanently add another AVCaptureVideoDataOutput
    // — with its own Metal device, command queue, and CIContext — to the
    // session, compounding GPU/CPU load with every booth cycle until it
    // crashes. This is called when the view leaves the hierarchy.
    static func dismantleUIView(_ uiView: MTKView, coordinator: Coordinator) {
        coordinator.detachOutput()
    }

    final class Coordinator: NSObject, MTKViewDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
        let metalDevice = MTLCreateSystemDefaultDevice()!
        private lazy var commandQueue = metalDevice.makeCommandQueue()
        private lazy var ciContext = CIContext(mtlDevice: metalDevice)
        private let videoOutput = AVCaptureVideoDataOutput()
        private let processingQueue = DispatchQueue(label: "camera.frame.processing")
        private weak var attachedSession: AVCaptureSession?

        private var currentFilteredImage: CIImage?
        private let imageLock = NSLock()

        init(session: AVCaptureSession) {
            super.init()
        }

        func attachOutput(to session: AVCaptureSession) {
            attachedSession = session
            session.beginConfiguration()
            videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }
            session.commitConfiguration()
        }

        func detachOutput() {
            guard let session = attachedSession else { return }
            session.beginConfiguration()
            if session.outputs.contains(videoOutput) {
                session.removeOutput(videoOutput)
            }
            session.commitConfiguration()
        }

        // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = currentRotationAngle()
            }

            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let filtered = BoothFilter.applyColor(to: ciImage)

            imageLock.lock()
            currentFilteredImage = filtered
            imageLock.unlock()
        }

        private func currentRotationAngle() -> CGFloat {
            switch UIDevice.current.orientation {
            case .portrait: return 90
            case .portraitUpsideDown: return 270
            case .landscapeLeft: return 180
            case .landscapeRight: return 0
            default: return 90
            }
        }

        // MARK: - MTKViewDelegate

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let commandBuffer = commandQueue?.makeCommandBuffer() else { return }

            imageLock.lock()
            let image = currentFilteredImage
            imageLock.unlock()

            guard let image else { return }
            
            let flipped = image.transformed(by: CGAffineTransform(scaleX: -1, y: 1))
            
            // Scale/center the filtered image to fill the view (aspect fill),
            // matching how the old preview layer's .resizeAspectFill looked.
            let drawableSize = CGSize(width: view.drawableSize.width, height: view.drawableSize.height)
            let scale = max(drawableSize.width / flipped.extent.width, drawableSize.height / flipped.extent.height)
            let scaledImage = flipped.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let originX = scaledImage.extent.origin.x + (scaledImage.extent.width - drawableSize.width) / 2
            let originY = scaledImage.extent.origin.y + (scaledImage.extent.height - drawableSize.height) / 2
            let croppedImage = scaledImage.cropped(to: CGRect(x: originX, y: originY, width: drawableSize.width, height: drawableSize.height))

            ciContext.render(
                croppedImage,
                to: drawable.texture,
                commandBuffer: commandBuffer,
                bounds: croppedImage.extent,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
