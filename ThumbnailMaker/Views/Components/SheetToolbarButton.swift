//
//  SheetToolbarButton.swift
//  ThumbnailMaker
//
//  APP-07: sheet navigation-bar actions as glyphs (the iOS 26 sheet
//  convention) whose symbols scale with Dynamic Type. Text bar buttons keep a
//  fixed size, which the Dynamic Type audit reports. The spoken label keeps
//  the familiar word, so VoiceOver, Voice Control and tests still say
//  "Done", "Cancel" or "Save".
//

import SwiftUI

struct SheetToolbarButton: View {
    enum Kind {
        case done
        case cancel
        case save
        case close

        var title: String {
            switch self {
            case .done: "Done"
            case .cancel: "Cancel"
            case .save: "Save"
            case .close: "Close"
            }
        }

        var systemImage: String {
            switch self {
            case .done, .save: "checkmark"
            case .cancel, .close: "xmark"
            }
        }

        var weight: Font.Weight {
            switch self {
            case .done, .save: .semibold
            case .cancel, .close: .regular
            }
        }
    }

    let kind: Kind
    let action: () -> Void

    init(_ kind: Kind, action: @escaping () -> Void) {
        self.kind = kind
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: kind.systemImage)
                .font(.body.weight(kind.weight))
        }
        .accessibilityLabel(kind.title)
        .help(kind.title)
    }
}
