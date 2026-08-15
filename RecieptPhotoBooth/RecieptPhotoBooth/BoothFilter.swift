import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// The booth's signature look: boosted contrast, film grain, and a soft
/// glow, applied identically to the live camera preview and to captured
/// photos so what guests see is exactly what prints. The mono (desaturated)
/// variant is used for the preview/print; the color variant is the same
/// treatment without desaturation, used for the digital save/AirDrop copy.
enum BoothFilter {

    /// The mono look used for the live preview and the printed strip.
    static func apply(to image: CIImage) -> CIImage {
        apply(to: image, saturation: 0)
    }

    /// Same contrast/bloom/grain treatment, but in color — used for the
    /// digital save/AirDrop copy. That copy doesn't need to match the
    /// thermal printer's 1-bit dithered output the way the live preview
    /// and the print itself do, so it keeps the booth's look without the
    /// black-and-white conversion.
    static func applyColor(to image: CIImage) -> CIImage {
        apply(to: image, saturation: 1)
    }

    private static func apply(to image: CIImage, saturation: Float) -> CIImage {
        var output = image
        let extent = image.extent

        // 1. Saturation (0 for the mono/print look, 1 = untouched for color), push contrast up.
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = output
        colorControls.saturation = saturation
        colorControls.contrast = 1.08
        colorControls.brightness = -0.03
        output = colorControls.outputImage ?? output

        // 2. Soft glow — a gentle bloom gives that hazy, soft-texture feel
        // without fully blurring detail away. Kept subtle: bloom brightens
        // highlights, and on the thermal printer's 1-bit dithering that
        // extra brightness reads as washed-out, low-detail skin tones.
        let bloom = CIFilter.bloom()
        bloom.inputImage = output
        bloom.intensity = 0.18
        bloom.radius = 5
        output = (bloom.outputImage ?? output).cropped(to: extent)

        // 3. Film grain — generate monochrome noise and soft-light blend
        // it over the image at low strength.
        let noise = CIFilter.randomGenerator().outputImage?.cropped(to: extent)
        if let noise {
            let monoMatrix = CIFilter.colorMatrix()
            monoMatrix.inputImage = noise
            // Collapse RGB into a single gray value so the grain reads as
            // texture, not colored static.
            monoMatrix.rVector = CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0)
            monoMatrix.gVector = CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0)
            monoMatrix.bVector = CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0)
            monoMatrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 0.06) // low opacity grain
            let grain = monoMatrix.outputImage ?? noise

            let blend = CIFilter.softLightBlendMode()
            blend.inputImage = grain
            blend.backgroundImage = output
            output = (blend.outputImage ?? output).cropped(to: extent)
        }

        return output
    }

    /// Convenience for applying the mono filter to a captured UIImage (used
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
