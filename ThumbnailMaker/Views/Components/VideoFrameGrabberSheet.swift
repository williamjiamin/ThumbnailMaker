//
//  VideoFrameGrabberSheet.swift
//  ThumbnailMaker
//
//  FRAME: "Grab from Video" — pick a video (Photos or Files), scrub to an
//  exact frame or tap a suggested best frame, then use it as the background
//  or as a new image layer. Everything runs on-device.
//

import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// A picked movie, copied into a private temporary directory on import.
struct PickedVideoFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            PickedVideoFile(url: try VideoFrameGrabberModel.copyToImportDirectory(received.file))
        }
    }
}

struct VideoFrameGrabberSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = VideoFrameGrabberModel()
    @State private var photoSelection: PhotosPickerItem?
    @State private var isFileImporterPresented = false
    @State private var scrubFraction: Double = 0
    @State private var isScrubbing = false
    @State private var photoImportRevision = 0

    /// Receives the lossless PNG and destination; returns whether it applied.
    let apply: (Data, VideoFrameDestination) -> Bool

    @ScaledMetric(relativeTo: .body) private var suggestionHeight: CGFloat = 72

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    pickerRow
                    content
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Grab from Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetToolbarButton(.close) { dismiss() }
                        .accessibilityIdentifier("videoFrameCloseButton")
                }
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.movie],
            allowsMultipleSelection: false
        ) { result in
            importFromFiles(result)
        }
        .onChange(of: photoSelection) { _, newValue in
            guard let newValue else { return }
            importFromPhotos(newValue)
        }
        .onChange(of: model.currentTime) { _, newValue in
            guard !isScrubbing, let source = model.source else { return }
            scrubFraction = VideoFrameTimeline.fraction(forTime: newValue, duration: source.duration)
        }
        .onDisappear { model.reset() }
        .accessibilityIdentifier("videoFrameGrabberSheet")
    }

    // MARK: Picking

    private var pickerRow: some View {
        let pickTitle = model.source == nil ? "Choose Video" : "Other Video"
        return HStack(spacing: 10) {
            PhotosPicker(selection: $photoSelection, matching: .videos, preferredItemEncoding: .current) {
                Label(pickTitle, systemImage: "video")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("videoFramePhotosPicker")

            Button {
                isFileImporterPresented = true
            } label: {
                Label("Files", systemImage: "folder")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("videoFrameFilesButton")
            .accessibilityHint("Choose a video from the Files app.")
        }
    }

    private func importFromPhotos(_ item: PhotosPickerItem) {
        photoImportRevision += 1
        let revision = photoImportRevision
        model.beginExternalImport()
        Task {
            do {
                let picked = try await item.loadTransferable(type: PickedVideoFile.self)
                guard revision == photoImportRevision else {
                    if let picked { try? FileManager.default.removeItem(at: picked.url.deletingLastPathComponent()) }
                    return
                }
                photoSelection = nil
                if let picked {
                    model.loadVideo(at: picked.url, ownsFile: true)
                } else {
                    model.showLoadFailure("That video could not be loaded from Photos.")
                }
            } catch {
                guard revision == photoImportRevision else { return }
                photoSelection = nil
                model.showLoadFailure("That video could not be loaded from Photos.")
            }
        }
    }

    private func importFromFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        photoImportRevision += 1 // a Files pick supersedes a slow Photos transfer
        let revision = photoImportRevision
        model.beginExternalImport()
        Task {
            let copy = await Task.detached(priority: .userInitiated) {
                try? VideoFrameGrabberModel.copyToImportDirectory(url)
            }.value
            guard revision == photoImportRevision else {
                if let copy { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
                return
            }
            if let copy {
                model.loadVideo(at: copy, ownsFile: true)
            } else {
                model.showLoadFailure("That video file could not be opened.")
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .empty:
            emptyState
        case .loading:
            ProgressView("Loading video…")
                .frame(maxWidth: .infinity, minHeight: 160)
                .accessibilityIdentifier("videoFrameLoading")
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("videoFrameError")
        case .ready(let source):
            readyContent(source)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Make a thumbnail from your own video.")
                .font(.headline)
            Text("Scrub to the exact moment, or pick one of the suggested frames — chosen on this device for faces, sharpness and good exposure. Your video never leaves your device.")
                .font(.footnote)
                .foregroundStyle(Color.accessibleSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("videoFrameEmptyState")
    }

    private func readyContent(_ source: VideoFrameSource) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            preview(source)
            scrubber(source)
            suggestionsSection
            actionButtons
        }
    }

    private func preview(_ source: VideoFrameSource) -> some View {
        let aspect = source.displaySize.height > 0 ? source.displaySize.width / source.displaySize.height : 16.0 / 9.0
        return ZStack {
            Color.black
            if let image = model.previewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("Frame at \(VideoFrameTimeline.timecode(model.currentTime))")
            }
            if model.isRenderingPreview && model.previewImage == nil {
                ProgressView().tint(.white)
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: 360)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("videoFramePreview")
    }

    private func scrubber(_ source: VideoFrameSource) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Slider(value: $scrubFraction, in: 0...1) { editing in
                isScrubbing = editing
                if !editing { model.seek(toFraction: scrubFraction) }
            }
            .onChange(of: scrubFraction) { _, newValue in
                if isScrubbing { model.seek(toFraction: newValue) }
            }
            .accessibilityLabel("Video position")
            .accessibilityValue(VideoFrameTimeline.timecode(model.currentTime))
            .accessibilityIdentifier("videoFrameScrubber")

            HStack {
                Text(VideoFrameTimeline.timecode(model.currentTime))
                    .monospacedDigit()
                    .accessibilityIdentifier("videoFrameTimecode")
                Spacer()
                Text(VideoFrameTimeline.timecode(source.duration))
                    .monospacedDigit()
                    .foregroundStyle(Color.accessibleSecondaryText)
            }
            .font(.caption)
            .accessibilityHidden(true)
        }
    }

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Suggested Frames")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if model.isAnalyzing {
                    ProgressView()
                        .accessibilityLabel("Finding the best frames")
                }
            }
            if model.suggestions.isEmpty {
                Text(model.isAnalyzing
                     ? "Looking for sharp, well-lit frames and faces…"
                     : (model.hasAnalyzed ? "No clear frames found — scrub to choose one." : ""))
                    .font(.footnote)
                    .foregroundStyle(Color.accessibleSecondaryText)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(model.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                            suggestionTile(suggestion, rank: index + 1)
                        }
                    }
                }
                .accessibilityIdentifier("videoFrameSuggestions")
            }
        }
    }

    private func suggestionTile(_ suggestion: VideoFrameSuggestion, rank: Int) -> some View {
        let isCurrent = abs(model.currentTime - suggestion.decodeTime) < 0.001
        return Button {
            model.select(suggestion)
        } label: {
            Image(decorative: suggestion.thumbnail, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(width: suggestionHeight * 16 / 9, height: suggestionHeight)
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    Text(VideoFrameTimeline.timecode(suggestion.time))
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 4)
                        .background(.black.opacity(0.6))
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: isCurrent ? 3 : 0)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Suggestion \(rank) at \(VideoFrameTimeline.timecode(suggestion.time))\(suggestion.hasFace ? ", has a face" : "")"
        )
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityIdentifier("videoFrameSuggestion_\(rank)")
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            ForEach(VideoFrameDestination.allCases) { destination in
                Button {
                    use(destination)
                } label: {
                    Label(destination.title, systemImage: destination == .background ? "photo.artframe" : "photo.on.rectangle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(destination == .background ? .accentColor : .secondary)
                .disabled(model.isExporting)
                .accessibilityIdentifier(destination == .background ? "videoFrameUseBackground" : "videoFrameAddLayer")
            }
            if model.isExporting {
                ProgressView("Capturing full-resolution frame…")
            }
        }
    }

    private func use(_ destination: VideoFrameDestination) {
        Task {
            guard let data = await model.currentFramePNG() else { return }
            if apply(data, destination) { dismiss() }
        }
    }
}
