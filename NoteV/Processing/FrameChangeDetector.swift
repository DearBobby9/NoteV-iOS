import CoreImage
import Foundation
import UIKit

// MARK: - FrameChangeDetector

/// Shared grayscale downsample + pixel-difference utilities for live and post-stop frame analysis.
enum FrameChangeDetector {

    private static let ciContext = CIContext()
    private static let targetSize = CGSize(width: 64, height: 64)

    /// Normalized L1 pixel distance (0 = identical, 1 = maximally different).
    static func pixelDifference(imageA: [UInt8], imageB: [UInt8]) -> Double {
        guard imageA.count == imageB.count, !imageA.isEmpty else { return 0.0 }

        var totalDiff: Double = 0
        for index in 0..<imageA.count {
            totalDiff += abs(Double(imageA[index]) - Double(imageB[index]))
        }
        return totalDiff / (255.0 * Double(imageA.count))
    }

    static func grayscale(from imageData: Data) -> [UInt8]? {
        guard let ciImage = CIImage(data: imageData) else { return nil }
        return grayscale(from: ciImage)
    }

    static func grayscale(from cgImage: CGImage) -> [UInt8]? {
        grayscale(from: CIImage(cgImage: cgImage))
    }

    static func grayscale(from ciImage: CIImage) -> [UInt8]? {
        let width = Int(targetSize.width)
        let height = Int(targetSize.height)
        let scaleX = targetSize.width / ciImage.extent.width
        let scaleY = targetSize.height / ciImage.extent.height
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        var pixelData = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let rendered = ciContext.createCGImage(scaled, from: CGRect(origin: .zero, size: targetSize)) else {
            return nil
        }

        context.draw(rendered, in: CGRect(origin: .zero, size: targetSize))

        var grayscale = [UInt8](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            let r = Double(pixelData[index * 4])
            let g = Double(pixelData[index * 4 + 1])
            let b = Double(pixelData[index * 4 + 2])
            grayscale[index] = UInt8(0.299 * r + 0.587 * g + 0.114 * b)
        }
        return grayscale
    }
}
