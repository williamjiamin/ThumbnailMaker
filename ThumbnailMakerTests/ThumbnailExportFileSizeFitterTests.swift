//
//  ThumbnailExportFileSizeFitterTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-10: fitting under a byte budget changes only quality.
//

import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import ThumbnailMaker

@MainActor
struct ThumbnailExportFileSizeFitterTests {
    /// bytes = quality * 1000 (monotonic fake encoder).
    private final class FakeEncoder {
        private(set) var qualities: [Double] = []
        func encode(_ quality: Double) -> Data {
            qualities.append(quality)
            return Data(count: Int((quality * 1000).rounded()))
        }
    }

    @Test func withinBudgetEncodesOnce() throws {
        let fake = FakeEncoder()
        let result = try ThumbnailExportFileSizeFitter.fit(
            requestedQuality: 0.9,
            budget: ThumbnailExportFileSizeBudget(maxBytes: 950),
            format: .jpeg,
            encode: fake.encode
        )
        #expect(result.attempts == 1)
        #expect(result.quality == 0.9)
        #expect(result.outcome == .withinBudget)
    }

    @Test func noBudgetEncodesOnce() throws {
        let fake = FakeEncoder()
        let result = try ThumbnailExportFileSizeFitter.fit(requestedQuality: 0.9, budget: nil, format: .jpeg, encode: fake.encode)
        #expect(result.attempts == 1)
        #expect(result.outcome == .noBudget)
    }

    @Test func overBudgetFindsHighestFittingQualityAboveFloor() throws {
        let fake = FakeEncoder()
        let result = try ThumbnailExportFileSizeFitter.fit(
            requestedQuality: 0.92,
            budget: ThumbnailExportFileSizeBudget(maxBytes: 780, qualityFloor: 0.6),
            format: .jpeg,
            encode: fake.encode
        )
        #expect(result.data.count <= 780)
        #expect(result.quality >= 0.6)
        #expect(result.attempts <= ThumbnailExportFileSizeFitter.maxAttempts)
        #expect(result.quality >= 0.75, "Should be close to the best fit, got \(result.quality)")
        #expect(result.outcome == .reducedQuality(from: 0.92, to: result.quality))
        #expect(fake.qualities.allSatisfy { $0 >= 0.6 && $0 <= 0.92 })
    }

    @Test func overBudgetEvenAtFloor() throws {
        let fake = FakeEncoder()
        let result = try ThumbnailExportFileSizeFitter.fit(
            requestedQuality: 0.9,
            budget: ThumbnailExportFileSizeBudget(maxBytes: 100, qualityFloor: 0.6),
            format: .jpeg,
            encode: fake.encode
        )
        #expect(result.outcome == .overBudgetAtFloor(bytes: 600))
        #expect(!result.fitsBudget)
        #expect(fake.qualities == [0.9, 0.6])
    }

    @Test func pngWithBudgetNeverRetries() throws {
        let fake = FakeEncoder()
        let result = try ThumbnailExportFileSizeFitter.fit(
            requestedQuality: 0.9,
            budget: ThumbnailExportFileSizeBudget(maxBytes: 100),
            format: .png,
            encode: fake.encode
        )
        #expect(result.outcome == .overBudgetAtFloor(bytes: 900))
        #expect(fake.qualities.count == 1)
    }

    @Test func cancellationBetweenAttemptsThrows() async {
        let task = Task.detached { () throws -> ThumbnailExportFileSizeFitter.FitResult in
            try ThumbnailExportFileSizeFitter.fit(
                requestedQuality: 0.9,
                budget: ThumbnailExportFileSizeBudget(maxBytes: 10),
                format: .jpeg
            ) { quality in
                withUnsafeCurrentTask { $0?.cancel() }
                return Data(count: Int(quality * 1000))
            }
        }
        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    @Test func realJPEGKeepsSizeAndFormat() throws {
        let width = 1280, height = 720
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        var generator = SystemRandomNumberGenerator()
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            for y in stride(from: 0, to: height, by: 8) {
                for x in stride(from: 0, to: width, by: 8) {
                    UIColor(
                        red: .random(in: 0...1, using: &generator),
                        green: .random(in: 0...1, using: &generator),
                        blue: .random(in: 0...1, using: &generator),
                        alpha: 1
                    ).setFill()
                    context.fill(CGRect(x: x, y: y, width: 8, height: 8))
                }
            }
        }
        var options = ThumbnailExportOptions()
        options.format = .jpeg
        let budget = 150_000
        let requested = try ThumbnailExporter.encodedData(for: image, options: { var o = options; o.compressionQuality = 0.95; return o }())
        #expect(requested.count > budget, "Fixture must start over budget, was \(requested.count)")

        let result = try ThumbnailExportFileSizeFitter.fit(
            requestedQuality: 0.95,
            budget: ThumbnailExportFileSizeBudget(maxBytes: budget, qualityFloor: 0.4),
            format: .jpeg
        ) { quality in
            var attempt = options
            attempt.compressionQuality = quality
            return try ThumbnailExporter.encodedData(for: image, options: attempt)
        }

        if result.fitsBudget {
            #expect(result.data.count <= budget)
        }
        let source = try #require(CGImageSourceCreateWithData(result.data as CFData, nil))
        let type = try #require(CGImageSourceGetType(source) as String?)
        #expect(type == UTType.jpeg.identifier)
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == width)
        #expect(decoded.height == height)
    }
}
