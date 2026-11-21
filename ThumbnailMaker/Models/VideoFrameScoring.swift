//
//  VideoFrameScoring.swift
//  ThumbnailMaker
//
//  FRAME: pure, deterministic pieces of "Grab from Video" — timeline/time
//  mapping, per-frame pixel metrics, the best-frame score and the distinct
//  top-N ranking. Nothing here touches AVFoundation or Vision, so every rule
//  is unit-testable with synthetic frames.
//

import CoreGraphics
import Foundation

// MARK: - Timeline mapping

enum VideoFrameTimeline {
    /// Sample times for `count` suggestions: the centre of each of `count`
    /// equal buckets across the clip, so the first and last frames (often a
    /// fade from/to black) are never sampled exactly.
    static func sampleTimes(duration: Double, count: Int) -> [Double] {
        guard duration.isFinite, duration > 0, count > 0 else { return [] }
        let bucket = duration / Double(count)
        return (0..<count).map { index in
            clampedTime((Double(index) + 0.5) * bucket, duration: duration)
        }
    }

    /// Scrubber fraction (0...1) → clip time, clamped inside the clip.
    static func time(forFraction fraction: Double, duration: Double) -> Double {
        guard duration.isFinite, duration > 0, fraction.isFinite else { return 0 }
        return clampedTime(min(max(fraction, 0), 1) * duration, duration: duration)
    }

    /// Clip time → scrubber fraction (0...1).
    static func fraction(forTime time: Double, duration: Double) -> Double {
        guard duration.isFinite, duration > 0, time.isFinite else { return 0 }
        return min(max(time / duration, 0), 1)
    }

    /// The last decodable instant is slightly before `duration`; asking for
    /// exactly `duration` with zero tolerance fails on many files.
    static func clampedTime(_ time: Double, duration: Double) -> Double {
        guard duration.isFinite, duration > 0, time.isFinite else { return 0 }
        let lastFrame = max(0, duration - 1.0 / 600.0)
        return min(max(time, 0), lastFrame)
    }

    /// "m:ss.t" (or "h:mm:ss.t" for long clips), for the scrubber readout.
    static func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00.0" }
        let tenths = Int((seconds * 10).rounded(.down))
        let totalSeconds = tenths / 10
        let fraction = tenths % 10
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d.%d", hours, minutes, secs, fraction)
        }
        return String(format: "%d:%02d.%d", minutes, secs, fraction)
    }
}

// MARK: - Metrics

/// Everything the ranker knows about one sampled frame.
struct VideoFrameMetrics: Equatable, Sendable {
    var time: Double
    /// Number of detected faces.
    var faceCount: Int = 0
    /// Largest face bounding box area, as a fraction of the frame (0...1).
    var largestFaceArea: Double = 0
    /// Vision face capture quality of the largest face (0...1), when available.
    var faceCaptureQuality: Double?
    /// Laplacian variance of the 0...255 luma plane (higher = sharper).
    var sharpness: Double = 0
    /// Mean luma, 0...1.
    var meanLuma: Double = 0.5
    /// Luma standard deviation, 0...1 (flat/transition frames are ~0).
    var lumaDeviation: Double = 0.2
    /// Coarse 8×8 luma signature (0...1 per cell) used for diversity.
    var signature: [Double] = []
}

// MARK: - Pixel analysis

enum VideoFramePixelAnalyzer {
    static let signatureSide = 8
    /// Frames are analysed at most this many pixels on the long edge.
    static let analysisLongEdge = 256

    struct Result: Equatable, Sendable {
        var sharpness: Double
        var meanLuma: Double
        var lumaDeviation: Double
        var signature: [Double]
    }

    /// Luma statistics for `image`, computed on a downscaled 8-bit gray copy.
    static func analyze(_ image: CGImage) -> Result? {
        let longEdge = max(image.width, image.height)
        guard longEdge > 0 else { return nil }
        let scale = min(1, Double(analysisLongEdge) / Double(longEdge))
        let width = max(3, Int((Double(image.width) * scale).rounded()))
        let height = max(3, Int((Double(image.height) * scale).rounded()))

        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        return analyze(luma: pixels, width: width, height: height)
    }

    /// Statistics for a raw 8-bit luma plane (row-major, `width * height`).
    static func analyze(luma pixels: [UInt8], width: Int, height: Int) -> Result? {
        guard width >= 3, height >= 3, pixels.count >= width * height else { return nil }

        let count = Double(width * height)
        var sum = 0.0
        var sumSquares = 0.0
        for value in pixels.prefix(width * height) {
            let v = Double(value)
            sum += v
            sumSquares += v * v
        }
        let mean = sum / count
        let variance = max(0, sumSquares / count - mean * mean)

        // 4-neighbour Laplacian over the interior.
        var lapSum = 0.0
        var lapSquares = 0.0
        var lapCount = 0.0
        for y in 1..<(height - 1) {
            let row = y * width
            for x in 1..<(width - 1) {
                let index = row + x
                let laplacian = Double(pixels[index - width]) + Double(pixels[index + width])
                    + Double(pixels[index - 1]) + Double(pixels[index + 1])
                    - 4 * Double(pixels[index])
                lapSum += laplacian
                lapSquares += laplacian * laplacian
                lapCount += 1
            }
        }
        let lapMean = lapSum / lapCount
        let lapVariance = max(0, lapSquares / lapCount - lapMean * lapMean)

        // Block-average signature.
        let side = signatureSide
        var cells = [Double](repeating: 0, count: side * side)
        var cellCounts = [Double](repeating: 0, count: side * side)
        for y in 0..<height {
            let cy = min(side - 1, y * side / height)
            for x in 0..<width {
                let cx = min(side - 1, x * side / width)
                cells[cy * side + cx] += Double(pixels[y * width + x])
                cellCounts[cy * side + cx] += 1
            }
        }
        let signature = zip(cells, cellCounts).map { total, n in n > 0 ? total / n / 255.0 : 0 }

        return Result(
            sharpness: lapVariance,
            meanLuma: mean / 255.0,
            lumaDeviation: variance.squareRoot() / 255.0,
            signature: signature
        )
    }
}

// MARK: - Scoring and ranking

enum VideoFrameScorer {
    /// Mean luma below this is a near-black / fade frame.
    static let nearBlackLuma = 0.07
    /// Mean luma above this is a blown-out / flash / white-card frame.
    static let nearWhiteLuma = 0.96
    /// Luma deviation below this is a flat frame (solid card, cross-fade mush).
    static let flatDeviation = 0.035
    /// Signatures closer than this (RMS, 0...1) count as the same shot.
    static let duplicateSignatureDistance = 0.06

    /// Frames nobody wants as a thumbnail: near-black, near-white or flat.
    static func isRejected(_ metrics: VideoFrameMetrics) -> Bool {
        metrics.meanLuma < nearBlackLuma
            || metrics.meanLuma > nearWhiteLuma
            || metrics.lumaDeviation < flatDeviation
    }

    /// Saturating 0...1 sharpness score from Laplacian variance.
    static func sharpnessScore(_ laplacianVariance: Double) -> Double {
        guard laplacianVariance.isFinite, laplacianVariance > 0 else { return 0 }
        return laplacianVariance / (laplacianVariance + 250)
    }

    /// 0...1 face score: presence, size (a big face reads at thumbnail size)
    /// and Vision's capture quality when it is available.
    static func faceScore(_ metrics: VideoFrameMetrics) -> Double {
        guard metrics.faceCount > 0 else { return 0 }
        let size = min(1, max(0, metrics.largestFaceArea) / 0.12)
        let quality = min(1, max(0, metrics.faceCaptureQuality ?? 0.5))
        return 0.4 + 0.35 * size + 0.25 * quality
    }

    /// Overall 0...1 score; rejected frames score below every accepted one.
    static func score(_ metrics: VideoFrameMetrics) -> Double {
        let exposure = 1 - pow(min(1, abs(metrics.meanLuma - 0.5) / 0.5), 2)
        let contrast = min(1, max(0, metrics.lumaDeviation) / 0.22)
        let value = 0.45 * faceScore(metrics)
            + 0.30 * sharpnessScore(metrics.sharpness)
            + 0.15 * contrast
            + 0.10 * exposure
        return isRejected(metrics) ? value - 1 : value
    }

    /// RMS distance between two signatures (0...1), or nil when unknown.
    static func signatureDistance(_ lhs: [Double], _ rhs: [Double]) -> Double? {
        guard !lhs.isEmpty, lhs.count == rhs.count else { return nil }
        var total = 0.0
        for (a, b) in zip(lhs, rhs) {
            total += (a - b) * (a - b)
        }
        return (total / Double(lhs.count)).squareRoot()
    }

    /// The best `limit` distinct frames, best first. A candidate is skipped
    /// when it is within `minimumSeparation` seconds of, or looks like the
    /// same shot as, a frame already picked. Rejected frames are only used if
    /// nothing else is left (an all-dark clip still offers something).
    static func rankDistinct(
        _ candidates: [VideoFrameMetrics],
        limit: Int,
        minimumSeparation: Double
    ) -> [VideoFrameMetrics] {
        guard limit > 0 else { return [] }
        let ordered = candidates.sorted { lhs, rhs in
            let l = score(lhs)
            let r = score(rhs)
            return l == r ? lhs.time < rhs.time : l > r
        }
        let accepted = ordered.filter { !isRejected($0) }
        let pool = accepted.isEmpty ? ordered : accepted

        var picked: [VideoFrameMetrics] = []
        for candidate in pool where picked.count < limit {
            let isDistinct = picked.allSatisfy { chosen in
                if abs(chosen.time - candidate.time) < minimumSeparation { return false }
                if let distance = signatureDistance(chosen.signature, candidate.signature),
                   distance < duplicateSignatureDistance {
                    return false
                }
                return true
            }
            if isDistinct { picked.append(candidate) }
        }
        return picked
    }
}
