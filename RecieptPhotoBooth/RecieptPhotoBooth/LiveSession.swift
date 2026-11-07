import AVFoundation
import Combine
import Photos
import SwiftUI

/// One guest session's digital copies: runs LiveExporter in the background
/// and publishes the result so screen 04 can switch from color stills to
/// the live video as soon as it's ready.
@MainActor
final class LiveExportJob: ObservableObject {
    @Published private(set) var result: LiveExporter.Result?
    @Published private(set) var failed = false

    /// The guest's photo page id — the QR code shows as soon as this exists.
    let sessionID: String

    init(sessionID: String, frame: BoothFrame, colorPhotos: [UIImage], runUps: [LiveFrameBuffer.Clip],
         runUpSeconds: Double, freezeSeconds: Double) {
        self.sessionID = sessionID
        UploadQueue.shared.register(sessionID)
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                // Each file starts uploading the moment it's on disk, while
                // the strip prints.
                let result = try await LiveExporter.export(
                    sessionID: sessionID,
                    frame: frame, colorPhotos: colorPhotos, runUps: runUps,
                    runUpSeconds: runUpSeconds, freezeSeconds: freezeSeconds,
                    onStripSaved: { url in
                        // Keep a copy on the iPad first, then hand it to the
                        // upload queue (which deletes its local file when done).
                        await PhotoLibrarySaver.save(url, as: .photo)
                        await MainActor.run { UploadQueue.shared.fileReady(sessionID, .strip) }
                    }
                )
                await PhotoLibrarySaver.save(result.liveMP4, as: .video)
                await MainActor.run {
                    self?.result = result
                    UploadQueue.shared.fileReady(sessionID, .live)
                }
            } catch {
                print("Live export failed: \(error)")
                await MainActor.run { self?.failed = true }
            }
        }
    }
}

/// Saves each session's color strip (JPG) and live video (MP4) to the
/// iPad's Photos library. The black & white print version is not saved.
/// Copies the file into Photos, so the upload queue can delete its own copy.
nonisolated enum PhotoLibrarySaver {
    enum Kind { case photo, video }

    static func save(_ file: URL, as kind: Kind) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                request.addResource(with: kind == .photo ? .photo : .video, fileURL: file, options: options)
            }
        } catch {
            print("Saving to Photos failed: \(error)")
        }
    }
}

/// Texting placeholder (on hold — see BoothFeatures.textingEnabled).
/// Uploads are real now (UploadQueue); texting a link via RingCentral is
/// not built. Guest phone numbers are NOT stored anywhere.
nonisolated enum DeliveryService {

    /// TODO: after the upload succeeds, record consent (number, time, booth ID,
    /// consent text version) on the server and send the first text.
    static func requestText(to phoneDigits: String, consentVersion: String) async {
        print("DeliveryService (stub): would text a link (consent \(consentVersion))")
    }
}

/// Plays the live MP4 muted and looping, positioned so the video's strip
/// lands exactly on `stripSize` — the same spot the still StripPreview uses —
/// with the rest of the 9:16 canvas clipped away.
struct LiveStripVideo: View {
    let url: URL
    let frame: BoothFrame
    let stripSize: CGSize

    var body: some View {
        let strip = LiveExporter.stripRect(for: frame)
        let scale = stripSize.width / strip.width
        LoopingPlayerView(url: url)
            .frame(width: LiveExporter.videoSize.width * scale, height: LiveExporter.videoSize.height * scale)
            .offset(x: -strip.minX * scale, y: -strip.minY * scale)
            .frame(width: stripSize.width, height: stripSize.height, alignment: .topLeading)
            .clipped()
    }
}

private struct LoopingPlayerView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerUIView { PlayerUIView(url: url) }
    func updateUIView(_ uiView: PlayerUIView, context: Context) {}

    final class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        private let player = AVQueuePlayer()
        private var looper: AVPlayerLooper?

        init(url: URL) {
            super.init(frame: .zero)
            let playerLayer = layer as! AVPlayerLayer
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.player = player
            player.isMuted = true
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            player.play()
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }
}
