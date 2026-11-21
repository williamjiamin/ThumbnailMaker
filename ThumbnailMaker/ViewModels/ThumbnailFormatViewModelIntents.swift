//
//  ThumbnailFormatViewModelIntents.swift
//  ThumbnailMaker
//
//  FEATURE-09: alternate-size intents shared by both editors. Every intent
//  settles pending edits, applies exactly one change to
//  `configuration.formatSet`, then settles again, so each call is one undo
//  step and is autosaved. No intent ever changes the original design: they
//  only write the size overrides.
//

import ImageIO
import SwiftUI
import UIKit

// MARK: - Configuration abstraction

protocol ThumbnailFormatEditableConfiguration {
    init(document: ThumbnailDocument)
    var document: ThumbnailDocument { get }
    var formatSet: ThumbnailFormatSet? { get set }
    var selectedImage: UIImage? { get set }
    var imageRecipe: ThumbnailImageFrameRecipe { get set }
    var selectedRatio: AspectRatio { get set }
    var overlayText: String { get set }
    var layers: [ThumbnailDocumentLayer] { get set }
    var exportOptions: ThumbnailExportOptions { get set }
}

extension SimpleMakerConfigurationModel: ThumbnailFormatEditableConfiguration {}
extension PremiumMakerConfigurationModel: ThumbnailFormatEditableConfiguration {}

extension ThumbnailFormatEditableConfiguration {
    /// The document without background bytes: skips a PNG encode and is all
    /// the pure format engines need (they take the image size separately).
    var imagelessDocument: ThumbnailDocument {
        var copy = self
        copy.selectedImage = nil
        return copy.document
    }

    /// A configuration for `document` that reuses this configuration's
    /// already-decoded background image.
    func replacingDocument(_ document: ThumbnailDocument) -> Self {
        var next = Self(document: document)
        next.selectedImage = selectedImage
        return next
    }

    var hasFormatContent: Bool {
        selectedImage != nil || !overlayText.isEmpty || layers.hasContentLayers
    }

    /// Pixel sizes of image layers, read from the file header (no decode).
    var formatLayerImageSizes: [String: CGSize] {
        var sizes: [String: CGSize] = [:]
        for layer in layers {
            if case .image(let content) = layer.content,
               let size = ThumbnailFormatImageMeasure.pixelSize(of: content.imageData) {
                sizes[layer.id] = size
            }
        }
        return sizes
    }
}

enum ThumbnailFormatImageMeasure {
    static func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0 else {
            return nil
        }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        // EXIF orientations 5...8 swap the displayed axes.
        return (5...8).contains(orientation)
            ? CGSize(width: height, height: width)
            : CGSize(width: width, height: height)
    }
}

// MARK: - Editor abstraction

@MainActor
protocol ThumbnailFormatEditing: AnyObject {
    associatedtype FormatConfiguration: ThumbnailFormatEditableConfiguration
    var formatEditorConfiguration: FormatConfiguration { get set }
    var variantExportBaseName: String { get }
    var fileExport: ThumbnailPreparedFileExport? { get set }
    var isFileExporterPresented: Bool { get set }
    var saveError: String? { get set }
    var showingSaveAlert: Bool { get set }
    var isPermissionError: Bool { get set }
    func commitEditorStateNow()
}

extension SimpleMakerViewModel: ThumbnailFormatEditing {
    var formatEditorConfiguration: SimpleMakerConfigurationModel {
        get { simpleMakerConfiguration }
        set { simpleMakerConfiguration = newValue }
    }
}

extension PremiumMakerViewModel: ThumbnailFormatEditing {
    var formatEditorConfiguration: PremiumMakerConfigurationModel {
        get { premiumMakerConfiguration }
        set { premiumMakerConfiguration = newValue }
    }
}

/// One chip's worth of data, resolved once per render.
struct ThumbnailFormatPreview<Configuration: ThumbnailFormatEditableConfiguration>: Identifiable {
    let format: ThumbnailAlternateFormat
    let configuration: Configuration
    let flags: [ThumbnailFormatClipFlag]
    var id: String { format.id }
}

extension ThumbnailFormatEditing {
    var alternateFormats: [ThumbnailAlternateFormat] {
        formatEditorConfiguration.formatSet?.formats ?? []
    }

    var availableFormatKinds: [ThumbnailFormatKind] {
        let configuration = formatEditorConfiguration
        let own = ThumbnailFormatKind.kind(for: configuration.selectedRatio)
        return ThumbnailFormatKind.allCases.filter { kind in
            kind != own && !(configuration.formatSet?.contains(kind) ?? false)
        }
    }

    var canCreateAlternateFormat: Bool {
        formatEditorConfiguration.hasFormatContent && !availableFormatKinds.isEmpty
    }

    func formatExportBaseName(_ id: String) -> String {
        "\(variantExportBaseName)-\(id)"
    }

    // MARK: Intents (each is one undo step)

    /// Adds a size proposed by the reflow engine. Returns its id, or nil when
    /// the size already exists, matches the original ratio, or the design is empty.
    @discardableResult
    func createAlternateFormat(_ kind: ThumbnailFormatKind) -> String? {
        commitEditorStateNow()
        guard availableFormatKinds.contains(kind), formatEditorConfiguration.hasFormatContent else { return nil }
        let format = proposedFormat(kind)
        var set = formatEditorConfiguration.formatSet ?? ThumbnailFormatSet()
        guard set.insert(format) else { return nil }
        applyFormatSet(set)
        return format.id
    }

    @discardableResult
    func commitAlternateFormatEdit(
        _ id: String,
        edited: FormatConfiguration,
        detachedTextLayerIDs: Set<String>? = nil
    ) -> Bool {
        commitEditorStateNow()
        guard let set = ThumbnailFormatLinker.foldBack(
            master: formatEditorConfiguration.imagelessDocument,
            formatID: id,
            edited: edited.imagelessDocument,
            detachedTextLayerIDs: detachedTextLayerIDs
        ) else { return false }
        return applyFormatSet(set)
    }

    /// Re-runs the reflow; keeps unlinked text and per-size hidden layers.
    @discardableResult
    func reproposeAlternateFormat(_ id: String) -> Bool {
        commitEditorStateNow()
        guard var set = formatEditorConfiguration.formatSet,
              let proposal = proposalKeepingUserChoices(id) else { return false }
        set.replace(proposal)
        return applyFormatSet(set)
    }

    @discardableResult
    func resetFormatLayer(_ id: String, layerID: String) -> Bool {
        commitEditorStateNow()
        guard var set = formatEditorConfiguration.formatSet,
              var format = set.format(id: id),
              let proposal = proposalKeepingUserChoices(id) else { return false }
        format.layout[layerID] = proposal.layout[layerID]
        set.replace(format)
        return applyFormatSet(set)
    }

    @discardableResult
    func setFormatLayerHidden(_ id: String, layerID: String, hidden: Bool) -> Bool {
        mutateFormat(id) { format in
            var ids = Set(format.hiddenLayerIDs)
            if hidden { ids.insert(layerID) } else { ids.remove(layerID) }
            format.hiddenLayerIDs = ids.sorted()
        }
    }

    /// Freezes the original's current text for this size only.
    @discardableResult
    func unlinkFormatText(_ id: String, layerID: String) -> Bool {
        let master = formatEditorConfiguration.imagelessDocument
        guard ThumbnailFormatLinker.isTextLayer(layerID, in: master),
              let value = ThumbnailFormatLinker.textValue(layerID, in: master), !value.isEmpty else { return false }
        return mutateFormat(id) { format in
            guard format.detachedText[layerID] == nil else { return }
            format.detachedText[layerID] = value
        }
    }

    /// Drops this size's own text so it follows the original again.
    @discardableResult
    func relinkFormatText(_ id: String, layerID: String) -> Bool {
        mutateFormat(id) { format in
            format.detachedText[layerID] = nil
        }
    }

    @discardableResult
    func removeAlternateFormat(_ id: String) -> Bool {
        commitEditorStateNow()
        guard var set = formatEditorConfiguration.formatSet, set.remove(id: id) else { return false }
        return applyFormatSet(set)
    }

    // MARK: Reads

    func resolvedFormatConfiguration(_ id: String) -> FormatConfiguration? {
        let configuration = formatEditorConfiguration
        guard let resolved = ThumbnailFormatResolver.resolvedDocument(
            master: configuration.imagelessDocument,
            formatID: id,
            layerImageSizes: configuration.formatLayerImageSizes
        ) else { return nil }
        return configuration.replacingDocument(resolved)
    }

    /// A fresh reflow of `id` rendered as a configuration, without saving it.
    func proposedFormatConfiguration(_ id: String) -> FormatConfiguration? {
        guard let proposal = proposalKeepingUserChoices(id) else { return nil }
        let configuration = formatEditorConfiguration
        let resolved = ThumbnailFormatResolver.resolvedDocument(
            master: configuration.imagelessDocument,
            format: proposal,
            layerImageSizes: configuration.formatLayerImageSizes
        )
        return configuration.replacingDocument(resolved)
    }

    func formatClipFlags(_ id: String) -> [ThumbnailFormatClipFlag] {
        guard let kind = ThumbnailFormatKind(rawValue: id),
              let resolved = resolvedFormatConfiguration(id) else { return [] }
        return formatClipFlags(forWorking: resolved, kind: kind)
    }

    /// Live flags for an in-progress (unsaved) edit of a size.
    func formatClipFlags(forWorking working: FormatConfiguration, kind: ThumbnailFormatKind) -> [ThumbnailFormatClipFlag] {
        let configuration = formatEditorConfiguration
        return ThumbnailFormatClipping.analyze(
            resolved: working.imagelessDocument,
            master: configuration.imagelessDocument,
            backgroundImageSize: configuration.selectedImage?.size,
            layerImageSizes: configuration.formatLayerImageSizes,
            safeZone: kind.preset.safeZone
        )
    }

    func alternateFormatPreviews() -> [ThumbnailFormatPreview<FormatConfiguration>] {
        let configuration = formatEditorConfiguration
        guard let set = configuration.formatSet, !set.isEmpty else { return [] }
        let master = configuration.imagelessDocument
        let sizes = configuration.formatLayerImageSizes
        return set.formats.map { format in
            let resolved = ThumbnailFormatResolver.resolvedDocument(master: master, format: format, layerImageSizes: sizes)
            let flags = ThumbnailFormatClipping.analyze(
                resolved: resolved,
                master: master,
                backgroundImageSize: configuration.selectedImage?.size,
                layerImageSizes: sizes,
                safeZone: format.kind.preset.safeZone
            )
            return ThumbnailFormatPreview(
                format: format,
                configuration: configuration.replacingDocument(resolved),
                flags: flags
            )
        }
    }

    /// Masters' current text per layer (what a linked size shows).
    func masterFormatText(_ layerID: String) -> String? {
        ThumbnailFormatLinker.textValue(layerID, in: formatEditorConfiguration.imagelessDocument)
    }

    // MARK: Export

    /// Renders one size through the existing exporter and presents the file
    /// exporter. `content` builds the render view for the resolved size.
    @discardableResult
    func prepareAlternateFormatExport<Content: View>(
        _ id: String,
        content: (FormatConfiguration, CGSize) -> Content
    ) -> Bool {
        commitEditorStateNow()
        guard let kind = ThumbnailFormatKind(rawValue: id),
              let resolved = resolvedFormatConfiguration(id) else {
            reportFormatError("That size no longer exists.")
            return false
        }
        let options = resolved.exportOptions
        do {
            let prepared = try ThumbnailExporter.preparedFileExport(
                content: content(resolved, options.outputSize.cgSize),
                options: options,
                baseFileName: formatExportBaseName(id)
            )
            saveError = nil
            fileExport = prepared
            isFileExporterPresented = true
            return true
        } catch {
            reportFormatError("Failed to export \(kind.displayName): \(error.localizedDescription)")
            return false
        }
    }

    // MARK: Private helpers

    private func proposedFormat(_ kind: ThumbnailFormatKind) -> ThumbnailAlternateFormat {
        let configuration = formatEditorConfiguration
        return ThumbnailFormatReflow.propose(
            master: configuration.imagelessDocument,
            kind: kind,
            sourceImageSize: configuration.selectedImage?.size,
            layerImageSizes: configuration.formatLayerImageSizes
        )
    }

    private func proposalKeepingUserChoices(_ id: String) -> ThumbnailAlternateFormat? {
        guard let existing = formatEditorConfiguration.formatSet?.format(id: id) else { return nil }
        var proposal = proposedFormat(existing.kind)
        proposal.createdAt = existing.createdAt
        proposal.detachedText = existing.detachedText
        proposal.hiddenLayerIDs = existing.hiddenLayerIDs
        return proposal
    }

    private func mutateFormat(_ id: String, _ mutate: (inout ThumbnailAlternateFormat) -> Void) -> Bool {
        commitEditorStateNow()
        guard var set = formatEditorConfiguration.formatSet, var format = set.format(id: id) else { return false }
        mutate(&format)
        set.replace(format)
        return applyFormatSet(set)
    }

    @discardableResult
    private func applyFormatSet(_ set: ThumbnailFormatSet) -> Bool {
        let next = set.nilIfEmpty
        guard next != formatEditorConfiguration.formatSet else { return false }
        formatEditorConfiguration.formatSet = next
        commitEditorStateNow()
        return true
    }

    private func reportFormatError(_ message: String) {
        isPermissionError = false
        saveError = message
        showingSaveAlert = true
    }
}
