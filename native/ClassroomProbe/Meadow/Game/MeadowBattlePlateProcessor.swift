import CoreImage
import UIKit

/// Applies restrained camera treatment to the existing battle scene plates.
/// Every result keeps the source canvas and is cached by asset name and role.
enum MeadowBattlePlateProcessor {
    enum Role: String {
        case farForest
        case ground
        case midground
        case foreground
    }

    private static let context = CIContext(options: [.useSoftwareRenderer: false])
    private static let cache = NSCache<NSString, UIImage>()

    static func image(named name: String, role: Role) -> UIImage? {
        let key = "\(role.rawValue):\(name)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = UIImage(named: name) else { return nil }
        if role == .foreground {
            cache.setObject(source, forKey: key)
            return source
        }
        guard let cgImage = source.cgImage,
              let processed = process(cgImage, scale: source.scale, role: role) else {
            cache.setObject(source, forKey: key)
            return source
        }
        cache.setObject(processed, forKey: key)
        return processed
    }

    private static func process(_ source: CGImage, scale: CGFloat, role: Role) -> UIImage? {
        let extent = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let input = CIImage(cgImage: source)
        let controls = CIFilter(name: "CIColorControls")
        controls?.setValue(input, forKey: kCIInputImageKey)

        let saturation: CGFloat
        let contrast: CGFloat
        let blurRadius: CGFloat
        switch role {
        case .farForest:
            saturation = 0.94
            contrast = 0.95
            blurRadius = 3
        case .ground:
            saturation = 0.90
            contrast = 0.96
            blurRadius = 4
        case .midground:
            saturation = 1
            contrast = 0.96
            blurRadius = 1.5
        case .foreground:
            return UIImage(cgImage: source, scale: scale, orientation: .up)
        }

        controls?.setValue(saturation, forKey: kCIInputSaturationKey)
        controls?.setValue(contrast, forKey: kCIInputContrastKey)
        guard let adjusted = controls?.outputImage?.cropped(to: extent) else { return nil }

        let output: CIImage
        switch role {
        case .farForest, .midground:
            output = blur(adjusted, radius: blurRadius, extent: extent) ?? adjusted
        case .ground:
            guard let softened = blur(adjusted, radius: blurRadius, extent: extent),
                  let mask = focusMask(width: source.width, height: source.height) else {
                output = adjusted
                break
            }
            let blend = CIFilter(name: "CIBlendWithMask")
            blend?.setValue(adjusted, forKey: kCIInputImageKey)
            blend?.setValue(softened, forKey: kCIInputBackgroundImageKey)
            blend?.setValue(mask, forKey: kCIInputMaskImageKey)
            output = blend?.outputImage?.cropped(to: extent) ?? adjusted
        case .foreground:
            output = adjusted
        }

        guard let result = context.createCGImage(output.cropped(to: extent), from: extent) else { return nil }
        return UIImage(cgImage: result, scale: scale, orientation: .up)
    }

    private static func blur(_ image: CIImage, radius: CGFloat, extent: CGRect) -> CIImage? {
        guard radius > 0, let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(image.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        return filter.outputImage?.cropped(to: extent)
    }

    /// White keeps the sharp source and black selects the blurred source.
    /// Coordinates are authored from the top edge of the 1309×1201 plates.
    private static func focusMask(width: Int, height: Int) -> CIImage? {
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            let y = CGFloat(row) / CGFloat(max(1, height - 1))
            let focus: CGFloat
            if y < 0.50 || y > 0.90 {
                focus = 0
            } else if y < 0.62 {
                focus = smoothstep((y - 0.50) / 0.12)
            } else if y <= 0.76 {
                focus = 1
            } else {
                focus = 1 - smoothstep((y - 0.76) / 0.14)
            }
            let value = UInt8((min(1, max(0, focus)) * 255).rounded())
            let start = row * width
            pixels.replaceSubrange(start..<(start + width), with: repeatElement(value, count: width))
        }
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: width, height: height,
                                  bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent) else { return nil }
        return CIImage(cgImage: image)
    }

    private static func smoothstep(_ value: CGFloat) -> CGFloat {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }
}
