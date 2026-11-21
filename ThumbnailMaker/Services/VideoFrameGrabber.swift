//
//  VideoFrameGrabber.swift
//  ThumbnailMaker
//
//  FRAME: AVFoundation + Vision side of "Grab from Video". Everything here is
//  nonisolated and runs off the main actor; it is fully on-device (no network).
//

import AVFoundation
import CoreGraphics
import Foundation
import UIKit
import Vision

enum VideoFrameGrabberError: LocalizedError, Equatable {
    case noVideoTrack
    case unreadable
    case frameUnavailable

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: "This file has no video track."
        case .unreadable: "This video could not be opened."
        case .frameUnavailable: "That frame could not be read from the video."
        }
    }
}

/// A loaded, readable video.
struct VideoFrameSource: Equatable, Sendable {
    let url: URL
    /// Clip duration in seconds.
    let duration: Double
    /// Display size (preferred transform applied), in pixels.
    let displaySize: CGSize
}

/// One suggested frame: its exact decode time, score and a small preview.
struct VideoFrameSuggestion: Identifiable, @unchecked Sendable {
    var id: Double { time }
    let time: Double
    let score: Double
    let hasFace: Bool
    let thumbnail: CGImage

    /// The time to regenerate this exact frame at zero tolerance. The decode
    /// time is nudged half a millisecond forward so rounding can never land
    /// just before the frame's presentation time (the previous frame).
    var decodeTime: Double { time + 0.0005 }
}

enum VideoFrameGrabber {
    static let defaultSampleCount = 40
    static let defaultSuggestionCount = 6
    static let thumbnailLongEdge: CGFloat = 480

    /// Opens `url` and reads its duration and display size.
    static func load(url: URL) async throws -> VideoFrameSource {
        let asset = AVURLAsset(url: url)
        let (duration, isReadable) = try await asset.load(.duration, .isReadable)
        guard isReadable else { throw VideoFrameGrabberError.unreadable }
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoFrameGrabberError.noVideoTrack
        }
        let (naturalSize, transform) = try await track.load(.naturalSize, .preferredTransform)
        let rect = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else { throw VideoFrameGrabberError.unreadable }
        return VideoFrameSource(
            url: url,
            duration: seconds,
            displaySize: CGSize(width: abs(rect.width), height: abs(rect.height))
        )
    }

    /// An image generator for `url`. `exact` uses zero tolerance so the frame
    /// shown is exactly the frame at the requested time.
    static func makeGenerator(url: URL, exact: Bool, maximumSize: CGSize = .zero) -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maximumSize
        if exact {
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
        }
        return generator
    }

    /// The exact, full-resolution frame at `time` (zero tolerance).
    static func frame(at time: Double, url: URL, duration: Double, maximumSize: CGSize = .zero) async throws -> CGImage {
        try Task.checkCancellation()
        let generator = makeGenerator(url: url, exact: true, maximumSize: maximumSize)
        let clamped = VideoFrameTimeline.clampedTime(time, duration: duration)
        do {
            let (image, _) = try await generator.image(at: cmTime(clamped))
            try Task.checkCancellation()
            return image
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw VideoFrameGrabberError.frameUnavailable
        }
    }

    /// Lossless PNG of the exact full-resolution frame at `time`.
    static func pngData(at time: Double, url: URL, duration: Double) async throws -> Data {
        let image = try await frame(at: time, url: url, duration: duration)
        guard let data = UIImage(cgImage: image).pngData() else {
            throw VideoFrameGrabberError.frameUnavailable
        }
        return data
    }

    /// Samples `sampleCount` frames across the clip, scores each and returns
    /// the best `limit` distinct frames, best first. Cooperatively cancellable.
    static func suggestions(
        for source: VideoFrameSource,
        sampleCount: Int = defaultSampleCount,
        limit: Int = defaultSuggestionCount,
        detectsFaces: Bool = true
    ) async throws -> [VideoFrameSuggestion] {
        let times = VideoFrameTimeline.sampleTimes(duration: source.duration, count: sampleCount)
        guard !times.isEmpty else { return [] }
        let bucket = source.duration / Double(times.count)

        // Sampling may snap to a nearby frame; each suggestion keeps the
        // actual decode time so "Use" regenerates the very same frame.
        let generator = makeGenerator(
            url: source.url,
            exact: false,
            maximumSize: CGSize(width: thumbnailLongEdge, height: thumbnailLongEdge)
        )
        let tolerance = cmTime(bucket * 0.25)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        var metrics: [VideoFrameMetrics] = []
        var thumbnails: [Double: CGImage] = [:]
        for time in times {
            try Task.checkCancellation()
            guard let (image, actual) = try? await generator.image(at: cmTime(time)) else { continue }
            let actualSeconds = actual.seconds.isFinite ? actual.seconds : time
            guard thumbnails[actualSeconds] == nil else { continue }
            guard var frame = measure(image, time: actualSeconds, detectsFaces: detectsFaces) else { continue }
            frame.time = actualSeconds
            metrics.append(frame)
            thumbnails[actualSeconds] = image
        }
        try Task.checkCancellation()

        let ranked = VideoFrameScorer.rankDistinct(
            metrics,
            limit: limit,
            minimumSeparation: min(1.0, bucket * 0.9)
        )
        return ranked.compactMap { frame in
            guard let thumbnail = thumbnails[frame.time] else { return nil }
            return VideoFrameSuggestion(
                time: frame.time,
                score: VideoFrameScorer.score(frame),
                hasFace: frame.faceCount > 0,
                thumbnail: thumbnail
            )
        }
    }

    /// Pixel metrics plus (optionally) Vision face metrics for one frame.
    static func measure(_ image: CGImage, time: Double, detectsFaces: Bool) -> VideoFrameMetrics? {
        guard let pixels = VideoFramePixelAnalyzer.analyze(image) else { return nil }
        var metrics = VideoFrameMetrics(
            time: time,
            sharpness: pixels.sharpness,
            meanLuma: pixels.meanLuma,
            lumaDeviation: pixels.lumaDeviation,
            signature: pixels.signature
        )
        // Skip Vision on frames that are rejected anyway.
        if detectsFaces, !VideoFrameScorer.isRejected(metrics) {
            applyFaceMetrics(from: image, to: &metrics)
        }
        return metrics
    }

    /// Face presence/size via VNDetectFaceRectanglesRequest and, when it is
    /// supported on this device, face capture quality. Vision failures count
    /// as "no face" — suggestions still rank on sharpness and exposure.
    static func applyFaceMetrics(from image: CGImage, to metrics: inout VideoFrameMetrics) {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let rectangles = VNDetectFaceRectanglesRequest()
        guard (try? handler.perform([rectangles])) != nil,
              let faces = rectangles.results, !faces.isEmpty else { return }

        metrics.faceCount = faces.count
        let largest = faces.max { lhs, rhs in
            lhs.boundingBox.width * lhs.boundingBox.height < rhs.boundingBox.width * rhs.boundingBox.height
        }
        if let largest {
            metrics.largestFaceArea = Double(largest.boundingBox.width * largest.boundingBox.height)
            let quality = VNDetectFaceCaptureQualityRequest()
            quality.inputFaceObservations = [largest]
            if (try? handler.perform([quality])) != nil,
               let value = quality.results?.first?.faceCaptureQuality {
                metrics.faceCaptureQuality = Double(value)
            }
        }
    }

    static func cmTime(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 90_000)
    }
}
