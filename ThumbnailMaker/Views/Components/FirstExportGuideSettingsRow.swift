//
//  FirstExportGuideSettingsRow.swift
//  ThumbnailMaker
//
//  FEATURE-13: Settings entry point to resume or restart the first-export
//  guide. Changes guide progress only, never projects or documents.
//

import SwiftUI

struct FirstExportGuideSettingsRow: View {
    @ObservedObject var guide: FirstExportGuideController
    var onShow: () -> Void

    init(guide: FirstExportGuideController? = nil, onShow: @escaping () -> Void = {}) {
        self.guide = guide ?? .shared
        self.onShow = onShow
    }

    var body: some View {
        Section(header: Text("Getting Started")) {
            Button {
                guide.showFromSettings()
                onShow()
            } label: {
                Label(buttonTitle, systemImage: "flag.checkered")
            }
            .accessibilityIdentifier("firstExportGuideSettingsButton")

            LabeledContent("Guide status", value: guide.statusDescription)
                .accessibilityIdentifier("firstExportGuideSettingsStatus")

            if let persistenceError = guide.persistenceError {
                Text(persistenceError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var buttonTitle: String {
        switch guide.progress.status {
        case .paused, .skipped, .active: "Show first-export guide"
        case .completed, .notStarted: "Start first-export guide"
        }
    }
}
