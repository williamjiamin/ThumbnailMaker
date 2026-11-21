//
//  ThumbnailFileDocument.swift
//  ThumbnailMaker
//

import SwiftUI
import UniformTypeIdentifiers

struct ThumbnailFileDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.png, .jpeg, .webP]
    }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
