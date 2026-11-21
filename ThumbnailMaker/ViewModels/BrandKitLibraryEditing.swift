//
//  BrandKitLibraryEditing.swift
//  ThumbnailMaker
//
//  FEATURE-08: shared brand kit library + layer style behaviour for both
//  editors. Each view model supplies one private-state primitive
//  (`commitBrandKitLibrary`, at the bottom of its own file); the rest is here.
//
//  Two kinds of change, deliberately different:
//  - Library changes (new/rename/duplicate/delete kit, save/delete style) are
//    persisted to the brand kit store and are NOT document undo steps.
//  - Styling a project (kit or style, whole project or one layer) mutates the
//    document: exactly one undo step, autosaved, per-variant like every edit.
//

import Foundation

@MainActor
protocol BrandKitLibraryEditing: AnyObject {
    var brandKitLibrary: BrandKitLibrary { get }
    var saveError: String? { get set }
    var showingSaveAlert: Bool { get set }

    @discardableResult
    func commitBrandKitLibrary(_ library: BrandKitLibrary) -> Bool
    /// The current document without the background pixels (styling never
    /// reads them; skipping them avoids a PNG encode per call).
    var stylingDocument: ThumbnailDocument { get }
    var currentBranding: ThumbnailDocumentBranding { get }
    /// Applies `transform` to the document as one undo step. Returns false
    /// when nothing changed.
    @discardableResult
    func applyStylingMutation(_ transform: (ThumbnailDocument) -> ThumbnailDocument) -> Bool
}

extension BrandKitLibraryEditing {
    func reportBrandKitError(_ message: String) {
        saveError = message
        showingSaveAlert = true
    }

    // MARK: Badge

    var appliedBrandKitDisplayName: String? {
        guard let kitID = currentBranding.appliedBrandKitID else { return nil }
        return brandKitLibrary.kit(id: kitID)?.name ?? currentBranding.appliedBrandKitName
    }

    var appliedBrandKitIsMissing: Bool {
        guard let kitID = currentBranding.appliedBrandKitID else { return false }
        return brandKitLibrary.kit(id: kitID) == nil
    }

    func appliedStyleName(forLayerID layerID: String) -> String? {
        guard let styleID = currentBranding.styleIDsByLayerID[layerID] else { return nil }
        return brandKitLibrary.style(id: styleID)?.name ?? currentBranding.styleNamesByLayerID[layerID]
    }

    // MARK: Library commands (not document undo)

    /// Adds a fresh default kit and makes it active.
    @discardableResult
    func createBrandKit(named name: String? = nil) -> BrandKit? {
        var library = brandKitLibrary
        guard !library.isFull else {
            reportBrandKitError(BrandKitStoreError.libraryFull.localizedDescription)
            return nil
        }
        var kit = BrandKit.defaultCreatorKit()
        let base = name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? kit.name
        kit.name = BrandKitLibrary.uniqueName(basedOn: base, existing: library.kits.map(\.name))
        library.upsert(kit, activate: true)
        return commitBrandKitLibrary(library) ? kit : nil
    }

    /// Saves edits to an existing kit (or adds it) and makes it active.
    @discardableResult
    func updateBrandKit(_ kit: BrandKit) -> Bool {
        var library = brandKitLibrary
        var kit = kit
        kit.updatedAt = Date()
        guard library.upsert(kit, activate: true) else {
            reportBrandKitError(BrandKitStoreError.libraryFull.localizedDescription)
            return false
        }
        return commitBrandKitLibrary(library)
    }

    @discardableResult
    func duplicateBrandKit(id: String) -> BrandKit? {
        var library = brandKitLibrary
        guard !library.isFull else {
            reportBrandKitError(BrandKitStoreError.libraryFull.localizedDescription)
            return nil
        }
        guard let copy = library.duplicate(id: id) else { return nil }
        return commitBrandKitLibrary(library) ? copy : nil
    }

    @discardableResult
    func renameBrandKit(id: String, to name: String) -> Bool {
        var library = brandKitLibrary
        library.rename(id: id, to: name)
        guard library != brandKitLibrary else { return false }
        return commitBrandKitLibrary(library)
    }

    @discardableResult
    func selectBrandKit(id: String) -> Bool {
        var library = brandKitLibrary
        library.setActive(id: id)
        guard library != brandKitLibrary else { return false }
        return commitBrandKitLibrary(library)
    }

    /// Deletes ONE kit. Projects already styled with it keep their resolved
    /// colors/fonts. Returns the removed kit + index for an Undo toast.
    @discardableResult
    func deleteBrandKit(id: String) -> (kit: BrandKit, index: Int)? {
        var library = brandKitLibrary
        guard let removed = library.remove(id: id) else { return nil }
        return commitBrandKitLibrary(library) ? removed : nil
    }

    @discardableResult
    func restoreBrandKit(_ kit: BrandKit, at index: Int) -> Bool {
        var library = brandKitLibrary
        library.restore(kit, at: index)
        guard library != brandKitLibrary else { return false }
        return commitBrandKitLibrary(library)
    }

    /// Captures a layer's current look into the given (or active) kit. Creates
    /// a default kit first when the library is empty.
    @discardableResult
    func saveLayerStyle(named name: String, fromLayerID layerID: String, inKit kitID: String? = nil) -> ThumbnailLayerStyle? {
        guard let style = ThumbnailLayerStyle.capturing(layerID: layerID, in: stylingDocument, name: name) else {
            reportBrandKitError("This layer has no text or shape styling to save.")
            return nil
        }
        var library = brandKitLibrary
        if library.kits.isEmpty {
            library.upsert(BrandKit.defaultCreatorKit(), activate: true)
        }
        guard let targetKitID = kitID ?? library.activeKitID,
              library.upsertStyle(style, inKit: targetKitID) else {
            reportBrandKitError("Choose a brand kit to save the style into.")
            return nil
        }
        guard commitBrandKitLibrary(library) else { return nil }
        return library.kit(id: targetKitID)?.styles.first { $0.id == style.id }
    }

    @discardableResult
    func deleteLayerStyle(id: String, fromKit kitID: String) -> Bool {
        var library = brandKitLibrary
        library.removeStyle(id: id, fromKit: kitID)
        guard library != brandKitLibrary else { return false }
        return commitBrandKitLibrary(library)
    }

    // MARK: Styling the project (document undo)

    /// One undo step. `.projectWide` also stamps the project's brand badge.
    @discardableResult
    func applyBrandKit(_ kit: BrandKit, to scope: ThumbnailStyleApplicationScope) -> Bool {
        applyStylingMutation { kit.applied(to: $0, scope: scope) }
    }

    /// One undo step. Kind mismatches, locked layers and images are skipped.
    @discardableResult
    func applyLayerStyle(_ style: ThumbnailLayerStyle, to scope: ThumbnailStyleApplicationScope) -> Bool {
        applyStylingMutation { style.applied(to: $0, scope: scope) }
    }

    /// Which style target the given layer accepts, if any.
    func layerStyleTarget(forLayerID layerID: String) -> ThumbnailLayerStyleTarget? {
        ThumbnailLayerStyle.target(forLayerID: layerID, in: stylingDocument)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Per-editor primitives (public API only)

extension SimpleMakerViewModel: BrandKitLibraryEditing {
    var stylingDocument: ThumbnailDocument {
        var probe = simpleMakerConfiguration
        probe.selectedImage = nil
        return probe.document
    }

    var currentBranding: ThumbnailDocumentBranding {
        simpleMakerConfiguration.branding
    }

    @discardableResult
    func applyStylingMutation(_ transform: (ThumbnailDocument) -> ThumbnailDocument) -> Bool {
        commitEditorStateNow()
        let before = stylingDocument
        let after = transform(before)
        guard ThumbnailDocumentHistory.snapshot(before) != ThumbnailDocumentHistory.snapshot(after) else {
            return false
        }
        var configuration = simpleMakerConfiguration
        configuration.adoptStyling(from: after)
        simpleMakerConfiguration = configuration
        commitEditorStateNow()
        exportReport = nil
        return true
    }
}

extension PremiumMakerViewModel: BrandKitLibraryEditing {
    var stylingDocument: ThumbnailDocument {
        var probe = premiumMakerConfiguration
        probe.selectedImage = nil
        return probe.document
    }

    var currentBranding: ThumbnailDocumentBranding {
        premiumMakerConfiguration.branding
    }

    @discardableResult
    func applyStylingMutation(_ transform: (ThumbnailDocument) -> ThumbnailDocument) -> Bool {
        commitEditorStateNow()
        let before = stylingDocument
        let after = transform(before)
        guard ThumbnailDocumentHistory.snapshot(before) != ThumbnailDocumentHistory.snapshot(after) else {
            return false
        }
        var configuration = premiumMakerConfiguration
        configuration.adoptStyling(from: after)
        premiumMakerConfiguration = configuration
        commitEditorStateNow()
        exportReport = nil
        return true
    }
}
