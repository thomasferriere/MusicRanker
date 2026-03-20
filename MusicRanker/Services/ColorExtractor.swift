import SwiftUI
import UIKit

/// Extracts dominant colors from artwork images for dynamic gradient backgrounds
final class ColorExtractor {

    static let shared = ColorExtractor()

    private var cache: [URL: [Color]] = [:]

    /// Extract dominant colors from a URL (downloads the small 100x100 version)
    func extractColors(from url: URL?) async -> [Color] {
        guard let url else { return Self.fallbackColors }

        // Check cache
        if let cached = cache[url] { return cached }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return Self.fallbackColors }
            let colors = dominantColors(from: image)
            cache[url] = colors
            return colors
        } catch {
            return Self.fallbackColors
        }
    }

    /// Fallback gradient when no artwork is available
    static let fallbackColors: [Color] = [
        Color(red: 0.1, green: 0.1, blue: 0.15),
        Color(red: 0.05, green: 0.05, blue: 0.1)
    ]

    // MARK: - Color Extraction

    private func dominantColors(from image: UIImage) -> [Color] {
        guard let cgImage = image.cgImage else { return Self.fallbackColors }

        // Downsample to 10x10 for fast averaging
        let size = 10
        let width = size
        let height = size
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return Self.fallbackColors }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Collect pixel colors
        var rTotal: Double = 0, gTotal: Double = 0, bTotal: Double = 0
        var rTop: Double = 0, gTop: Double = 0, bTop: Double = 0
        var topCount = 0
        let totalPixels = width * height

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * bytesPerPixel
                let r = Double(pixelData[offset]) / 255.0
                let g = Double(pixelData[offset + 1]) / 255.0
                let b = Double(pixelData[offset + 2]) / 255.0

                rTotal += r; gTotal += g; bTotal += b

                // Top third for secondary color
                if y < height / 3 {
                    rTop += r; gTop += g; bTop += b
                    topCount += 1
                }
            }
        }

        let n = Double(totalPixels)
        let avgColor = Color(
            red: rTotal / n * 0.7,
            green: gTotal / n * 0.7,
            blue: bTotal / n * 0.7
        )

        let tn = Double(max(topCount, 1))
        let topColor = Color(
            red: rTop / tn * 0.5,
            green: gTop / tn * 0.5,
            blue: bTop / tn * 0.5
        )

        // Dark base for readability
        let darkBase = Color(red: 0.05, green: 0.05, blue: 0.08)

        return [avgColor, topColor, darkBase]
    }
}
