import CoreImage
import QuartzCore
import UIKit

/// Rolling buffer of recent camera frames, so each shot can keep the
/// moments *before* its shutter (the "run-up") for the live video.
///
/// Fed by FilteredCameraPreview with every frame it receives (already
/// rotated upright). Frames are downscaled, mirrored to match the preview
/// and the captured photos, and kept only for the last `maxDuration` seconds.
nonisolated final class LiveFrameBuffer: @unchecked Sendable {
    static let shared = LiveFrameBuffer()

    /// One buffered frame. `time` is CACurrentMediaTime() when it arrived.
    struct Frame {
        let time: CFTimeInterval
        let image: CGImage
    }

    /// A shot's run-up: frames with their offset from the shutter (≤ 0 s).
    struct Clip {
        let frames: [(offset: Double, image: CGImage)]
        static let empty = Clip(frames: [])
    }

    /// Longest run-up the settings allow, plus a little slack.
    let maxDuration: Double = 2.5
    /// Frames kept per second. 15 is smooth enough for a short loop and
    /// keeps memory to ~20 MB per shot at `frameWidth`.
    let fps: Double = 15
    /// Width frames are stored at (height follows the camera's aspect).
    let frameWidth: CGFloat = 540

    private var frames: [Frame] = []
    private var lastAppend: CFTimeInterval = 0
    private let lock = NSLock()
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    private init() {}

    /// Called on the camera's processing queue for every preview frame.
    func append(_ image: CIImage) {
        let now = CACurrentMediaTime()
        lock.lock()
        let due = now - lastAppend >= 1 / fps
        if due { lastAppend = now }
        lock.unlock()
        guard due, image.extent.width > 0 else { return }

        // Downscale, then mirror horizontally like the on-screen preview.
        let scale = frameWidth / image.extent.width
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let mirrored = scaled.transformed(by: CGAffineTransform(scaleX: -1, y: 1))
        let extent = mirrored.extent.integral
        guard let cg = ciContext.createCGImage(mirrored, from: extent) else { return }

        lock.lock()
        frames.append(Frame(time: now, image: cg))
        let cutoff = now - maxDuration
        if let firstKept = frames.firstIndex(where: { $0.time >= cutoff }), firstKept > 0 {
            frames.removeFirst(firstKept)
        }
        lock.unlock()
    }

    /// The `duration` seconds of frames up to `shutter`, as offsets from it.
    func clip(endingAt shutter: CFTimeInterval, duration: Double) -> Clip {
        lock.lock()
        let picked = frames.filter { $0.time >= shutter - duration && $0.time <= shutter }
        lock.unlock()
        return Clip(frames: picked.map { ($0.time - shutter, $0.image) })
    }

    /// Drops everything (e.g. between sessions) to free memory.
    func clear() {
        lock.lock()
        frames.removeAll()
        lock.unlock()
    }
}
