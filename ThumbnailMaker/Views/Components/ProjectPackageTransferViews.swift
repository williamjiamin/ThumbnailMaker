//
//  ProjectPackageTransferViews.swift
//  ThumbnailMaker
//
//  FEATURE-06: small views used by the project library sheet for .thumbproj
//  import/export feedback.
//

import SwiftUI
import UniformTypeIdentifiers

struct ProjectTransferBanner: Equatable {
    var message: String
    var isError: Bool
}

struct ProjectTransferBannerView: View {
    let banner: ProjectTransferBanner
    let dismissAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(banner.isError ? Color.orange : Color.green)
            Text(banner.message)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismissAction) {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(
            (banner.isError ? Color.orange : Color.green).opacity(0.12),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(banner.isError ? "projectTransferError" : "projectTransferNotice")
    }
}

/// Kept on a different view than the sheet's `.fileImporter`: SwiftUI only
/// honours one file-panel modifier per view.
struct ProjectPackageExporterModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var document: ThumbnailProjectFileDocument?
    @Binding var banner: ProjectTransferBanner?

    func body(content: Content) -> some View {
        content.fileExporter(
            isPresented: $isPresented,
            document: document ?? ThumbnailProjectFileDocument(),
            contentType: .thumbnailMakerProject,
            defaultFilename: document?.suggestedFileName ?? "Thumbnail Project"
        ) { result in
            let name = document?.package.manifest.name ?? "Project"
            document = nil
            switch result {
            case .success:
                banner = ProjectTransferBanner(message: "Exported \"\(name)\" as an editable project.", isError: false)
            case .failure(let error):
                guard (error as NSError).code != NSUserCancelledError else { return }
                banner = ProjectTransferBanner(
                    message: ThumbnailProjectPackageError.writeFailed(error.localizedDescription).userMessage,
                    isError: true
                )
            }
        }
    }
}
