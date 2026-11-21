//
//  OverlayTransformControlView.swift
//  ThumbnailMaker
//

import SwiftUI

struct OverlayTransformStatusView: View {
    let title: String
    @Binding var transform: ThumbnailOverlayTransform
    var size: CGFloat? = nil
    var resetTransform: ThumbnailOverlayTransform = .centered

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cursorarrow.motionlines")
                .font(.body.weight(.semibold))
                .foregroundStyle(.blue)
                .frame(width: 38, height: 38)
                .background(Color(uiColor: .tertiarySystemBackground))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text("\(transform.positionDescription) · \(Int(round(transform.rotationDegrees)))°")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(title)
            .accessibilityValue(transform.canvasStateDescription(size: size))

            Button {
                transform.reset(to: resetTransform)
            } label: {
                ZStack {
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemBackground))
                        .frame(width: 38, height: 38)
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )

                    Image(systemName: "scope")
                        .font(.callout.weight(.semibold))
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            .accessibilityLabel("Reset \(title.lowercased()) placement")
            .accessibilityHint("Returns this overlay to its default canvas position, rotation, and flip state.")
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    OverlayTransformStatusView(
        title: "Text Canvas",
        transform: .constant(ThumbnailOverlayTransform(x: 0.45, y: 0.55, rotationDegrees: 15))
    )
    .padding()
}
