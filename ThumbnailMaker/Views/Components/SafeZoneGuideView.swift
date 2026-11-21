//
//  SafeZoneGuideView.swift
//  ThumbnailMaker
//

import SwiftUI

struct SafeZoneOverlayView: View {
    let safeZone: ThumbnailSafeZone
    let width: CGFloat
    let height: CGFloat

    private var safeRect: CGRect {
        let rect = safeZone.contentRect(
            in: CGSize(width: max(0, width), height: max(0, height))
        )
        let inset = max(0, min(1, rect.width / 2, rect.height / 2))
        return rect.insetBy(dx: inset, dy: inset)
    }

    var body: some View {
        ZStack {
            outsideSafeZoneFill

            RoundedRectangle(cornerRadius: max(4, min(width, height) * 0.025), style: .continuous)
                .stroke(
                    Color.white.opacity(0.95),
                    style: StrokeStyle(
                        lineWidth: max(1, min(width, height) * 0.006),
                        dash: [max(5, min(width, height) * 0.035), max(4, min(width, height) * 0.025)]
                    )
                )
                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                .frame(width: max(0, safeRect.width), height: max(0, safeRect.height))
                .position(x: safeRect.midX, y: safeRect.midY)
        }
        .frame(width: max(0, width), height: max(0, height))
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Safe Zone Guide")
        .accessibilityIdentifier("safeZoneOverlay")
    }

    private var outsideSafeZoneFill: some View {
        Path { path in
            path.addRect(CGRect(x: 0, y: 0, width: max(0, width), height: max(0, height)))
            path.addRect(safeRect)
        }
        .fill(Color.black.opacity(0.18), style: FillStyle(eoFill: true))
    }
}

struct SafeZoneGuideToggle: View {
    @Binding var isOn: Bool
    let safeZone: ThumbnailSafeZone

    var body: some View {
        Toggle(isOn: $isOn) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Safe Zone Guide")
                        .font(.subheadline.weight(.semibold))
                    Text(safeZone.name)
                        .font(.caption)
                        .foregroundStyle(Color.accessibleSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .accessibilityIdentifier("safeZoneGuideToggle")
    }
}

#Preview {
    SafeZoneOverlayView(
        safeZone: ThumbnailExportPreset.shortFormCover.safeZone!,
        width: 180,
        height: 320
    )
}
