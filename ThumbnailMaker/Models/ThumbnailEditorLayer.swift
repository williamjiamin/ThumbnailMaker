//
//  ThumbnailEditorLayer.swift
//  ThumbnailMaker
//
//  Created by OpenAI on 2026-06-14.
//

import Foundation

enum ThumbnailEditorLayer: String, CaseIterable, Identifiable {
    case text
    case profile

    var id: String { rawValue }

    var documentLayerID: String {
        switch self {
        case .text:
            ThumbnailDocumentLayer.textID
        case .profile:
            ThumbnailDocumentLayer.profileID
        }
    }

    var documentLayerKind: ThumbnailDocumentLayerKind {
        switch self {
        case .text:
            .text
        case .profile:
            .profile
        }
    }

    var title: String {
        switch self {
        case .text:
            "Text"
        case .profile:
            "Profile"
        }
    }

    var subtitle: String {
        switch self {
        case .text:
            "Overlay"
        case .profile:
            "Circle"
        }
    }

    var systemImage: String {
        switch self {
        case .text:
            "textformat"
        case .profile:
            "person.crop.circle"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .text:
            "layerSelectionText"
        case .profile:
            "layerSelectionProfile"
        }
    }
}

enum ThumbnailLayerSelection: Hashable, Identifiable {
    case textOverlay
    case profileOverlay
    case content(String)

    var id: String {
        documentLayerID
    }

    var documentLayerID: String {
        switch self {
        case .textOverlay:
            ThumbnailDocumentLayer.textID
        case .profileOverlay:
            ThumbnailDocumentLayer.profileID
        case .content(let id):
            id
        }
    }

    var editorLayer: ThumbnailEditorLayer? {
        switch self {
        case .textOverlay:
            .text
        case .profileOverlay:
            .profile
        case .content:
            nil
        }
    }

    init?(documentLayer: ThumbnailDocumentLayer) {
        switch documentLayer.id {
        case ThumbnailDocumentLayer.textID:
            self = .textOverlay
        case ThumbnailDocumentLayer.profileID:
            self = .profileOverlay
        case ThumbnailDocumentLayer.backgroundID:
            return nil
        default:
            self = .content(documentLayer.id)
        }
    }
}
