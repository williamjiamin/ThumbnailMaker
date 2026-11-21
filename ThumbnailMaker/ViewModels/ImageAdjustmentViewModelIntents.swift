//
//  ImageAdjustmentViewModelIntents.swift
//  ThumbnailMaker
//
//  FEATURE-14: photo adjustment intents for both editors.
//
//  Two paths, deliberately different:
//  - `updateAdjustments` is the CONTINUOUS slider path. It writes through the
//    configuration so the editor's existing debounced autosave collapses a
//    whole drag into one undo step; `commitAdjustmentsEdit` closes that step
//    as soon as the finger lifts.
//  - `setAdjustments` / `resetAdjustments` / `applyLook` are DISCRETE: each
//    call is exactly one undo step (or none when nothing changes).
//  Image bytes are never touched; only the recipe on the layer record moves.
//

import Foundation

@MainActor
protocol ThumbnailImageAdjustmentEditing: AnyObject {
    var adjustmentLayerRecords: [ThumbnailDocumentLayer] { get set }
    var hasAdjustableBaseImage: Bool { get }
    var hasAdjustableProfileImage: Bool { get }
    func commitEditorStateNow()
}

extension ThumbnailImageAdjustmentEditing {
    var adjustableImages: [ThumbnailAdjustableImage] {
        adjustmentLayerRecords.adjustableImages(
            hasBaseImage: hasAdjustableBaseImage,
            hasProfileImage: hasAdjustableProfileImage
        )
    }

    var hasAdjustableImages: Bool {
        !adjustableImages.isEmpty
    }

    func canAdjust(_ target: ThumbnailAdjustmentTarget) -> Bool {
        adjustmentLayerRecords.canAdjustLayer(
            id: target.layerID,
            hasBaseImage: hasAdjustableBaseImage,
            hasProfileImage: hasAdjustableProfileImage
        )
    }

    func adjustments(for target: ThumbnailAdjustmentTarget) -> ThumbnailImageAdjustments {
        adjustmentLayerRecords.adjustments(for: target)
    }

    /// Continuous path (slider ticks). Rides the debounced autosave.
    func updateAdjustments(_ adjustments: ThumbnailImageAdjustments, for target: ThumbnailAdjustmentTarget) {
        guard canAdjust(target) else { return }
        var layers = adjustmentLayerRecords
        layers.setAdjustments(adjustments, for: target)
        guard layers != adjustmentLayerRecords else { return }
        adjustmentLayerRecords = layers
    }

    /// Closes the undo step opened by `updateAdjustments`.
    func commitAdjustmentsEdit() {
        commitEditorStateNow()
    }

    /// Discrete path: one call is one undo step. Returns false when the
    /// target can't be adjusted or nothing would change.
    @discardableResult
    func setAdjustments(_ adjustments: ThumbnailImageAdjustments, for target: ThumbnailAdjustmentTarget) -> Bool {
        guard canAdjust(target) else { return false }
        var layers = adjustmentLayerRecords
        layers.setAdjustments(adjustments, for: target)
        guard layers != adjustmentLayerRecords else { return false }
        commitEditorStateNow()
        adjustmentLayerRecords = layers
        commitEditorStateNow()
        return true
    }

    @discardableResult
    func resetAdjustments(for target: ThumbnailAdjustmentTarget) -> Bool {
        setAdjustments(.neutral, for: target)
    }

    @discardableResult
    func applyLook(_ look: ThumbnailLook, to target: ThumbnailAdjustmentTarget) -> Bool {
        setAdjustments(look.adjustments, for: target)
    }
}

extension SimpleMakerViewModel: ThumbnailImageAdjustmentEditing {
    var adjustmentLayerRecords: [ThumbnailDocumentLayer] {
        get { simpleMakerConfiguration.layers }
        set { simpleMakerConfiguration.layers = newValue }
    }

    var hasAdjustableBaseImage: Bool { simpleMakerConfiguration.selectedImage != nil }
    var hasAdjustableProfileImage: Bool { false }
}

extension PremiumMakerViewModel: ThumbnailImageAdjustmentEditing {
    var adjustmentLayerRecords: [ThumbnailDocumentLayer] {
        get { premiumMakerConfiguration.layers }
        set { premiumMakerConfiguration.layers = newValue }
    }

    var hasAdjustableBaseImage: Bool { premiumMakerConfiguration.selectedImage != nil }
    var hasAdjustableProfileImage: Bool { premiumMakerConfiguration.circularProfile?.image != nil }
}
