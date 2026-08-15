import SwiftUI
import AVFoundation

/// The countdown/capture screen. Same header (logo + title) and camera
/// box styling as WelcomeView for visual consistency, with the live
/// countdown number overlaid and "smile" shown below in the booth's
/// type style instead of the old star shape.
struct CaptureView: View {
    @ObservedObject var camera: CameraCaptureManager
    /// Called once all photos are captured, handing the mono (print-matching)
    /// and color (save/AirDrop) sets to RootView to move on to review.
    var onComplete: (_ photos: [UIImage], _ colorPhotos: [UIImage]) -> Void = { _, _ in }

    @ObservedObject private var frameStore = FrameConfigStore.shared

    private var shotEmoji: String {
        switch camera.currentShotIndex {
        case 1: return "😜😜😜"
        case 2: return "✌️✌️✌️"
        case 3: return "💋💋💋"
        default: return ""
        }
    }

    /// Same shot-count logic used to drive runBoothSequence below, so the
    /// "x/y" indicator always matches how many photos will actually be taken.
    private var totalShots: Int {
        frameStore.config.resolvedTemplateMode == .singlePhoto ? 1 : frameStore.config.shotCount
    }

    /// Fixed width, height derived from the actual print slot's aspect
    /// ratio — matches WelcomeView so the framing guests see never changes
    /// between the two screens, and matches what survives into the print.
    private let previewWidth: CGFloat = 855
    private var previewHeight: CGFloat {
        previewWidth / StripComposer.photoSlotAspectRatio(for: frameStore.config.resolvedTemplateMode)
    }

    var body: some View {
        Boothbackground {
            VStack(spacing: 0) {
                Spacer().frame(height: 20)

                Image("Logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 239, height: 73)

                EmporiumTitleText(text: "EMPORIUM THAI MARKET")
                    .padding(.top, 6)

                ZStack {
                    FilteredCameraPreview(session: camera.session)
                        .frame(width: previewWidth, height: previewHeight)
                        .clipped()

                    if !camera.countdownText.isEmpty {
                        Text(camera.countdownText)
                            .font(.cossetteTitre(size: 90, weight: .bold))
                            .foregroundColor(EmporiumStyle.accentPink)
                            .shadow(color: .black.opacity(0.5), radius: 10)
                    }

                    if let preview = camera.lastCapturedImage {
                            Image(uiImage: preview)
                                .resizable()
                                .scaledToFill()
                                .frame(width: previewWidth, height: previewHeight)
                                .clipped()
                                .transition(.opacity)
                        }

                    // "x/y" shot progress — set as soon as the countdown for
                    // that shot begins, so it reads correctly through the
                    // whole countdown, not just at the moment of capture.
                    if camera.currentShotIndex > 0 {
                        VStack {
                            HStack {
                                Spacer()
                                Text("\(camera.currentShotIndex)/\(totalShots)")
                                    .font(.epilogue(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(EmporiumStyle.accentPink.opacity(0.85)))
                                    .padding(12)
                            }
                            Spacer()
                        }
                    }
                }
                .frame(width: previewWidth, height: previewHeight)
                .background(EmporiumStyle.boxFill)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .inset(by: 0.5)
                        .stroke(EmporiumStyle.accentPink, lineWidth: 1)
                )
                .padding(.top, 20)

                ZStack {
                    Ellipse()
                        .fill(EmporiumStyle.buttonFill)
                        .overlay(
                            Ellipse().stroke(EmporiumStyle.accentPink, lineWidth: 1)
                        )
                        .frame(width: 252, height: 57)

                    Text(shotEmoji)
                        .font(.system(size: 22))
                }
                .padding(.top, 18)
                Spacer()
            }

            ConsentNoticeText()
            TagUsText()
            
        }
        .onAppear {
            // Camera is already running from WelcomeView — no restart needed.
            // Guest already tapped "start" — begin shooting immediately
            // rather than waiting for another tap here.
            camera.runBoothSequence(
                shotCount: frameStore.config.resolvedTemplateMode == .singlePhoto ? 1 : frameStore.config.shotCount,
                interval: frameStore.config.secondsBetweenShots
            ) { photos, colorPhotos in
                onComplete(photos, colorPhotos)
            }
        }
    }
}

#Preview {
    CaptureView(camera: CameraCaptureManager())
}
