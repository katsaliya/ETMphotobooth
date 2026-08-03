import AVFoundation
import UIKit
import Combine

final class CameraCaptureManager: NSObject, ObservableObject {

    @Published var isRunningSequence = false
    @Published var countdownText: String = ""
    @Published var capturedImages: [UIImage] = []
    @Published var lastError: String?

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var pendingCompletion: ((UIImage?) -> Void)?

    override init() {
        super.init()
        configureSession()
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            lastError = "Camera unavailable"
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        session.commitConfiguration()
    }

    func start() {
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    /// The one button the public sees. Fires N shots, `interval` seconds apart,
    /// then hands the finished set back on the main thread.
    func runBoothSequence(
        shotCount: Int,
        interval: TimeInterval,
        onComplete: @escaping ([UIImage]) -> Void
    ) {
        guard !isRunningSequence else { return }
        isRunningSequence = true
        capturedImages = []

        func takeNext(_ remaining: Int) {
            guard remaining > 0 else {
                isRunningSequence = false
                countdownText = ""
                onComplete(capturedImages)
                return
            }

            countdown(from: 3) { [weak self] in
                self?.capturePhoto { image in
                    if let image {
                        self?.capturedImages.append(image)
                    }
                    // brief pause after the flash/shutter before next countdown
                    DispatchQueue.main.asyncAfter(deadline: .now() + max(0, interval - 3)) {
                        takeNext(remaining - 1)
                    }
                }
            }
        }

        takeNext(shotCount)
    }

    private func countdown(from n: Int, then: @escaping () -> Void) {
        guard n > 0 else {
            countdownText = "📸"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { then() }
            return
        }
        countdownText = "\(n)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.countdown(from: n - 1, then: then)
        }
    }

    private func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        pendingCompletion = completion
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

extension CameraCaptureManager: AVCapturePhotoOutputPhotoFinalizeDelegate, AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            pendingCompletion?(nil)
            pendingCompletion = nil
            return
        }
        pendingCompletion?(image)
        pendingCompletion = nil
    }
}
