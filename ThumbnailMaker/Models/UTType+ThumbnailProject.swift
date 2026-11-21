//
//  UTType+ThumbnailProject.swift
//  ThumbnailMaker
//
//  FEATURE-06: the exported .thumbproj package type (declared in Info.plist
//  under UTExportedTypeDeclarations, conforming to com.apple.package).
//

import UniformTypeIdentifiers

extension UTType {
    static let thumbnailMakerProject = UTType(
        exportedAs: ThumbnailProjectPackageLayout.formatIdentifier,
        conformingTo: .package
    )
}
