//
//  ExportQueueTestSupport.swift
//  ThumbnailMakerTests
//
//  FEATURE-10 shared helpers: an in-memory destination with injectable
//  failures, a counting renderer, and a 3-variant 16:9 fixture set.
//

import Foundation
import SwiftUI
import UIKit
@testable import ThumbnailMaker

@MainActor
final class InMemoryExportDestination: ThumbnailExportDestinationWriting {
    var displayName = "Test Folder"
    var supportsFileNames = true
    /// Lowercased name -> bytes.
    private(set) var files: [String: Data] = [:]
    /// Original-case names in write order.
    private(set) var writtenNames: [String] = []
    /// File names whose next write throws (removed after the first failure when `failOnce`).
    var failingFileNames: Set<String> = []
    var failOnce = false
    /// Called after every successful write with the running count.
    var afterWrite: ((Int) -> Void)?

    struct InjectedFailure: LocalizedError {
        let name: String
        var errorDescription: String? { "Injected failure for \(name)" }
    }

    func seed(_ names: [String]) {
        for name in names { files[name.lowercased()] = Data([0x00]) }
    }

    func data(named name: String) -> Data? { files[name.lowercased()] }

    func snapshot() throws -> ThumbnailExportDestinationSnapshot {
        ThumbnailExportDestinationSnapshot(
            displayName: displayName,
            existingFileNames: supportsFileNames ? Set(files.keys) : [],
            supportsFileNames: supportsFileNames
        )
    }

    func write(
        _ data: Data,
        fileName: String,
        format: ThumbnailExportFormat,
        policy: ThumbnailExportOverwritePolicy
    ) async throws -> ThumbnailExportWriteResult {
        if failingFileNames.contains(fileName) {
            if failOnce { failingFileNames.remove(fileName) }
            throw InjectedFailure(name: fileName)
        }
        var target = fileName
        let exists = files[fileName.lowercased()] != nil
        if supportsFileNames && exists {
            switch policy {
            case .skip: return .skippedExisting(fileName: fileName)
            case .keepBoth: target = ThumbnailVariantExportNaming.uniqueName(fileName, taken: Set(files.keys))
            case .replace: break
            }
        }
        files[target.lowercased()] = data
        writtenNames.append(target)
        afterWrite?(writtenNames.count)
        return .written(fileName: target, url: nil)
    }
}

@MainActor
final class CountingExportRenderer: ThumbnailExportJobRendering {
    private(set) var renderCount = 0
    private(set) var renderedSlotsAndSizes: [String] = []

    func render(_ document: ThumbnailDocument, size: ThumbnailExportSize) throws -> UIImage {
        renderCount += 1
        renderedSlotsAndSizes.append("\(document.text.value)-\(size.width)x\(size.height)")
        // Small stand-in bitmap: the runner never inspects pixel size.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 32, height: 18), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 18))
        }
    }
}

enum ExportQueueTestSupport {
    static func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FEATURE10-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func document(
        text: String,
        color: ThumbnailDocumentColor,
        ratio: AspectRatio = .ratio16_9,
        editorMode: ThumbnailDocumentEditorMode = .simple
    ) -> ThumbnailDocument {
        ThumbnailDocument(
            editorMode: editorMode,
            canvas: ThumbnailDocumentCanvas(aspectRatioRawValue: ratio.rawValue, backgroundColor: color),
            text: ThumbnailDocumentText(value: text)
        )
    }

    static let red = ThumbnailDocumentColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1)
    static let green = ThumbnailDocumentColor(red: 0.1, green: 0.8, blue: 0.2, alpha: 1)
    static let blue = ThumbnailDocumentColor(red: 0.1, green: 0.2, blue: 0.9, alpha: 1)

    /// Three 16:9 simple-mode variants (A red, B green, C blue), B preferred.
    static func threeVariantSet(projectName: String = "My Video", ratio: AspectRatio = .ratio16_9) -> ThumbnailVariantSet {
        let now = Date(timeIntervalSince1970: 1_000)
        let colors = [red, green, blue]
        let variants = ThumbnailVariantSlot.allCases.enumerated().map { index, slot in
            ThumbnailVariant(
                slot: slot,
                name: slot.defaultName,
                createdAt: now,
                updatedAt: now,
                document: document(text: slot.displayLetter, color: colors[index], ratio: ratio)
            )
        }
        return ThumbnailVariantSet(
            updatedAt: now,
            editorMode: .simple,
            projectName: projectName,
            activeSlot: .a,
            preferredSlot: .b,
            variants: variants
        )
    }

    static func singleVariantSet(ratio: AspectRatio = .ratio16_9) -> ThumbnailVariantSet {
        ThumbnailVariantSet(
            seedDocument: document(text: "Solo", color: red, ratio: ratio),
            editorMode: .simple
        )
    }

    /// A small, fast recipe: 3 in-range 16:9 sizes, JPEG, no budget.
    static func smallRecipe(policy: ThumbnailExportOverwritePolicy = .keepBoth) -> ThumbnailExportRecipe {
        ThumbnailExportRecipe(
            name: "Small",
            sizes: [
                ThumbnailExportRecipeSize(width: 1280, height: 720),
                ThumbnailExportRecipeSize(width: 960, height: 540),
                ThumbnailExportRecipeSize(width: 640, height: 360)
            ],
            format: .jpeg,
            compressionQuality: 0.9,
            overwritePolicy: policy
        )
    }

    static func plan(
        set: ThumbnailVariantSet = threeVariantSet(),
        recipe: ThumbnailExportRecipe = .youTubeABC,
        destination: ThumbnailExportDestinationSnapshot = ThumbnailExportDestinationSnapshot(displayName: "Folder", supportsFileNames: true),
        formatIsAvailable: @escaping (ThumbnailExportFormat) -> Bool = { _ in true }
    ) -> ThumbnailExportQueuePlan {
        ThumbnailExportQueuePlan.make(
            set: set,
            recipe: recipe,
            projectName: "",
            fallbackBaseName: ThumbnailExportPreset.youTubeThumbnail.id,
            destination: destination,
            formatIsAvailable: formatIsAvailable
        )
    }

    static func context(set: ThumbnailVariantSet = threeVariantSet(), projectID: UUID? = nil) -> ThumbnailExportQueueContext {
        ThumbnailExportQueueContext(
            variantSet: set,
            projectID: projectID,
            projectName: "",
            fallbackBaseName: ThumbnailExportPreset.youTubeThumbnail.id,
            currentOptions: ThumbnailExportOptions()
        )
    }
}
