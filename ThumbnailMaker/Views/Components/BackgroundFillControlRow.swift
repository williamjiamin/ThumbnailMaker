//
//  BackgroundFillControlRow.swift
//  ThumbnailMaker
//
//  SHELL: the editor's background controls gain a Solid / Gradient switch.
//  Switching back to Solid keeps the gradient recipe (kind = .solid), so
//  turning Gradient on again restores it; every change is an ordinary
//  document edit, so Undo covers it.
//

import SwiftUI

struct BackgroundFillControlRow: View {
    @Binding var backgroundColor: Color
    @Binding var fill: ThumbnailBackgroundFill?

    private var isGradient: Bool { fill?.drawsGradient == true }

    private var kindBinding: Binding<ThumbnailBackgroundFill.Kind> {
        Binding(
            get: { isGradient ? .linearGradient : .solid },
            set: { newKind in
                switch newKind {
                case .solid:
                    guard var current = fill else { return }
                    current.kind = .solid
                    fill = current
                case .linearGradient:
                    if var current = fill, current.stops.count >= ThumbnailBackgroundFill.stopCountRange.lowerBound {
                        current.kind = .linearGradient
                        fill = current.normalized()
                    } else {
                        fill = Self.defaultGradient(from: backgroundColor)
                    }
                }
            }
        )
    }

    static func defaultGradient(from color: Color) -> ThumbnailBackgroundFill {
        let start = ThumbnailDocumentColor(color: color)
        let placeholder = ThumbnailDocumentColor(color: Color(uiColor: .secondarySystemBackground))
        guard start != placeholder else {
            return ThumbnailBackgroundFill.presets[1].fill
        }
        return .linearGradient(
            [start, ThumbnailDocumentColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1)],
            angleDegrees: 90
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            title
            kindPicker

            if let current = fill, current.drawsGradient {
                presetRow
                stopRow(current)
                angleRow(current)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("backgroundFillControls")
    }

    private var title: some View {
        Text("Background")
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kindPicker: some View {
        Picker("Background fill", selection: kindBinding) {
            Text("Solid").tag(ThumbnailBackgroundFill.Kind.solid)
            Text("Gradient").tag(ThumbnailBackgroundFill.Kind.linearGradient)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("backgroundFillKindPicker")
    }

    private var presetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ThumbnailBackgroundFill.presets) { preset in
                    Button {
                        fill = preset.fill
                    } label: {
                        Circle()
                            .fill(LinearGradient(
                                gradient: preset.fill.gradient,
                                startPoint: preset.fill.startPoint,
                                endPoint: preset.fill.endPoint
                            ))
                            .frame(width: 32, height: 32)
                            .overlay(Circle().stroke(Color.primary.opacity(fill == preset.fill ? 0.8 : 0.15), lineWidth: 2))
                            .minimumHitTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(preset.name) gradient")
                    .accessibilityAddTraits(fill == preset.fill ? .isSelected : [])
                    .accessibilityIdentifier("backgroundGradientPreset-\(preset.id)")
                }
            }
        }
    }

    private func stopRow(_ current: ThumbnailBackgroundFill) -> some View {
        HStack(spacing: 12) {
            ForEach(Array(current.stops.indices), id: \.self) { index in
                ColorPicker("", selection: stopColorBinding(index))
                    .labelsHidden()
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Gradient color \(index + 1)")
            }
            Spacer(minLength: 0)
            if current.stops.count < ThumbnailBackgroundFill.stopCountRange.upperBound {
                Button {
                    addStop()
                } label: {
                    Image(systemName: "plus.circle")
                        .minimumHitTarget()
                }
                .accessibilityLabel("Add gradient color")
                .accessibilityIdentifier("addGradientStopButton")
            }
            if current.stops.count > ThumbnailBackgroundFill.stopCountRange.lowerBound {
                Button {
                    removeStop()
                } label: {
                    Image(systemName: "minus.circle")
                        .minimumHitTarget()
                }
                .accessibilityLabel("Remove gradient color")
                .accessibilityIdentifier("removeGradientStopButton")
            }
        }
    }

    private func angleRow(_ current: ThumbnailBackgroundFill) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Angle \(Int(current.angleDegrees.rounded()))°")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Slider(value: angleBinding, in: 0...359, step: 1) {
                Text("Gradient angle")
            }
            .accessibilityValue("\(Int(current.angleDegrees.rounded())) degrees")
            .accessibilityIdentifier("gradientAngleSlider")
        }
    }

    private var angleBinding: Binding<Double> {
        Binding(
            get: { fill?.angleDegrees ?? 0 },
            set: { newValue in
                guard var current = fill else { return }
                current.angleDegrees = ThumbnailBackgroundFill.normalizedAngle(newValue)
                fill = current
            }
        )
    }

    private func stopColorBinding(_ index: Int) -> Binding<Color> {
        Binding(
            get: {
                guard let fill, fill.stops.indices.contains(index) else { return .clear }
                return fill.stops[index].color.color
            },
            set: { newColor in
                guard var current = fill, current.stops.indices.contains(index) else { return }
                current.stops[index].color = ThumbnailDocumentColor(color: newColor)
                fill = current
            }
        )
    }

    private func addStop() {
        guard var current = fill,
              current.stops.count < ThumbnailBackgroundFill.stopCountRange.upperBound,
              let last = current.stops.last else { return }
        // Re-space evenly with the new colour at the end.
        var colors = current.stops.map(\.color)
        colors.append(last.color)
        let spaced = ThumbnailBackgroundFill.linearGradient(colors, angleDegrees: current.angleDegrees)
        current.stops = spaced.stops
        fill = current
    }

    private func removeStop() {
        guard var current = fill,
              current.stops.count > ThumbnailBackgroundFill.stopCountRange.lowerBound else { return }
        var colors = current.stops.map(\.color)
        colors.removeLast()
        current.stops = ThumbnailBackgroundFill.linearGradient(colors, angleDegrees: current.angleDegrees).stops
        fill = current
    }
}
