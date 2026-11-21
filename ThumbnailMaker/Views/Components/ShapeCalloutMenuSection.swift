//
//  ShapeCalloutMenuSection.swift
//  ThumbnailMaker
//
//  FEATURE-12: the "Arrows, badges & callouts" block dropped into the
//  existing "Add Shape" menus of both editors.
//

import SwiftUI

struct ShapeCalloutMenuSection: View {
    let add: (ThumbnailCalloutPreset) -> Void

    var body: some View {
        Section("Arrows, badges & callouts") {
            ForEach(ThumbnailCalloutPreset.allCases) { preset in
                Button {
                    add(preset)
                } label: {
                    Label(preset.title, systemImage: preset.systemImage)
                }
                .accessibilityIdentifier("addCalloutPreset-\(preset.id)")
            }
        }
    }
}
