import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// The booth's signature look: zero saturation, boosted contrast, film
/// grain, and a soft glow. Applied identically to the live camera preview
/// and to captured photos, so what guests see is exactly what prints.
enum BoothFilter {

    static func apply(to image: CIImage) -> CIImage {
        var output = image
        let extent = image.extent

        // 1. Drop saturation to zero, push contrast up.
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = output
        colorControls.saturation = 0
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

    /// Convenience for applying the filter to a captured UIImage (used
    /// right after each photo is taken, before it's added to the strip).
    static func apply(to uiImage: UIImage) -> UIImage {
        guard let ciImage = CIImage(image: uiImage) else { return uiImage }
        let flipped = ciImage.transformed(by: CGAffineTransform(scaleX: -1, y: 1))
        let filtered = apply(to: flipped)
        let context = CIContext()
        guard let cgImage = context.createCGImage(filtered, from: filtered.extent) else { return uiImage }
        return UIImage(cgImage: cgImage, scale: uiImage.scale, orientation: uiImage.imageOrientation)
    }
}
