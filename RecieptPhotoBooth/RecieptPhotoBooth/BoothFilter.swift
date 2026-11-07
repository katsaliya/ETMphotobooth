import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// No effects: the camera shows and saves the photo as shot. The only
/// processing left is converting to black and white for the thermal print
/// (and the on-screen "b&w" copy). The color copy and the live preview are
/// untouched. (Contrast, bloom and film grain were removed Nov 5, 2026 at
/// the owner's request.)
enum BoothFilter {

    /// Black-and-white version, used for the printed strip.
    static func apply(to image: CIImage) -> CIImage {
        apply(to: image, saturation: 0)
    }

    /// Color version: returned unchanged. Used for the live preview and the
    /// save/AirDrop copy.
    static func applyColor(to image: CIImage) -> CIImage {
        apply(to: image, saturation: 1)
    }

    private static func apply(to image: CIImage, saturation: Float) -> CIImage {
        guard saturation < 1 else { return image }
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = image
        colorControls.saturation = saturation
        return colorControls.outputImage ?? image
    }

    /// Convenience for converting a captured UIImage to black and white (used
    /// right after each photo is taken, before it's added to the strip).
    static func apply(to uiImage: UIImage) -> UIImage {
        render(uiImage, saturation: 0)
    }

    /// Color counterpart of the above, for the save/AirDrop copy.
    static func applyColor(to uiImage: UIImage) -> UIImage {
        render(uiImage, saturation: 1)
    }

    private static func render(_ uiImage: UIImage, saturation: Float) -> UIImage {
        guard let ciImage = CIImage(image: uiImage) else { return uiImage }
        let flipped = ciImage.transformed(by: CGAffineTransform(scaleX: -1, y: 1))
        let filtered = apply(to: flipped, saturation: saturation)
        let context = CIContext()
        guard let cgImage = context.createCGImage(filtered, from: filtered.extent) else { return uiImage }
        return UIImage(cgImage: cgImage, scale: uiImage.scale, orientation: uiImage.imageOrientation)
    }
}
