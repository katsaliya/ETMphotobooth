import UIKit
 
enum StripComposer {

    /// Matches your exported Figma template's pixel dimensions exactly.
    /// Shared by every layout — the thermal paper width never changes.
    static let printWidth: CGFloat = 576

    static func composeStrip(photos: [UIImage], config: FrameConfig) -> UIImage {
        switch config.resolvedTemplateMode {
        case .singlePhoto:
            return composeSinglePhoto(photos: photos)
        case .threePhotoStrip:
            return composeThreePhotoStrip(photos: photos)
        }
    }

    /// Width/height of a single photo slot for the given template — used to
    /// size the live camera preview so what guests see while shooting is
    /// exactly what survives into the print, instead of the preview framing
    /// a taller crop than the slot keeps (which was cutting off heads).
    static func photoSlotAspectRatio(for mode: TemplateMode) -> CGFloat {
        switch mode {
        case .singlePhoto:
            return singlePhotoSlot.width / singlePhotoSlot.height
        case .threePhotoStrip:
            let slot = photoSlots[0]
            return slot.width / slot.height
        }
    }

    // MARK: - Single photo (current default)

    private static let singlePhotoHeight: CGFloat = 768

    /// The transparent photo window in PrintTemplateSingle.png, read
    /// directly off the exported asset's pixel bounds (scaled to printWidth).
    private static let singlePhotoSlot = CGRect(x: 0, y: 173, width: 576, height: 519)

    private static func composeSinglePhoto(photos: [UIImage]) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: printWidth, height: singlePhotoHeight))

        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: printWidth, height: singlePhotoHeight))

            if let photo = photos.first {
                drawAspectFilled(photo, in: singlePhotoSlot)
            }

            if let template = UIImage(named: "PrintTemplateSingle") {
                template.draw(in: CGRect(x: 0, y: 0, width: printWidth, height: singlePhotoHeight))
            }
        }
    }

    // MARK: - 3-photo strip (original layout — kept so we can switch back
    // by flipping FrameConfig.templateMode; nothing else needs to change)

    private static let threePhotoHeight: CGFloat = 1056

    /// PrintTemplate.png has a single full-width transparent window (no
    /// divider lines) from y:180 to y:933 at this print scale — measured
    /// directly off the asset's alpha channel, then split into 3 equal
    /// thirds for the 3 photos. If the template is swapped again, re-measure
    /// and update just these two constants — nothing else needs to change.
    private static let photoSlots: [CGRect] = {
        let bandTop: CGFloat = 180
        let bandHeight: CGFloat = 753
        let slotHeight = bandHeight / 3
        return (0..<3).map { i in
            CGRect(x: 0, y: bandTop + CGFloat(i) * slotHeight, width: 576, height: slotHeight)
        }
    }()

    private static func composeThreePhotoStrip(photos: [UIImage]) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: printWidth, height: threePhotoHeight))

        return renderer.image { ctx in
            // White base — shows through anywhere the template doesn't
            // cover (shouldn't normally be visible, just a safety fill).
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: printWidth, height: threePhotoHeight))

            // Draw each captured photo into its slot FIRST...
            for (index, slot) in photoSlots.enumerated() where index < photos.count {
                drawAspectFilled(photos[index], in: slot)
            }

            // ...then draw the template on top. Its title/tagline/logo
            // areas are opaque and cover the same spots either way, and
            // its photo window is transparent, so the photos show through
            // cleanly underneath.
            if let template = UIImage(named: "PrintTemplate") {
                template.draw(in: CGRect(x: 0, y: 0, width: printWidth, height: threePhotoHeight))
            }
        }
    }

    private static func drawAspectFilled(_ image: UIImage, in rect: CGRect) {
        UIGraphicsGetCurrentContext()?.saveGState()
        UIBezierPath(rect: rect).addClip()
        let aspectRect = image.size.aspectFillRect(in: rect)
        image.draw(in: aspectRect)
        UIGraphicsGetCurrentContext()?.restoreGState()
    }
}
 
private extension CGSize {
    func aspectFillRect(in rect: CGRect) -> CGRect {
        let scale = max(rect.width / width, rect.height / height)
        let w = width * scale
        let h = height * scale
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
}
