//
//  CreatorActionIcon.swift
//  ThumbnailMaker
//

import SwiftUI

struct CreatorActionIcon: View {
    let systemName: String
    let colors: [Color]
    var isLoading = false
    @ScaledMetric(relativeTo: .body) private var width: CGFloat = 58
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 46
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 20

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: colors,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            if isLoading {
                ProgressView()
                    .tint(.white)
            } else {
                Image(systemName: systemName)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: max(44, width), height: max(44, height))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }
}
