import SwiftUI
import AVFoundation

/// The countdown/capture screen. Same header (logo + title) and camera
/// box styling as WelcomeView for visual consistency, with the live
/// countdown number overlaid and "smile" shown below in the booth's
/// type style instead of the old star shape.
struct CaptureView: View {
    @ObservedObject var camera: CameraCaptureManager
    /// Called once all 3 photos are captured, handing them to RootView
    /// to move on to the review/export screen.
    var onComplete: ([UIImage]) -> Void = { _ in }

    @ObservedObject private var frameStore = FrameConfigStore.shared
    
    private var shotEmoji: String {
        switch camera.currentShotIndex {
        case 1: return "😜😜😜"
        case 2: return "✌️✌️✌️"
        case 3: return "💋💋💋"
        default: return ""
        }
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
                        .frame(width: 603, height: 398.00992)
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
                                .frame(width: 603, height: 398.00992)
                                .clipped()
                                .transition(.opacity)
                        }
                }
                .frame(width: 603, height: 398.00992)
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
            // Guest already tapped "get receipt" — begin shooting immediately
            // rather than waiting for another tap here.
            camera.runBoothSequence(
                shotCount: frameStore.config.resolvedTemplateMode == .singlePhoto ? 1 : frameStore.config.shotCount,
                interval: frameStore.config.secondsBetweenShots
            ) { photos in
                onComplete(photos)
            }
        }
    }
}

#Preview {
    CaptureView(camera: CameraCaptureManager())
}
