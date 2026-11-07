import SwiftUI
import AVFoundation

/// On-screen strip for a `BoothFrame`: the real template image, with photos
/// (or the live camera / placeholders) showing through its transparent
/// photo windows.
///
/// Pass `liveSession` to show the live camera in the first slot. Only one
/// FilteredCameraPreview may be on screen at a time (each one adds its own
/// video output to the shared session), so the other slots show the sage
/// placeholder.
struct StripPreview: View {
    let frame: BoothFrame
    let width: CGFloat
    var liveSession: AVCaptureSession? = nil
    /// Optional custom content per slot (index, slot size) — used by the
    /// countdown screen to show live / captured / upcoming states.
    /// Replaces the default placeholder + liveSession behavior when set.
    var slotContent: ((Int, CGSize) -> AnyView)? = nil

    /// Strip height ÷ strip width — lets callers size the strip to fit
    /// the available height.
    static func heightFactor(for frame: BoothFrame) -> CGFloat {
        frame.templateSize.height / frame.templateSize.width
    }

    private var scale: CGFloat { width / frame.templateSize.width }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white

            // Photos go underneath; the template's windows are transparent.
            ForEach(Array(frame.slots.enumerated()), id: \.offset) { index, rect in
                let size = CGSize(width: rect.width * scale, height: rect.height * scale)
                slot(index: index, size: size)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .offset(x: rect.minX * scale, y: rect.minY * scale)
            }

            Image(frame.templateImage)
                .resizable()
                .interpolation(.high)
                .frame(width: width, height: width * Self.heightFactor(for: frame))
                .allowsHitTesting(false)
        }
        .frame(width: width, height: width * Self.heightFactor(for: frame))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }

    @ViewBuilder
    private func slot(index: Int, size: CGSize) -> some View {
        if let slotContent {
            slotContent(index, size)
        } else {
            ZStack {
                BoothTheme.slotPlaceholder
                if index == 0, let liveSession {
                    FilteredCameraPreview(session: liveSession)
                }
            }
        }
    }
}

#Preview {
    HStack(spacing: 30) {
        ForEach(BoothFrame.all) { frame in
            StripPreview(frame: frame, width: 200)
        }
    }
    .padding(40)
    .background(BoothTheme.background)
}
