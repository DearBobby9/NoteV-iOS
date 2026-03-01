import Foundation
import UIKit

// MARK: - FrameDeduplicator

/// Deduplicates captured frames using perceptual hashing (pHash).
/// Groups same-slide frames and picks the sharpest (Laplacian variance) as representative.
final class FrameDeduplicator {

    // MARK: - Deduplicate

    /// Deduplicate frames by perceptual hash similarity.
    /// Returns ordered unique slides with the sharpest representative frame for each group.
    func deduplicate(frames: [TimestampedFrame], imageStore: ImageStore, sessionId: UUID) -> [UniqueSlide] {
        guard !frames.isEmpty else { return [] }

        NSLog("[FrameDeduplicator] Processing \(frames.count) frames")

        // Load images and compute pHash + sharpness for each frame
        var frameInfos: [(frame: TimestampedFrame, hash: UInt64, sharpness: Double)] = []

        for frame in frames {
            guard let imageData = imageStore.loadImage(filename: frame.imageFilename, sessionId: sessionId),
                  let uiImage = UIImage(data: imageData) else {
                continue
            }

            let hash = computePHash(image: uiImage)
            let sharpness = computeSharpness(image: uiImage)
            frameInfos.append((frame, hash, sharpness))
        }

        guard !frameInfos.isEmpty else { return [] }

        // Group frames by pHash similarity (sequential comparison)
        var groups: [[(frame: TimestampedFrame, hash: UInt64, sharpness: Double)]] = []
        var currentGroup: [(frame: TimestampedFrame, hash: UInt64, sharpness: Double)] = [frameInfos[0]]

        for i in 1..<frameInfos.count {
            let distance = hammingDistance(frameInfos[i].hash, currentGroup[0].hash)
            if distance <= NoteVConfig.SlideAnalysis.pHashThreshold {
                currentGroup.append(frameInfos[i])
            } else {
                groups.append(currentGroup)
                currentGroup = [frameInfos[i]]
            }
        }
        groups.append(currentGroup)

        // Build unique slides — pick sharpest frame per group
        let maxSlides = NoteVConfig.SlideAnalysis.maxUniqueSlides
        var slides: [UniqueSlide] = []

        for (index, group) in groups.prefix(maxSlides).enumerated() {
            let best = group.max(by: { $0.sharpness < $1.sharpness })!
            let slide = UniqueSlide(
                representativeFrame: best.frame.imageFilename,
                timestamp: best.frame.timestamp,
                slideNumber: index + 1,
                extractedText: nil,
                duplicateCount: group.count
            )
            slides.append(slide)
        }

        NSLog("[FrameDeduplicator] Deduplicated \(frameInfos.count) frames → \(slides.count) unique slides")
        return slides
    }

    // MARK: - Perceptual Hash

    /// Compute a 64-bit perceptual hash.
    /// Resize to 32x32 grayscale → DCT-like → top-left 8x8 → median threshold.
    private func computePHash(image: UIImage) -> UInt64 {
        let size = 32
        guard let cgImage = image.cgImage,
              let context = CGContext(
                data: nil,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: size,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else {
            return 0
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        guard let data = context.data else { return 0 }
        let buffer = data.bindMemory(to: UInt8.self, capacity: size * size)

        // Extract 8x8 top-left low-frequency components
        var values: [Double] = []
        for y in 0..<8 {
            for x in 0..<8 {
                // Average a 4x4 block to simulate DCT low-frequency
                var sum: Double = 0
                for dy in 0..<4 {
                    for dx in 0..<4 {
                        sum += Double(buffer[(y * 4 + dy) * size + (x * 4 + dx)])
                    }
                }
                values.append(sum / 16.0)
            }
        }

        // Median threshold
        let sorted = values.sorted()
        let median = sorted[sorted.count / 2]

        var hash: UInt64 = 0
        for (i, value) in values.enumerated() {
            if value > median {
                hash |= (1 << i)
            }
        }

        return hash
    }

    // MARK: - Sharpness (Laplacian Variance)

    /// Compute sharpness via Laplacian variance — higher = sharper.
    private func computeSharpness(image: UIImage) -> Double {
        let size = 64
        guard let cgImage = image.cgImage,
              let context = CGContext(
                data: nil,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: size,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else {
            return 0
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        guard let data = context.data else { return 0 }
        let buffer = data.bindMemory(to: UInt8.self, capacity: size * size)

        // Simple Laplacian (3x3 kernel: 0,-1,0 / -1,4,-1 / 0,-1,0)
        var sum: Double = 0
        var sumSq: Double = 0
        var count = 0

        for y in 1..<(size - 1) {
            for x in 1..<(size - 1) {
                let center = Double(buffer[y * size + x]) * 4
                let top = Double(buffer[(y - 1) * size + x])
                let bottom = Double(buffer[(y + 1) * size + x])
                let left = Double(buffer[y * size + (x - 1)])
                let right = Double(buffer[y * size + (x + 1)])
                let laplacian = center - top - bottom - left - right

                sum += laplacian
                sumSq += laplacian * laplacian
                count += 1
            }
        }

        guard count > 0 else { return 0 }
        let mean = sum / Double(count)
        let variance = (sumSq / Double(count)) - (mean * mean)
        return variance
    }

    // MARK: - Hamming Distance

    private func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }
}
