import UIKit

enum StripComposer {

    /// Standard 80mm thermal printer (e.g. Star mC-Print3) = 576px wide at 203dpi.
    /// Use 384 for 58mm/2" printers (e.g. mC-Print2, mC-Label2).
    static let printWidth: CGFloat = 576

    static func composeStrip(photos: [UIImage], config: FrameConfig) -> UIImage {
        let photoWidth = printWidth - 24 // 12pt margin each side
        let photoHeight = photoWidth * 0.75 // 4:3 crop per shot
        let spacing: CGFloat = 10
        let headerHeight: CGFloat = config.headerText.isEmpty ? 0 : 46
        let footerHeight: CGFloat = config.footerText.isEmpty ? 0 : 60
        let dateHeight: CGFloat = config.showDateTime ? 24 : 0
        let logoHeight: CGFloat = config.logoImageData != nil ? 60 : 0

        let totalHeight = logoHeight + headerHeight
            + (photoHeight + spacing) * CGFloat(photos.count)
            + dateHeight + footerHeight + 24

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: printWidth, height: totalHeight))

        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: printWidth, height: totalHeight))

            var y: CGFloat = 12

            if let logoData = config.logoImageData, let logo = UIImage(data: logoData) {
                let logoWidth = logoHeight * (logo.size.width / logo.size.height)
                logo.draw(in: CGRect(x: (printWidth - logoWidth) / 2, y: y, width: logoWidth, height: logoHeight - 12))
                y += logoHeight
            }

            if !config.headerText.isEmpty {
                drawCentered(config.headerText, y: y, width: printWidth,
                             font: .boldSystemFont(ofSize: 22))
                y += headerHeight
            }

            for photo in photos {
                let rect = CGRect(x: 12, y: y, width: photoWidth, height: photoHeight)
                if config.showBorder {
                    UIColor.black.setStroke()
                    ctx.stroke(rect.insetBy(dx: -1, dy: -1), lineWidth: 2)
                }
                drawAspectFilled(photo, in: rect)
                y += photoHeight + spacing
            }

            if config.showDateTime {
                let df = DateFormatter()
                df.dateFormat = "MM/dd/yy  h:mm a"
                drawCentered(df.string(from: Date()), y: y, width: printWidth,
                             font: .systemFont(ofSize: 14))
                y += dateHeight
            }

            if !config.footerText.isEmpty {
                drawCentered(config.footerText, y: y, width: printWidth,
                             font: .italicSystemFont(ofSize: 16))
            }
        }
    }

    private static func drawCentered(_ text: String, y: CGFloat, width: CGFloat, font: UIFont) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black
        ]
        let size = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: (width - size.width) / 2, y: y), withAttributes: attrs)
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
