//
//  CutoutViewModelIntents.swift
//  ThumbnailMaker
//
//  FEATURE-11: non-destructive cutout intents for both editors.
//
//  - `generateAutomaticCutout` (the existing "Cutout" button) asks the subject
//    processor for a MASK and stores it on the layer record. Image bytes are
//    never rewritten; undo removes the mask.
//  - The async result is tagged with a revision and the exact source it was
//    computed from. It is applied only if the tag is still current AND the
//    target still shows that same image; otherwise it is dropped silently
//    (the newer selection owns the document), like `applyImportedImageData`.
//  - `commitCutoutRefinement` is the refinement sheet's single write: one
//    sheet session is one undo step (or none when nothing changed).
//

import UIKit

/// The pixels a refinement session works on.
struct ThumbnailCutoutSource {
    let target: ThumbnailCutoutTarget
    let image: UIImage
    let pixelWidth: Int
    let pixelHeight: Int
    /// The stored recipe, or nil when there is none / it no longer matches.
    let mask: ThumbnailCutoutMask?
    let title: String
}

@MainActor
protocol ThumbnailCutoutEditing: AnyObject {
    var cutoutLayerRecords: [ThumbnailDocumentLayer] { get set }
    var cutoutBaseImage: UIImage? { get }
    var cutoutRevision: Int { get set }
    var isProcessingSubject: Bool { get set }
    func commitEditorStateNow()
    func reportCutoutError(_ message: String)
}

extension ThumbnailCutoutEditing {
    // MARK: Targets

    /// Mirrors `canRemoveBackground`: an image layer, else the base photo.
    func cutoutTarget(for selection: ThumbnailLayerSelection) -> ThumbnailCutoutTarget? {
        if case .content(let id) = selection,
           let layer = cutoutLayerRecords.record(id: id),
           case .image = layer.content {
            return .contentLayer(id)
        }
        return cutoutBaseImage != nil ? .baseImage : nil
    }

    func canRefineCutout(_ target: ThumbnailCutoutTarget) -> Bool {
        cutoutSource(for: target) != nil
    }

    func cutoutSource(for target: ThumbnailCutoutTarget) -> ThumbnailCutoutSource? {
        let image: UIImage
        let title: String
        switch target {
        case .baseImage:
            guard let base = cutoutBaseImage else { return nil }
            image = base
            title = "Photo"
        case .contentLayer(let id):
            guard let layer = cutoutLayerRecords.record(id: id),
                  case .image(let content) = layer.content,
                  let decoded = UIImage(data: content.imageData) else { return nil }
            image = decoded
            title = layer.name.isEmpty ? "Image" : layer.name
        case .profileImage:
            return nil
        }
        let size = ThumbnailCutoutMaskRenderer.displayPixelSize(of: image)
        guard size.width > 0, size.height > 0 else { return nil }
        let stored = cutoutLayerRecords.cutout(forLayerID: target.layerID)
        let compatible = stored.flatMap {
            $0.isCompatible(withSourcePixelWidth: size.width, height: size.height) ? $0 : nil
        }
        return ThumbnailCutoutSource(
            target: target,
            image: image,
            pixelWidth: size.width,
            pixelHeight: size.height,
            mask: compatible,
            title: title
        )
    }

    func cutout(for target: ThumbnailCutoutTarget) -> ThumbnailCutoutMask? {
        cutoutLayerRecords.cutout(forLayerID: target.layerID)
    }

    // MARK: Automatic subject mask (async, revision-guarded)

    @discardableResult
    func beginCutoutGeneration() -> Int {
        cutoutRevision += 1
        return cutoutRevision
    }

    /// Applies an automatic mask only if `revision` is still current and the
    /// target's image still has the pixel size the mask was generated for.
    /// Stale results are rejected silently. One call is one undo step.
    @discardableResult
    func applyGeneratedCutoutBase(
        _ base: ThumbnailCutoutAutomaticBase,
        to target: ThumbnailCutoutTarget,
        revision: Int
    ) -> Bool {
        guard revision == cutoutRevision,
              let source = cutoutSource(for: target),
              base.sourcePixelWidth == source.pixelWidth,
              base.sourcePixelHeight == source.pixelHeight else {
            return false
        }
        var layers = cutoutLayerRecords
        // A mask for a different photo is replaced, not merged into.
        if source.mask == nil { layers.resetCutout(forLayerID: target.layerID) }
        layers.setAutomaticCutoutBase(base, forLayerID: target.layerID)
        return commitCutoutLayers(layers)
    }

    /// The "Cutout" button. Never rewrites image bytes.
    func generateAutomaticCutout(
        for target: ThumbnailCutoutTarget?,
        using processor: ThumbnailSubjectProcessing
    ) async {
        guard let target, let source = cutoutSource(for: target) else { return }
        let revision = beginCutoutGeneration()
        let sourceIdentity = cutoutSourceIdentity(for: target)
        isProcessingSubject = true
        defer {
            // Only the newest run owns the busy flag.
            if revision == cutoutRevision { isProcessingSubject = false }
        }

        do {
            let base = try await processor.foregroundAlphaMask(from: source.image)
            // The same pixel size is not enough: the target must still show
            // the very image the mask was computed from.
            guard cutoutSourceIdentity(for: target) == sourceIdentity else { return }
            applyGeneratedCutoutBase(base, to: target, revision: revision)
        } catch {
            guard revision == cutoutRevision else { return }
            reportCutoutError("Failed to remove background: \(error.localizedDescription)")
        }
    }

    // MARK: Refinement sheet

    /// The sheet's single write. Returns true when the document changed.
    @discardableResult
    func commitCutoutRefinement(_ mask: ThumbnailCutoutMask?, for target: ThumbnailCutoutTarget) -> Bool {
        guard let source = cutoutSource(for: target) else { return false }
        var recipe = mask
        recipe?.sourcePixelWidth = source.pixelWidth
        recipe?.sourcePixelHeight = source.pixelHeight
        var layers = cutoutLayerRecords
        layers.setCutout(recipe, forLayerID: target.layerID)
        let changed = commitCutoutLayers(layers)
        if changed { prewarmCutout(for: target) }
        return changed
    }

    @discardableResult
    func resetCutout(for target: ThumbnailCutoutTarget) -> Bool {
        var layers = cutoutLayerRecords
        layers.resetCutout(forLayerID: target.layerID)
        return commitCutoutLayers(layers)
    }

    /// Resolves once so the canvas's next synchronous render is a cache hit.
    func prewarmCutout(for target: ThumbnailCutoutTarget) {
        let mask = cutout(for: target)
        switch target {
        case .baseImage:
            if let image = cutoutBaseImage {
                ThumbnailCutoutImageCache.shared.prewarm(
                    image: image,
                    identity: ThumbnailDocumentLayer.backgroundID,
                    mask: mask
                )
            }
        case .contentLayer(let id):
            if let layer = cutoutLayerRecords.record(id: id), case .image(let content) = layer.content {
                ThumbnailCutoutImageCache.shared.prewarm(imageData: content.imageData, identity: id, mask: mask)
            }
        case .profileImage:
            break
        }
    }

    // MARK: Private

    /// Discrete edit: exactly one undo step, or none when nothing changes.
    private func commitCutoutLayers(_ layers: [ThumbnailDocumentLayer]) -> Bool {
        guard layers != cutoutLayerRecords else { return false }
        commitEditorStateNow()
        cutoutLayerRecords = layers
        commitEditorStateNow()
        return true
    }

    private func cutoutSourceIdentity(for target: ThumbnailCutoutTarget) -> String? {
        switch target {
        case .baseImage:
            return cutoutBaseImage.map { ObjectIdentifier($0).debugDescription + $0.thumbnailCutoutInstanceToken }
        case .contentLayer(let id):
            guard let layer = cutoutLayerRecords.record(id: id), case .image(let content) = layer.content else {
                return nil
            }
            return ThumbnailCutoutImageCache.dataToken(content.imageData)
        case .profileImage:
            return nil
        }
    }
}

extension SimpleMakerViewModel: ThumbnailCutoutEditing {
    var cutoutLayerRecords: [ThumbnailDocumentLayer] {
        get { simpleMakerConfiguration.layers }
        set { simpleMakerConfiguration.layers = newValue }
    }

    var cutoutBaseImage: UIImage? { simpleMakerConfiguration.selectedImage }

    func reportCutoutError(_ message: String) {
        isPermissionError = false
        saveError = message
        showingSaveAlert = true
    }
}

extension PremiumMakerViewModel: ThumbnailCutoutEditing {
    var cutoutLayerRecords: [ThumbnailDocumentLayer] {
        get { premiumMakerConfiguration.layers }
        set { premiumMakerConfiguration.layers = newValue }
    }

    var cutoutBaseImage: UIImage? { premiumMakerConfiguration.selectedImage }

    func reportCutoutError(_ message: String) {
        isPermissionError = false
        saveError = message
        showingSaveAlert = true
    }
}
