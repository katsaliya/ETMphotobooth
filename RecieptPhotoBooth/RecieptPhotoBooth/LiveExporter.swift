import AVFoundation
import UIKit

/// After a session, writes the guest's digital copies to the app's
/// Documents folder (visible in the Files app → On My iPad → Booth By Liya):
///
///   Sessions/<session id>/strip.jpg  — color strip, same frame design as the print
///   Sessions/<session id>/live.mp4   — 9:16 live strip: every slot plays its
///                                     run-up, freezes on its photo, holds, resets.
///                                     All slots in sync; the file loops cleanly.
///
/// The black-and-white print is built separately (StripComposer, ReviewView)
/// and is not touched by any of this.
nonisolated enum LiveExporter {

    struct Result {
        let folder: URL
        let stripJPG: URL
        let liveMP4: URL
    }

    // MARK: - Video format

    static let videoSize = CGSize(width: 1080, height: 1920) // 9:16
    static let videoFPS: Int32 = 30
    /// The file repeats the run-up → freeze cycle until it's at least this
    /// long, for players that don't loop on their own.
    static let minimumVideoSeconds: Double = 6

    // MARK: - Export

    /// `onStripSaved` runs as soon as strip.jpg is on disk (before the
    /// slower video), so it can start uploading right away.
    static func export(
        sessionID: String,
        frame: BoothFrame,
        colorPhotos: [UIImage],
        runUps: [LiveFrameBuffer.Clip],
        runUpSeconds: Double,
        freezeSeconds: Double,
        onStripSaved: @Sendable (URL) async -> Void = { _ in }
    ) async throws -> Result {
        let folder = try sessionFolder(sessionID)

        // 1. Color strip JPG — exactly the print's composition, in color.
        let strip = StripComposer.composeStrip(photos: colorPhotos, frame: frame)
        let stripURL = folder.appendingPathComponent("strip.jpg")
        guard let jpg = strip.jpegData(compressionQuality: 0.92) else { throw ExportError.jpegEncoding }
        try jpg.write(to: stripURL, options: .atomic)
        await onStripSaved(stripURL)

        // 2. Live MP4.
        // Written under a temp name and moved into place when complete, so
        // the upload queue never sees a half-written file after a restart.
        let liveURL = folder.appendingPathComponent("live.mp4")
        let tempURL = folder.appendingPathComponent("live.partial.mp4")
        try? FileManager.default.removeItem(at: tempURL)
        try await writeLiveVideo(
            to: tempURL, frame: frame, photos: colorPhotos, runUps: runUps,
            runUpSeconds: runUpSeconds, freezeSeconds: freezeSeconds
        )
        try? FileManager.default.removeItem(at: liveURL)
        try FileManager.default.moveItem(at: tempURL, to: liveURL)

        return Result(folder: folder, stripJPG: stripURL, liveMP4: liveURL)
    }

    enum ExportError: Error {
        case jpegEncoding
        case writerSetup
        case writerFailed(Error?)
    }

    // MARK: - Live video

    private static func writeLiveVideo(
        to url: URL,
        frame: BoothFrame,
        photos: [UIImage],
        runUps: [LiveFrameBuffer.Clip],
        runUpSeconds: Double,
        freezeSeconds: Double
    ) async throws {
        let size = videoSize
        let layout = Layout(frame: frame, canvas: size)

        // Pre-render everything that doesn't change frame to frame.
        let template = UIImage(named: frame.templateImage).map { prescale($0, to: layout.stripRect.size) }
        let stills: [UIImage] = layout.slotRects.indices.map { i in
            i < photos.count ? aspectFillTop(photos[i], into: layout.slotRects[i].size) : placeholder(layout.slotRects[i].size)
        }

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        guard writer.canAdd(input) else { throw ExportError.writerSetup }
        writer.add(input)
        guard writer.startWriting() else { throw ExportError.writerFailed(writer.error) }
        writer.startSession(atSourceTime: .zero)

        // One cycle = run-up then freeze; repeat to reach the minimum length.
        let cycle = runUpSeconds + freezeSeconds
        let cycles = max(1, Int(ceil(minimumVideoSeconds / cycle)))
        let framesPerCycle = Int((cycle * Double(videoFPS)).rounded())
        let totalFrames = framesPerCycle * cycles

        for index in 0..<totalFrames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            guard let pool = adaptor.pixelBufferPool else { throw ExportError.writerFailed(writer.error) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw ExportError.writerFailed(writer.error) }

            // Time inside the current cycle: [0, runUp) plays the run-up,
            // [runUp, cycle) holds the captured photo.
            let t = Double(index % framesPerCycle) / Double(videoFPS)

            draw(into: buffer, size: size) {
                UIColor.white.setFill()
                UIRectFill(CGRect(origin: .zero, size: size))

                for (i, rect) in layout.slotRects.enumerated() {
                    if t < runUpSeconds, i < runUps.count,
                       let image = runUps[i].frame(at: t - runUpSeconds) {
                        // Run-up frame (offset from the shutter, ≤ 0).
                        drawAspectFillTop(UIImage(cgImage: image), in: rect)
                    } else {
                        stills[i].draw(in: rect)
                    }
                }

                template?.draw(in: layout.stripRect)
            }

            let time = CMTime(value: CMTimeValue(index), timescale: videoFPS)
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw ExportError.writerFailed(writer.error)
            }
        }

        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw ExportError.writerFailed(writer.error) }
    }

    /// Where the strip sits inside the video (1080×1920 canvas).
    static func stripRect(for frame: BoothFrame) -> CGRect {
        Layout(frame: frame, canvas: videoSize).stripRect
    }

    /// Where the strip sits on the 9:16 canvas: as large as fits, centered.
    private struct Layout {
        let stripRect: CGRect
        let slotRects: [CGRect]

        init(frame: BoothFrame, canvas: CGSize) {
            let t = frame.templateSize
            let scale = min(canvas.width / t.width, canvas.height / t.height)
            let size = CGSize(width: t.width * scale, height: t.height * scale)
            let origin = CGPoint(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2)
            stripRect = CGRect(origin: origin, size: size)
            slotRects = frame.slots.map {
                CGRect(x: origin.x + $0.minX * scale, y: origin.y + $0.minY * scale,
                       width: $0.width * scale, height: $0.height * scale)
            }
        }
    }

    // MARK: - Drawing helpers

    /// Draws with UIKit (top-left origin) straight into a video frame.
    private static func draw(into buffer: CVPixelBuffer, size: CGSize, _ body: () -> Void) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(ctx)
        body()
        UIGraphicsPopContext()
    }

    /// Same crop as the print and live preview: fill the slot, keep the top
    /// of the shot (heads), center horizontally.
    private static func drawAspectFillTop(_ image: UIImage, in rect: CGRect) {
        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let w = image.size.width * scale, h = image.size.height * scale
        UIGraphicsGetCurrentContext()?.saveGState()
        UIBezierPath(rect: rect).addClip()
        image.draw(in: CGRect(x: rect.midX - w / 2, y: rect.minY, width: w, height: h))
        UIGraphicsGetCurrentContext()?.restoreGState()
    }

    private static func aspectFillTop(_ image: UIImage, into size: CGSize) -> UIImage {
        renderer(size).image { _ in drawAspectFillTop(image, in: CGRect(origin: .zero, size: size)) }
    }

    private static func prescale(_ image: UIImage, to size: CGSize) -> UIImage {
        renderer(size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    private static func placeholder(_ size: CGSize) -> UIImage {
        renderer(size).image { ctx in
            UIColor.lightGray.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    private static func renderer(_ size: CGSize) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    // MARK: - Files

    /// Documents/Sessions — every session's local copies live here until
    /// they're uploaded (and for at most 7 days).
    static var sessionsRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sessions", isDirectory: true)
    }

    private static func sessionFolder(_ sessionID: String) throws -> URL {
        let folder = sessionsRoot.appendingPathComponent(sessionID, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

nonisolated extension LiveFrameBuffer.Clip {
    /// The frame showing at `offset` seconds from the shutter (≤ 0): the
    /// latest frame at or before it, or the earliest frame if the buffer
    /// didn't reach back that far. nil if the clip is empty.
    func frame(at offset: Double) -> CGImage? {
        guard let first = frames.first else { return nil }
        return frames.last(where: { $0.offset <= offset })?.image ?? first.image
    }
}
