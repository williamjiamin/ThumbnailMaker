//
//  VideoFrameGrabberTests.swift
//  ThumbnailMakerTests
//
//  FRAME: timeline mapping, pixel metrics, best-frame scoring/ranking, exact
//  frame extraction from a synthetic AVAssetWriter video, stale-result
//  protection, and the undoable editor intents.
//

import AVFoundation
import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import ThumbnailMaker

// MARK: - Timeline

struct VideoFrameTimelineTests {
    @Test func sampleTimesAreBucketCentres() {
        let times = VideoFrameTimeline.sampleTimes(duration: 10, count: 5)
        #expect(times == [1, 3, 5, 7, 9])
    }

    @Test func sampleTimesRejectDegenerateInput() {
        #expect(VideoFrameTimeline.sampleTimes(duration: 0, count: 40).isEmpty)
        #expect(VideoFrameTimeline.sampleTimes(duration: 5, count: 0).isEmpty)
        #expect(VideoFrameTimeline.sampleTimes(duration: .nan, count: 4).isEmpty)
    }

    @Test func fortySamplesStayInsideTheClip() {
        let times = VideoFrameTimeline.sampleTimes(duration: 2, count: 40)
        #expect(times.count == 40)
        #expect(times.first == 0.025)
        #expect(times.allSatisfy { $0 > 0 && $0 < 2 })
        #expect(zip(times, times.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test func fractionAndTimeRoundTripAndClamp() {
        #expect(VideoFrameTimeline.time(forFraction: 0.5, duration: 8) == 4)
        #expect(VideoFrameTimeline.time(forFraction: -1, duration: 8) == 0)
        // Never the exact end, which zero-tolerance decoding cannot serve.
        let end = VideoFrameTimeline.time(forFraction: 2, duration: 8)
        #expect(end < 8)
        #expect(end > 7.99)
        #expect(VideoFrameTimeline.fraction(forTime: 2, duration: 8) == 0.25)
        #expect(VideoFrameTimeline.fraction(forTime: 20, duration: 8) == 1)
        #expect(VideoFrameTimeline.fraction(forTime: 1, duration: 0) == 0)
    }

    @Test func timecodeFormatting() {
        #expect(VideoFrameTimeline.timecode(0) == "0:00.0")
        #expect(VideoFrameTimeline.timecode(7.36) == "0:07.3")
        #expect(VideoFrameTimeline.timecode(125.5) == "2:05.5")
        #expect(VideoFrameTimeline.timecode(3725) == "1:02:05.0")
    }
}

// MARK: - Pixel metrics, scoring and ranking

struct VideoFrameScoringTests {
    @Test func checkerboardIsSharperThanFlatAndBlurredFrames() throws {
        let sharp = try #require(VideoFramePixelAnalyzer.analyze(SyntheticFrames.checkerboard(cell: 4)))
        let flat = try #require(VideoFramePixelAnalyzer.analyze(SyntheticFrames.solid(gray: 128)))
        let gradient = try #require(VideoFramePixelAnalyzer.analyze(SyntheticFrames.gradient()))
        #expect(sharp.sharpness > gradient.sharpness)
        #expect(gradient.sharpness >= flat.sharpness)
        #expect(flat.sharpness < 1)
        #expect(sharp.signature.count == 64)
        #expect(abs(flat.meanLuma - 128.0 / 255.0) < 0.02)
        #expect(flat.lumaDeviation < 0.01)
    }

    @Test func nearBlackWhiteAndFlatFramesAreRejected() throws {
        let black = try #require(VideoFramePixelAnalyzer.analyze(SyntheticFrames.solid(gray: 4)))
        let blackMetrics = VideoFrameMetrics(
            time: 0, sharpness: black.sharpness, meanLuma: black.meanLuma, lumaDeviation: black.lumaDeviation
        )
        #expect(VideoFrameScorer.isRejected(blackMetrics))
        #expect(VideoFrameScorer.isRejected(VideoFrameMetrics(time: 0, sharpness: 900, meanLuma: 0.98, lumaDeviation: 0.2)))
        #expect(VideoFrameScorer.isRejected(VideoFrameMetrics(time: 0, sharpness: 0, meanLuma: 0.5, lumaDeviation: 0.01)))
        #expect(!VideoFrameScorer.isRejected(VideoFrameMetrics(time: 0, sharpness: 300, meanLuma: 0.5, lumaDeviation: 0.2)))
        // A rejected frame scores below any accepted one, even a dull one.
        let dull = VideoFrameMetrics(time: 0, sharpness: 1, meanLuma: 0.2, lumaDeviation: 0.04)
        let crispBlack = VideoFrameMetrics(time: 0, faceCount: 1, largestFaceArea: 0.2, sharpness: 5000, meanLuma: 0.03, lumaDeviation: 0.2)
        #expect(VideoFrameScorer.score(dull) > VideoFrameScorer.score(crispBlack))
    }

    @Test func facesAndFaceSizeAndQualityRaiseTheScore() {
        let base = VideoFrameMetrics(time: 0, sharpness: 300, meanLuma: 0.5, lumaDeviation: 0.2)
        var smallFace = base
        smallFace.faceCount = 1
        smallFace.largestFaceArea = 0.01
        var bigFace = smallFace
        bigFace.largestFaceArea = 0.15
        var bigGoodFace = bigFace
        bigGoodFace.faceCaptureQuality = 0.95
        var bigBadFace = bigFace
        bigBadFace.faceCaptureQuality = 0.05
        #expect(VideoFrameScorer.score(smallFace) > VideoFrameScorer.score(base))
        #expect(VideoFrameScorer.score(bigFace) > VideoFrameScorer.score(smallFace))
        #expect(VideoFrameScorer.score(bigGoodFace) > VideoFrameScorer.score(bigBadFace))
    }

    @Test func sharpnessRaisesTheScore() {
        let blurry = VideoFrameMetrics(time: 0, sharpness: 5, meanLuma: 0.5, lumaDeviation: 0.2)
        let sharp = VideoFrameMetrics(time: 0, sharpness: 800, meanLuma: 0.5, lumaDeviation: 0.2)
        #expect(VideoFrameScorer.score(sharp) > VideoFrameScorer.score(blurry))
        #expect(VideoFrameScorer.sharpnessScore(0) == 0)
        #expect(VideoFrameScorer.sharpnessScore(1_000_000) < 1)
    }

    @Test func rankingSkipsNearDuplicatesAndRejectedFrames() {
        let shotA = Array(repeating: 0.3, count: 64)
        let shotAAgain = Array(repeating: 0.31, count: 64)
        let shotB = Array(repeating: 0.7, count: 64)
        let candidates = [
            VideoFrameMetrics(time: 1, sharpness: 900, meanLuma: 0.5, lumaDeviation: 0.2, signature: shotA),
            // Same shot a second later, slightly worse: a duplicate.
            VideoFrameMetrics(time: 2, sharpness: 850, meanLuma: 0.5, lumaDeviation: 0.2, signature: shotAAgain),
            // Different shot but only 0.1 s from the best frame: too close.
            VideoFrameMetrics(time: 1.1, sharpness: 800, meanLuma: 0.5, lumaDeviation: 0.2, signature: shotB),
            VideoFrameMetrics(time: 3, sharpness: 400, meanLuma: 0.5, lumaDeviation: 0.2, signature: shotB),
            // Black frame: rejected.
            VideoFrameMetrics(time: 5, sharpness: 2000, meanLuma: 0.02, lumaDeviation: 0.2, signature: Array(repeating: 0, count: 64)),
        ]
        let ranked = VideoFrameScorer.rankDistinct(candidates, limit: 6, minimumSeparation: 0.5)
        #expect(ranked.map(\.time) == [1, 3])
    }

    @Test func rankingRespectsLimitAndOrdersBestFirst() {
        let candidates = (0..<20).map { index in
            VideoFrameMetrics(
                time: Double(index),
                sharpness: Double(index * 50),
                meanLuma: 0.5,
                lumaDeviation: 0.2,
                signature: Array(repeating: Double(index) / 10, count: 64)
            )
        }
        let ranked = VideoFrameScorer.rankDistinct(candidates, limit: 6, minimumSeparation: 0.5)
        #expect(ranked.count == 6)
        #expect(ranked.map(\.time) == [19, 18, 17, 16, 15, 14])
        #expect(VideoFrameScorer.rankDistinct(candidates, limit: 0, minimumSeparation: 0).isEmpty)
    }

    @Test func allRejectedClipStillOffersItsBestFrame() {
        let candidates = [
            VideoFrameMetrics(time: 0, sharpness: 10, meanLuma: 0.02, lumaDeviation: 0.01),
            VideoFrameMetrics(time: 4, sharpness: 90, meanLuma: 0.03, lumaDeviation: 0.02),
        ]
        let ranked = VideoFrameScorer.rankDistinct(candidates, limit: 6, minimumSeparation: 1)
        #expect(ranked.first?.time == 4)
    }

    @Test func visionMeasurementOnAFacelessFrameFindsNoFace() throws {
        let metrics = try #require(
            VideoFrameGrabber.measure(SyntheticFrames.checkerboard(cell: 6), time: 1.5, detectsFaces: true)
        )
        #expect(metrics.faceCount == 0)
        #expect(metrics.time == 1.5)
        #expect(metrics.sharpness > 100)
    }
}

// MARK: - Synthetic video

/// 2 s, 10 fps, 160×90 H.264. Frames 0–4 are black (a fade-in); 5–9, 10–14
/// and 15–19 are three visibly different shots. Every frame paints its index
/// along the top edge so tests can tell exactly which frame a decode returned.
enum SyntheticVideo {
    static let width = 160
    static let height = 90
    static let fps: Int32 = 10
    static let frameCount = 20

    static func make() async throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoFrameTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("synthetic.mov")

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 4_000_000],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? VideoFrameGrabberError.unreadable }
        writer.startSession(atSourceTime: .zero)

        for index in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            guard let pool = adaptor.pixelBufferPool else { throw VideoFrameGrabberError.unreadable }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw VideoFrameGrabberError.unreadable }
            paint(buffer, frame: index)
            let time = CMTime(value: CMTimeValue(index), timescale: fps)
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw writer.error ?? VideoFrameGrabberError.unreadable
            }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(frameCount), timescale: fps))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? VideoFrameGrabberError.unreadable }
        return url
    }

    /// The frame index is painted as 5 black/white 16×16 bit patches along
    /// the top edge (bit k at x = 16k), which survives H.264 and colour
    /// conversion exactly.
    static let indexBits = 5

    private static func paint(_ buffer: CVPixelBuffer, frame index: Int) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let value: UInt8
                if y < 16 && x < 16 * indexBits {
                    value = (index >> (x / 16)) & 1 == 1 ? 255 : 0
                } else if index < 5 {
                    value = 0
                } else if index < 10 {
                    value = ((x / 8 + y / 8) % 2 == 0) ? 230 : 30 // fine checkerboard
                } else if index < 15 {
                    value = (y / 6) % 2 == 0 ? 200 : 60 // horizontal stripes
                } else {
                    value = x < width / 2 ? 220 : 50 // split frame with vertical stripes
                        - ((x / 4) % 2 == 0 ? 0 : 20)
                }
                let offset = y * rowBytes + x * 4
                pixels[offset] = value
                pixels[offset + 1] = value
                pixels[offset + 2] = value
                pixels[offset + 3] = 255
            }
        }
    }

    /// Reads the painted frame index back from a decoded frame.
    static func frameIndex(of image: CGImage) -> Int? {
        let width = image.width
        let height = image.height
        guard width >= 16 * indexBits, height >= 16 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        let ok = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        var index = 0
        for bit in 0..<indexBits {
            // Row 8 from the top, centre of the bit's patch. The bitmap
            // context's memory is top-row-first.
            let value = pixels[8 * width + bit * 16 + 8]
            if value > 128 { index |= 1 << bit }
        }
        return index
    }
}

@Suite(.serialized)
struct VideoFrameGrabberVideoTests {
    @Test func loadReadsDurationAndDisplaySize() async throws {
        let url = try await SyntheticVideo.make()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let source = try await VideoFrameGrabber.load(url: url)
        #expect(abs(source.duration - 2.0) < 0.05)
        #expect(source.displaySize == CGSize(width: 160, height: 90))
    }

    @Test(arguments: [(0.0, 0), (0.75, 7), (1.05, 10), (1.349, 13), (1.95, 19), (99.0, 19)])
    func exactFrameExtractionMapsTimeToTheRightFrame(time: Double, expectedIndex: Int) async throws {
        let url = try await SyntheticVideo.make()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let source = try await VideoFrameGrabber.load(url: url)

        // 99 s is past the end: it clamps to the last frame instead of failing.
        let image = try await VideoFrameGrabber.frame(at: time, url: url, duration: source.duration)
        #expect(image.width == 160)
        #expect(image.height == 90)
        let index = SyntheticVideo.frameIndex(of: image)
        #expect(index == expectedIndex, "Zero-tolerance decode must return the frame shown at that time.")
    }

    @Test func pngExportIsLosslessFullResolution() async throws {
        let url = try await SyntheticVideo.make()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let source = try await VideoFrameGrabber.load(url: url)
        let data = try await VideoFrameGrabber.pngData(at: 0.65, url: url, duration: source.duration)
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        let decoded = try #require(UIImage(data: data)?.cgImage)
        #expect(decoded.width == 160)
        #expect(decoded.height == 90)
        #expect(SyntheticVideo.frameIndex(of: decoded) == 6)
    }

    @Test func suggestionsSkipTheBlackIntroAndAreDistinct() async throws {
        let url = try await SyntheticVideo.make()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let source = try await VideoFrameGrabber.load(url: url)
        let suggestions = try await VideoFrameGrabber.suggestions(for: source, detectsFaces: false)

        #expect(!suggestions.isEmpty)
        #expect(suggestions.count <= 6)
        #expect(suggestions.count >= 3, "Three visibly different shots should each be suggested.")
        #expect(suggestions.allSatisfy { $0.time >= 0.5 }, "Black fade-in frames must not be suggested.")
        #expect(Set(suggestions.map(\.time)).count == suggestions.count)
        #expect(zip(suggestions, suggestions.dropFirst()).allSatisfy { $0.score >= $1.score })

        // Each suggestion's decode time regenerates exactly the frame it previewed.
        for suggestion in suggestions {
            let full = try await VideoFrameGrabber.frame(at: suggestion.decodeTime, url: url, duration: source.duration)
            #expect(SyntheticVideo.frameIndex(of: full) == SyntheticVideo.frameIndex(of: suggestion.thumbnail))
        }
    }

    @Test func suggestionsHonourCancellation() async throws {
        let url = try await SyntheticVideo.make()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let source = try await VideoFrameGrabber.load(url: url)
        let task = Task {
            try await VideoFrameGrabber.suggestions(for: source, sampleCount: 400, detectsFaces: false)
        }
        task.cancel()
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
    }

    @Test func nonVideoFileFailsToLoad() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("not-a-video.mov")
        try Data("hello".utf8).write(to: url)
        await #expect(throws: (any Error).self) { try await VideoFrameGrabber.load(url: url) }
    }
}

// MARK: - Model (revisions) and editor intents

@MainActor
@Suite(.serialized)
struct VideoFrameGrabberModelTests {
    private func waitUntil(timeout: Double = 30, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    @Test func newerVideoWinsOverAnOlderInFlightLoad() async throws {
        let first = try await SyntheticVideo.make()
        let second = try await SyntheticVideo.make()
        defer {
            try? FileManager.default.removeItem(at: first.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: second.deletingLastPathComponent())
        }
        let model = VideoFrameGrabberModel(detectsFaces: false)
        model.loadVideo(at: first, ownsFile: false)
        let staleRevision = model.sourceRevision
        model.loadVideo(at: second, ownsFile: false)
        #expect(model.sourceRevision > staleRevision)

        await waitUntil { model.hasAnalyzed }
        #expect(model.source?.url == second)
        #expect(!model.suggestions.isEmpty)
        #expect(!model.isAnalyzing)
        model.reset()
    }

    @Test func seekPublishesOnlyTheNewestPreviewAndExportsIt() async throws {
        let url = try await SyntheticVideo.make()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let model = VideoFrameGrabberModel(detectsFaces: false)
        model.loadVideo(at: url, ownsFile: false)
        await waitUntil { model.source != nil }
        let source = try #require(model.source)

        model.seek(to: 0.55)
        model.seek(to: 1.25)
        #expect(model.currentTime == 1.25)
        await waitUntil { !model.isRenderingPreview }
        let preview = try #require(model.previewImage?.cgImage)
        #expect(SyntheticVideo.frameIndex(of: preview) == 12)

        model.seek(toFraction: 0.9)
        #expect(abs(model.currentTime - 0.9 * source.duration) < 0.0001)
        let exportedData = await model.currentFramePNG()
        let data = try #require(exportedData)
        let exported = try #require(UIImage(data: data)?.cgImage)
        #expect(SyntheticVideo.frameIndex(of: exported) == 18)
        model.reset()
    }

    @Test func resetInvalidatesResultsAndDeletesOwnedCopy() async throws {
        let original = try await SyntheticVideo.make()
        defer { try? FileManager.default.removeItem(at: original.deletingLastPathComponent()) }
        let copy = try VideoFrameGrabberModel.copyToImportDirectory(original)
        #expect(FileManager.default.fileExists(atPath: copy.path))

        let model = VideoFrameGrabberModel(detectsFaces: false)
        model.loadVideo(at: copy, ownsFile: true)
        model.reset()
        #expect(model.phase == .empty)
        #expect(!FileManager.default.fileExists(atPath: copy.path))
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(model.phase == .empty, "A load that finishes after reset must not publish.")
        #expect(model.suggestions.isEmpty)
    }

    private func makeSimpleViewModel(in directory: URL) -> SimpleMakerViewModel {
        SimpleMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json")),
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand.json"))
        )
    }

    private func pngFrame() throws -> Data {
        try #require(UIImage(cgImage: SyntheticFrames.checkerboard(cell: 5)).pngData())
    }

    @Test func frameAsBackgroundIsOneUndoStep() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = makeSimpleViewModel(in: directory)
        #expect(viewModel.simpleMakerConfiguration.selectedImage == nil)

        let outcome = viewModel.applyVideoFrame(try pngFrame(), as: .background)
        #expect(outcome.applied)
        #expect(outcome.selection == nil)
        let image = try #require(viewModel.simpleMakerConfiguration.selectedImage)
        #expect(image.size == CGSize(width: 160, height: 90))
        #expect(viewModel.canUndo)

        viewModel.undo()
        #expect(viewModel.simpleMakerConfiguration.selectedImage == nil)
        #expect(!viewModel.canUndo)
    }

    @Test func frameAsBackgroundMakesAnOlderPhotoImportStale() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = makeSimpleViewModel(in: directory)
        let pendingPhotoRevision = viewModel.beginImageImport()

        #expect(viewModel.applyVideoFrame(try pngFrame(), as: .background).applied)
        let lateOther = try #require(UIImage(cgImage: SyntheticFrames.solid(gray: 90)).pngData())
        #expect(!viewModel.applyImportedImageData(lateOther, revision: pendingPhotoRevision, preservingFrame: true))
        #expect(viewModel.simpleMakerConfiguration.selectedImage?.size == CGSize(width: 160, height: 90))
    }

    @Test func frameAsImageLayerKeepsLosslessBytesAndUndoes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = PremiumMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: directory.appendingPathComponent("premium.json")),
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand.json"))
        )
        let data = try pngFrame()
        let before = viewModel.premiumMakerConfiguration.layers.count

        let outcome = viewModel.applyVideoFrame(data, as: .imageLayer)
        #expect(outcome.applied)
        let selection = try #require(outcome.selection)
        let layer = try #require(viewModel.premiumMakerConfiguration.layers.first { $0.id == selection.documentLayerID })
        guard case .image(let content) = layer.content else {
            Issue.record("The grabbed frame must be an image layer.")
            return
        }
        #expect(content.imageData == data)
        #expect(!content.isSticker)

        viewModel.undo()
        #expect(viewModel.premiumMakerConfiguration.layers.count == before)
    }

    @Test func undecodableFrameIsIgnored() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = makeSimpleViewModel(in: directory)
        let outcome = viewModel.applyVideoFrame(Data("nope".utf8), as: .background)
        #expect(!outcome.applied)
        #expect(!viewModel.canUndo)
    }
}

// MARK: - Synthetic still frames

enum SyntheticFrames {
    static let size = (width: 160, height: 90)

    static func make(_ value: (Int, Int) -> UInt8) -> CGImage {
        let width = size.width
        let height = size.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                pixels[y * width + x] = value(x, y)
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }

    static func checkerboard(cell: Int) -> CGImage {
        make { x, y in (x / cell + y / cell) % 2 == 0 ? 230 : 25 }
    }

    static func solid(gray: UInt8) -> CGImage {
        make { _, _ in gray }
    }

    static func gradient() -> CGImage {
        make { x, _ in UInt8(40 + x) }
    }
}
