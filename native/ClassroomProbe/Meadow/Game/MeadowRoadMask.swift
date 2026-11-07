import UIKit

/// Union of distances to every road segment, in world pixels. Junctions share
/// one mask/material, so overlapping paths never create a seam or dark stripe.
enum MeadowRoadMask {
    static func make(network: TrailNetwork, bounds: CGRect, progress: ((Double) -> Void)? = nil) -> CGImage {
        let width = Int(bounds.width), height = Int(bounds.height)
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let segments = network.edges.reduce(0) { $0 + max(0, $1.trail.points.count - 1) }
        var completed = 0
        for edge in network.edges {
            let radius = edge.width * 0.5 + 9
            for (a, b) in zip(edge.trail.points, edge.trail.points.dropFirst()) {
                defer { completed += 1; progress?(Double(completed) / Double(max(1, segments))) }
                let dx = b.x - a.x, dy = b.y - a.y
                let length2 = dx * dx + dy * dy
                guard length2 > 0.001 else { continue }
                let minX = max(0, Int(floor(min(a.x, b.x) - radius - bounds.minX)))
                let maxX = min(width - 1, Int(ceil(max(a.x, b.x) + radius - bounds.minX)))
                let minY = max(0, Int(floor(min(a.y, b.y) - radius - bounds.minY)))
                let maxY = min(height - 1, Int(ceil(max(a.y, b.y) + radius - bounds.minY)))
                guard minX <= maxX, minY <= maxY else { continue }
                for y in minY...maxY { for x in minX...maxX {
                    let px = CGFloat(x) + bounds.minX + 0.5, py = CGFloat(y) + bounds.minY + 0.5
                    let t = max(0, min(1, ((px - a.x) * dx + (py - a.y) * dy) / length2))
                    let distance = hypot(px - a.x - t * dx, py - a.y - t * dy)
                    guard distance < radius else { continue }
                    let coverage = UInt8(min(255, max(0, (1 - distance / radius) * 255)))
                    let rutDistance = abs(distance - edge.width * 0.22)
                    let rut = UInt8(max(0, 1 - rutDistance / max(2, edge.width * 0.10)) * 255)
                    let i = (y * width + x) * 4
                    rgba[i] = max(rgba[i], coverage)
                    rgba[i + 1] = max(rgba[i + 1], rut)
                    rgba[i + 3] = 255
                } }
            }
        }
        // Keep coverage in RGB, not premultiplied alpha; the shader owns feathering.
        for i in stride(from: 3, to: rgba.count, by: 4) { rgba[i] = 255 }
        let data = Data(rgba) as CFData
        guard let provider = CGDataProvider(data: data), let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { fatalError("Road mask allocation failed") }
        return image
    }
}
