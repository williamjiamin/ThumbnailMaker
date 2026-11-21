//
//  ThumbnailProjectFileDocument.swift
//  ThumbnailMaker
//
//  FEATURE-06: the editable .thumbproj package for fileExporter. Deliberately a
//  separate type from ThumbnailFileDocument, which only exports flattened
//  PNG/JPEG/WebP images.
//

import SwiftUI
import UniformTypeIdentifiers

struct ThumbnailProjectFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.thumbnailMakerProject] }
    static var writableContentTypes: [UTType] { [.thumbnailMakerProject] }

    var package: ThumbnailProjectEncodedPackage

    init(package: ThumbnailProjectEncodedPackage = .empty) {
        self.package = package
    }

    init(configuration: ReadConfiguration) throws {
        let read = try ThumbnailProjectPackageReader.package(from: configuration.file)
        package = try ThumbnailProjectPackageWriter.encode(read.contents)
    }

    var suggestedFileName: String {
        ThumbnailProjectPackageWriter.suggestedFileName(for: package.manifest.name)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        ThumbnailProjectPackageWriter.fileWrapper(for: package)
    }
}
