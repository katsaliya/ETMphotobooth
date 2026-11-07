import UIKit

/// Builds the finished strip image (printed, saved to Photos, AirDropped)
/// from the frame the guest picked on the home screen.
///
/// Uses the same template image and photo windows as the on-screen
/// StripPreview (`BoothFrame`), so the print matches what guests saw.
nonisolated enum StripComposer {

    /// Thermal paper width in points. The renderer draws at the device's
    /// screen scale (2x on iPad), so the image itself is 1152px wide; the
    /// printer scales it to this width.
    static let printWidth: CGFloat = 576

    static func composeStrip(photos: [UIImage], frame: BoothFrame) -> UIImage {
        let scale = printWidth / frame.templateSize.width
        let size = CGSize(width: printWidth, height: frame.templateSize.height * scale)

        return UIGraphicsImageRenderer(size: size).image { ctx in
            // White base behind everything.
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // Photos first, one per transparent window...
            for (index, window) in frame.slots.enumerated() where index < photos.count {
                let rect = CGRect(
                    x: window.minX * scale,
                    y: window.minY * scale,
                    width: window.width * scale,
                    height: window.height * scale
                )
                drawAspectFilled(photos[index], in: rect)
            }

            // ...then the template on top: its artwork is opaque and its
            // photo windows are transparent, so the photos show through.
            if let template = UIImage(named: frame.templateImage) {
                template.draw(in: CGRect(origin: .zero, size: size))
            }
        }
    }

    private static func drawAspectFilled(_ image: UIImage, in rect: CGRect) {
        UIGraphicsGetCurrentContext()?.saveGState()
        UIBezierPath(rect: rect).addClip()
        image.draw(in: image.size.aspectFillRect(in: rect))
        UIGraphicsGetCurrentContext()?.restoreGState()
    }
}

nonisolated private extension CGSize {
    /// Aspect-fills `rect`, anchored to the top of the source image instead
    /// of centered — matches FilteredCameraPreview's live crop (top-anchored,
    /// horizontally centered) so what guests see while shooting is exactly
    /// what ends up in the print, not a lower slice of it.
    func aspectFillRect(in rect: CGRect) -> CGRect {
        let scale = max(rect.width / width, rect.height / height)
        let w = width * scale
        let h = height * scale
        return CGRect(x: rect.midX - w / 2, y: rect.minY, width: w, height: h)
    }
}
