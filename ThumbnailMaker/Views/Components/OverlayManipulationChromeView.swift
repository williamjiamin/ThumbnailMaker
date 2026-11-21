//
//  OverlayManipulationChromeView.swift
//  ThumbnailMaker
//

import SwiftUI

struct OverlayManipulationChromeView: View {
    let accessibilityPrefix: String
    let cornerRadius: CGFloat
    let rotateGesture: AnyGesture<Void>
    let resizeGesture: AnyGesture<Void>
    let flipAction: () -> Void
    let rotateClockwiseAction: () -> Void
    let rotateCounterClockwiseAction: () -> Void
    let increaseSizeAction: () -> Void
    let decreaseSizeAction: () -> Void

    var body: some View {
        ZStack {
            Color.clear
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.blue.opacity(0.72), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            HStack {
                handle(systemName: "arrow.left.and.right")
                    .highPriorityGesture(TapGesture().onEnded(flipAction))
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Flip overlay")
                    .accessibilityHint("Flips the selected overlay horizontally.")
                    .accessibilityIdentifier("\(accessibilityPrefix)FlipHandle")
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            VStack {
                handle(systemName: "arrow.clockwise")
                    .gesture(rotateGesture)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Rotate overlay")
                    .accessibilityHint("Swipe up or down to rotate the selected overlay.")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment:
                            rotateClockwiseAction()
                        case .decrement:
                            rotateCounterClockwiseAction()
                        @unknown default:
                            break
                        }
                    }
                    .accessibilityIdentifier("\(accessibilityPrefix)RotateHandle")
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            VStack {
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                handle(systemName: "arrow.up.left.and.arrow.down.right")
                    .gesture(resizeGesture)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Resize overlay")
                    .accessibilityHint("Swipe up or down to resize the selected overlay.")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment:
                            increaseSizeAction()
                        case .decrement:
                            decreaseSizeAction()
                        @unknown default:
                            break
                        }
                    }
                    .accessibilityIdentifier("\(accessibilityPrefix)ResizeHandle")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }

    private func handle(systemName: String) -> some View {
        ZStack {
            Circle()
                .fill(Color.blue)
                .frame(width: 34, height: 34)
                .shadow(color: .black.opacity(0.24), radius: 4, x: 0, y: 2)

            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: Self.handleSize, height: Self.handleSize)
        .contentShape(Rectangle())
    }

    static let minimumInteractiveWidth: CGFloat = handleSize * 3
    static let minimumInteractiveHeight: CGFloat = handleSize * 2 + 8

    private static let handleSize: CGFloat = 44
}

#Preview {
    OverlayManipulationChromeView(
        accessibilityPrefix: "text",
        cornerRadius: 8,
        rotateGesture: AnyGesture(DragGesture().map { _ in () }),
        resizeGesture: AnyGesture(DragGesture().map { _ in () }),
        flipAction: {},
        rotateClockwiseAction: {},
        rotateCounterClockwiseAction: {},
        increaseSizeAction: {},
        decreaseSizeAction: {}
    )
    .frame(width: 220, height: 96)
    .padding(60)
}
