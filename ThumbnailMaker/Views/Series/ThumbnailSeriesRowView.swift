//
//  ThumbnailSeriesRowView.swift
//  ThumbnailMaker
//
//  FEATURE-15: one editable series row: title / episode / file name fields,
//  the row's photo, a live preview rendered through the series recipe, its
//  issues and its render status.
//

import PhotosUI
import SwiftUI

struct ThumbnailSeriesRowView: View {
    @ObservedObject var model: ThumbnailSeriesViewModel
    let row: ThumbnailSeriesRow
    let index: Int

    @State private var photoItem: PhotosPickerItem?

    private struct PreviewKey: Equatable {
        let row: ThumbnailSeriesRow
        let sourceDigest: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                preview
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Title", text: Binding(
                        get: { row.title },
                        set: { model.setTitle($0, for: row.id) }
                    ), axis: .vertical)
                    .lineLimit(1...3)
                    .font(.body.weight(.semibold))
                    .accessibilityIdentifier("seriesRowTitleField_\(index)")

                    HStack {
                        TextField("Episode", text: Binding(
                            get: { row.episode ?? "" },
                            set: { model.setEpisode($0, for: row.id) }
                        ))
                        .frame(maxWidth: 90)
                        .accessibilityIdentifier("seriesRowEpisodeField_\(index)")

                        TextField(model.report.outputStems[row.id] ?? "File name", text: Binding(
                            get: { row.outputName ?? "" },
                            set: { model.setOutputName($0, for: row.id) }
                        ))
                        .font(.caption.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("seriesRowNameField_\(index)")
                    }
                    .font(.subheadline)
                    .textFieldStyle(.roundedBorder)
                }
            }

            imageRow

            ForEach(model.issues(for: row.id)) { issue in
                Label(issue.message, systemImage: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(issue.severity == .error ? Color.red : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("seriesRowIssue_\(index)")
            }

            if let status = statusText {
                Text(status.text)
                    .font(.caption)
                    .foregroundStyle(status.color)
                    .accessibilityIdentifier("seriesRowStatus_\(index)")
            }
        }
        .padding(.vertical, 4)
        .disabled(model.isEditingLocked)
        .accessibilityIdentifier("seriesRow_\(index)")
        .task(id: PreviewKey(row: row, sourceDigest: model.source.digest)) {
            // Debounce while typing; a newer edit cancels this task.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await model.loadPreview(for: row.id)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    model.setImage(data, fileName: "photo-row-\(index + 1).jpg", for: row.id)
                } else {
                    model.errorMessage = "Couldn't load that photo."
                }
                photoItem = nil
            }
        }
    }

    private var preview: some View {
        let ratio = AspectRatio(rawValue: model.source.template.document.canvas.aspectRatioRawValue) ?? .ratio16_9
        let dimensions = ratio.dimensions
        let width: CGFloat = 112
        let height = width * dimensions.height / max(dimensions.width, 1)
        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.15))
            if let image = model.previews[row.id] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                ProgressView()
            }
        }
        .frame(width: width, height: min(height, 200))
        .accessibilityLabel("Preview of row \(index + 1)")
    }

    private var imageRow: some View {
        HStack(spacing: 8) {
            Image(systemName: row.imageRef == nil ? "photo.badge.plus" : "photo")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(imageLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            PhotosPicker(selection: $photoItem, matching: .images) {
                Text(row.imageRef == nil ? "Choose Photo" : "Replace")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("seriesRowPhotoButton_\(index)")
            if row.imageRef != nil || row.requestedImageName != nil {
                Button {
                    model.clearImage(for: row.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Remove image")
            }
        }
    }

    private var imageLabel: String {
        if let ref = row.imageRef { return ref.originalFileName }
        if let requested = row.requestedImageName { return "Waiting for \(requested)" }
        return "Uses the source's image"
    }

    private var statusText: (text: String, color: Color)? {
        switch model.status(for: row.id) {
        case .idle, .needsFixing:
            return nil
        case .pending:
            return ("Waiting", .secondary)
        case .rendering:
            return ("Rendering…", .blue)
        case .done(let files):
            return ("Rendered \(files) file\(files == 1 ? "" : "s")", .green)
        case .failed(let message):
            return ("Failed: \(message)", .red)
        case .skipped(let reason):
            return ("Skipped: \(reason)", .secondary)
        case .notRun:
            return ("Not run", .orange)
        }
    }
}
