import AVFoundation
import UIKit
import Combine

final class CameraCaptureManager: NSObject, ObservableObject {

    @Published var isRunningSequence = false
    @Published var countdownText: String = ""
    @Published var capturedImages: [UIImage] = []
    @Published var lastError: String?
    @Published var currentShotIndex: Int = 0
    @Published var lastCapturedImage: UIImage?

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var pendingCompletion: ((UIImage?) -> Void)?

    override init() {
        super.init()
        configureSession()
        observeOrientationChanges()
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

    // MARK: - Orientation handling
    //
    // AVFoundation's video connections don't rotate automatically just because
    // the SwiftUI layout does — we have to explicitly tell both the live
    // preview layer and the photo output which way is "up" whenever the
    // iPad's physical orientation changes.

    private func observeOrientationChanges() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceOrientationChanged),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
        updatePhotoOutputOrientation()
    }

    @objc private func deviceOrientationChanged() {
        updatePhotoOutputOrientation()
    }

    /// Called by CameraPreview whenever its own preview layer needs updating too.
    var currentVideoOrientation: AVCaptureVideoOrientation {
        switch UIDevice.current.orientation {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        // Note: landscapeLeft/Right are intentionally swapped here — UIDevice's
        // landscape orientation naming is inverted relative to AVCaptureVideoOrientation.
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        default: return .portrait // faceUp/faceDown/unknown: keep last sensible value
        }
    }

    private func updatePhotoOutputOrientation() {
        guard let connection = photoOutput.connection(with: .video) else { return }
        let newOrientation = currentVideoOrientation
        // Ignore face-up/face-down/unknown so a flat-on-table iPad doesn't reset rotation.
        let deviceOrientation = UIDevice.current.orientation
        guard deviceOrientation.isPortrait || deviceOrientation.isLandscape else { return }
        if connection.isVideoOrientationSupported {
            connection.videoOrientation = newOrientation
        }
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
                currentShotIndex = 0
                onComplete(capturedImages)
                return
            }

            currentShotIndex = shotCount - remaining + 1

            countdown(from: 3) { [weak self] in
                self?.capturePhoto { image in
                    if let image {
                        self?.capturedImages.append(image)
                        self?.lastCapturedImage = image
                    }
                    // Show a preview of the photo just taken before moving on.
                    DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
                        self?.lastCapturedImage = nil
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

    deinit {
        NotificationCenter.default.removeObserver(self)
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }
}

extension CameraCaptureManager: AVCapturePhotoCaptureDelegate {
    // AVCapturePhotoOutput always delivers this on an internal background
    // queue, never the main thread — regardless of what thread called
    // capturePhoto(with:). pendingCompletion ultimately mutates @Published
    // state (capturedImages, lastCapturedImage) via runBoothSequence, and
    // is itself written from capturePhoto() on the main thread, so touching
    // it here without hopping to main is both a SwiftUI threading violation
    // and a data race on pendingCompletion — this is what was crashing the
    // app on the very first photo after a fresh launch/clean build.
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let rawImage = UIImage(data: data) else {
            DispatchQueue.main.async { [weak self] in
                self?.pendingCompletion?(nil)
                self?.pendingCompletion = nil
            }
            return
        }
        // Same filter as the live preview, so what guests saw while
        // shooting matches what gets saved and printed. Kept off the main
        // thread since it's real CPU/GPU work — only the completion hop
        // below needs to be on main.
        let filtered = BoothFilter.apply(to: rawImage)
        DispatchQueue.main.async { [weak self] in
            self?.pendingCompletion?(filtered)
            self?.pendingCompletion = nil
        }
    }
}
