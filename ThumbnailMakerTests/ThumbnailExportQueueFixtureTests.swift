//
//  ThumbnailExportQueueFixtureTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-10 end to end: 3 variants x 3 YouTube sizes through the REAL
//  renderer, encoder, fitter and a real folder on disk.
//

import Foundation
import ImageIO
import SwiftUI
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import ThumbnailMaker

@MainActor
struct ThumbnailExportQueueFixtureTests {
    private typealias Support = ExportQueueTestSupport

    private struct RGB {
        let r: Int, g: Int, b: Int
        func distance(to other: RGB) -> Int { abs(r - other.r) + abs(g - other.g) + abs(b - other.b) }
    }

    private func pixel(of image: CGImage, x: Int, y: Int) throws -> RGB {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &bytes,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return RGB(r: Int(bytes[0]), g: Int(bytes[1]), b: Int(bytes[2]))
    }

    private func decode(_ url: URL) throws -> (image: CGImage, type: String, bytes: Int) {
        let data = try Data(contentsOf: url)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let type = try #require(CGImageSourceGetType(source) as String?)
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image, type, data.count)
    }

    @Test func threeByThreeYouTubeFixtureWritesExactFiles() async throws {
        let folder = Support.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = FolderExportDestination(folderURL: folder, usesSecurityScope: false)
        let set = Support.threeVariantSet()
        let plan = Support.plan(set: set, recipe: .youTubeABC, destination: try destination.snapshot())
        #expect(plan.runnableJobs.count == 9)

        let runner = ThumbnailExportQueueRunner()
        await runner.run(plan, destination: destination)

        let written = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
        #expect(written == Set(plan.jobs.map(\.targetFileName)))
        #expect(runner.succeededCount + runner.failedCount == 9)

        var cornerBySlot: [ThumbnailVariantSlot: RGB] = [:]
        for job in plan.jobs {
            let url = folder.appendingPathComponent(job.targetFileName)
            guard FileManager.default.fileExists(atPath: url.path) else {
                // Only acceptable when the job reported failure (budget).
                guard case .failed? = runner.state(for: job.id) else {
                    Issue.record("\(job.targetFileName) missing without a failure")
                    continue
                }
                continue
            }
            let decoded = try decode(url)
            #expect(decoded.image.width == job.size.width)
            #expect(decoded.image.height == job.size.height)
            #expect(decoded.type == UTType.jpeg.identifier)
            #expect(decoded.bytes <= 2_000_000)

            let corner = try pixel(of: decoded.image, x: 8, y: 8)
            if let first = cornerBySlot[job.slot] {
                #expect(first.distance(to: corner) < 24, "\(job.id) corner drifted between sizes")
            } else {
                cornerBySlot[job.slot] = corner
            }
        }
        let a = try #require(cornerBySlot[.a]), b = try #require(cornerBySlot[.b]), c = try #require(cornerBySlot[.c])
        #expect(a.distance(to: b) > 100)
        #expect(b.distance(to: c) > 100)
        #expect(a.r > a.g && a.r > a.b)
        #expect(b.g > b.r && b.g > b.b)
        #expect(c.b > c.r && c.b > c.g)

        // Second run with Keep Both: nine "-2" files, originals untouched.
        let originals = try Dictionary(uniqueKeysWithValues: written.map {
            ($0, try Data(contentsOf: folder.appendingPathComponent($0)))
        })
        let secondPlan = Support.plan(set: set, recipe: .youTubeABC, destination: try destination.snapshot())
        #expect(secondPlan.jobs.allSatisfy {
            if case .existsWillRename(let name) = $0.conflict { return name.hasSuffix("-2.jpg") }
            return false
        })
        await runner.run(secondPlan, destination: destination)
        let after = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
        #expect(after.count == 18)
        for (name, data) in originals {
            #expect(try Data(contentsOf: folder.appendingPathComponent(name)) == data)
        }
    }

    @Test func queueRenderMatchesEditorExportPath() throws {
        let set = Support.threeVariantSet()
        let document = try #require(set.document(for: .a))
        let size = ThumbnailExportSize(width: 1920, height: 1080)

        let queued = try ThumbnailQueueDocumentRenderer().render(document, size: size)

        // The editor's single export: PreviewComponentView bound to the live
        // configuration, rendered by ThumbnailExporter at the export options.
        var configuration = document.makeSimpleConfiguration()
        configuration.exportOptions.usesCustomSize = true
        configuration.exportOptions.customSize = size
        let editor = try ThumbnailExporter.render(
            content: PreviewComponentView(
                simpleMakerConfiguration: .constant(configuration),
                width: CGFloat(size.width),
                height: CGFloat(size.height)
            ),
            options: configuration.exportOptions
        )

        let queuedCG = try #require(queued.cgImage)
        let editorCG = try #require(editor.cgImage)
        #expect(queuedCG.width == editorCG.width)
        #expect(queuedCG.height == editorCG.height)
        for (x, y) in [(8, 8), (960, 540), (1900, 1070), (400, 900)] {
            let lhs = try pixel(of: queuedCG, x: x, y: y)
            let rhs = try pixel(of: editorCG, x: x, y: y)
            #expect(lhs.distance(to: rhs) <= 3, "pixel (\(x),\(y)) differs")
        }
    }
}
