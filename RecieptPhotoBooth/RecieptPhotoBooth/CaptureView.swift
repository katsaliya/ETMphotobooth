import SwiftUI
import AVFoundation

/// 03 · Countdown — docs/user-flow.md.
/// Same sides as the home screen: strip on the LEFT (same size and position,
/// so it doesn't jump when the guest taps "I'm ready"), text on the RIGHT.
/// The strip fills in shot by shot: current slot = live camera + outline +
/// big 3-2-1 + LIVE badge; finished slots = the captured photo; upcoming
/// slots = dimmed "Next".
///
/// The camera sequence itself (CameraCaptureManager.runBoothSequence) is
/// unchanged — this view only reads its published state.
struct CaptureView: View {
    @ObservedObject var camera: CameraCaptureManager
    let frame: BoothFrame
    /// Called once all photos are captured, handing the mono (print-matching)
    /// and color (save/AirDrop) sets to RootView to move on to review.
    var onComplete: (_ photos: [UIImage], _ colorPhotos: [UIImage]) -> Void = { _, _ in }

    @ObservedObject private var frameStore = FrameConfigStore.shared
    /// Guards against showing the previous session's photos for the one
    /// render before onAppear resets the sequence.
    @State private var started = false

    /// Same shot-count logic that drives runBoothSequence below, so the
    /// "SHOT N OF Y" label always matches how many photos will be taken.
    private var totalShots: Int {
        frame.photoCount
    }

    /// 1-based shot number currently counting down / just taken.
    private var shotNumber: Int { min(max(camera.currentShotIndex, 1), totalShots) }

    private var shotCopy: BoothCopy.Countdown.Shot {
        let shots = BoothCopy.Countdown.shots
        return shots[min(shotNumber - 1, shots.count - 1)]
    }

    var body: some View {
        Boothbackground(backgroundColor: BoothTheme.background) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    stripColumn(size: CGSize(width: geo.size.width / 2, height: geo.size.height))
                        .frame(width: geo.size.width / 2)

                    BoothTheme.divider
                        .frame(width: 1)
                        .padding(.vertical, 56)

                    textColumn
                        .padding(.horizontal, 56)
                        .padding(.vertical, 40)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            started = true
            // Camera is already running from WelcomeView — no restart needed.
            camera.runBoothSequence(
                shotCount: frame.photoCount,
                interval: frameStore.config.secondsBetweenShots
            ) { photos, colorPhotos in
                onComplete(photos, colorPhotos)
            }
        }
    }

    // MARK: - Right: instructions

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Move this if the booth iPad's front camera sits elsewhere.
            Text(BoothCopy.Countdown.cameraHint)
                .font(BoothTheme.label(17))
                .tracking(2)
                .foregroundStyle(.white)

            Spacer(minLength: 20)

            Text(BoothCopy.Countdown.shotLabel(shotNumber, of: totalShots))
                .font(BoothTheme.label(16))
                .tracking(2)
                .foregroundStyle(.white)
                .contentTransition(.numericText())

            Text("\(shotCopy.lead)\(Text(shotCopy.accent).italic().foregroundStyle(.white))")
                .font(BoothTheme.headline(64))
                .foregroundStyle(.black)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.6)
                .padding(.top, 10)
                .id(shotNumber)
                .transition(.opacity)

            Text(shotCopy.sub)
                .font(BoothTheme.body(22).italic())
                .foregroundStyle(.white)
                .padding(.top, 8)
                .id("sub-\(shotNumber)")
                .transition(.opacity)

            // Thin segmented progress bar under the sub (Figma frames 5–8):
            // only the shot in progress is highlighted.
            HStack(spacing: 10) {
                ForEach(0..<totalShots, id: \.self) { index in
                    Capsule()
                        .fill(index == shotNumber - 1 ? BoothTheme.progressActive : Color.white.opacity(0.35))
                        .frame(height: 5)
                }
            }
            .frame(maxWidth: 380)
            .padding(.top, 22)

            if BoothCopy.Countdown.showLiveClipLine {
                HStack(spacing: 8) {
                    Circle().fill(Color.red).frame(width: 9, height: 9)
                    Text(BoothCopy.Countdown.liveClipLine)
                        .font(BoothTheme.body(15))
                        .foregroundStyle(.white)
                }
                .padding(.top, 12)
            }

            Spacer(minLength: 20)
            // No Cancel: once the countdown starts, the session runs to the end.
        }
        .animation(.easeInOut(duration: 0.25), value: shotNumber)
    }

    // MARK: - Left: strip filling in

    /// Mirrors WelcomeView.previewColumn's geometry exactly (arrow space,
    /// caption block) with those parts invisible, so the strip stays in the
    /// same place and size as on the home screen.
    private func stripColumn(size: CGSize) -> some View {
        let arrowSpace: CGFloat = 2 * (52 + 20)
        let maxStripHeight = size.height - 80 - 110
        let maxStripWidth = size.width - arrowSpace - 40
        let stripWidth = min(maxStripHeight / StripPreview.heightFactor(for: frame), maxStripWidth)

        return VStack(spacing: 0) {
            Spacer(minLength: 40)

            HStack(spacing: 20) {
                Color.clear.frame(width: 52, height: 68)
                StripPreview(frame: frame, width: stripWidth) { index, slotSize in
                    AnyView(CountdownSlot(camera: camera, index: index, size: slotSize, totalShots: totalShots, started: started))
                }
                Color.clear.frame(width: 52, height: 68)
            }

            // Same height as the home screen's caption/dots/hint block.
            VStack(spacing: 10) {
                Text(frame.caption).font(BoothTheme.body(20, weight: .bold))
                Capsule().frame(width: 9, height: 9)
                Text(BoothCopy.Home.swipeHint).font(BoothTheme.body(15))
            }
            .hidden()
            .padding(.top, 22)

            Spacer(minLength: 40)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// One photo slot on the countdown strip. Observes the camera itself (rather
/// than being built inside the parent's closure) so it redraws on every
/// countdown tick — SwiftUI doesn't reliably re-render views passed in as closures.
private struct CountdownSlot: View {
    @ObservedObject var camera: CameraCaptureManager
    let index: Int
    let size: CGSize
    let totalShots: Int
    let started: Bool

    private var shotNumber: Int { min(max(camera.currentShotIndex, 1), totalShots) }
    private var doneCount: Int { started ? camera.capturedColorImages.count : 0 }

    var body: some View {
        if index < doneCount, index < camera.capturedColorImages.count {
            // Finished: the captured photo, top-anchored like the print crop.
            Image(uiImage: camera.capturedColorImages[index])
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipped()
                .transition(.opacity)
        } else if index == shotNumber - 1 {
            currentSlot
        } else {
            // Upcoming: dimmed with a "Next" label.
            ZStack {
                BoothTheme.slotPlaceholder
                Color.black.opacity(0.25)
                Text(BoothCopy.Countdown.nextLabel)
                    .font(BoothTheme.body(max(15, size.height * 0.12), weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    /// Only the numbers 3-2-1 are shown; the camera's own "📸" at the
    /// shutter moment is hidden.
    private var countdownNumber: String? {
        Int(camera.countdownText) != nil ? camera.countdownText : nil
    }

    private var currentSlot: some View {
        ZStack {
            BoothTheme.slotPlaceholder
            FilteredCameraPreview(session: camera.session)

            if let countdownNumber {
                Text(countdownNumber)
                    .font(.system(size: size.height * 0.3, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 6)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.easeInOut(duration: 0.2), value: countdownNumber)
            }
        }
        .overlay(
            Rectangle()
                .strokeBorder(BoothTheme.primaryButton, lineWidth: 4)
        )
    }
}

#Preview {
    CaptureView(camera: CameraCaptureManager(), frame: BoothFrame.all[0])
}
