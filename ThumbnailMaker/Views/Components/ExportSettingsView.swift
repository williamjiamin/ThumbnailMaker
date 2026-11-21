//
//  ExportSettingsView.swift
//  ThumbnailMaker
//

import SwiftUI
import UIKit

struct ExportSettingsSummaryRow: View {
    @Binding var selectedRatio: AspectRatio
    @Binding var options: ThumbnailExportOptions
    @State private var showingExportSettings = false

    var body: some View {
        Button {
            showingExportSettings = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3)
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Export")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .accessibilityIdentifier("exportSettingsTitle")
                    Text(options.preset.name)
                        .font(.caption)
                        .foregroundColor(.accessibleSecondaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(options.outputSize.displayText) · \(options.format.displayName)")
                        .font(.caption)
                        .foregroundColor(.accessibleSecondaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.accessibleSecondaryText)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("exportSettingsButton")
        .accessibilityLabel("Export")
        .accessibilityValue("\(options.preset.name), \(options.outputSize.displayText), \(options.format.displayName)")
        .sheet(isPresented: $showingExportSettings) {
            ExportSettingsView(
                selectedRatio: $selectedRatio,
                options: $options
            )
        }
    }
}

struct ExportSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedRatio: AspectRatio
    @Binding var options: ThumbnailExportOptions

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    exportSection(title: "Preset") {
                        ForEach(ThumbnailExportPreset.all) { preset in
                            Button {
                                options.applyPreset(preset)
                                selectedRatio = preset.aspectRatio
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(preset.name)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(preset.summary)
                                            .font(.caption)
                                            .foregroundColor(.accessibleSecondaryText)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .layoutPriority(1)

                                    Spacer(minLength: 12)

                                    if ThumbnailAccessibilityText.isExportPresetSelected(preset, options: options) {
                                        Image(systemName: "checkmark")
                                            .font(.body.weight(.semibold))
                                            .foregroundColor(.blue)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            // APP-07: the checkmark is decorative, so the row itself
                            // carries the selection like the Format rows below.
                            .accessibilityLabel(preset.name)
                            .accessibilityValue(ThumbnailAccessibilityText.exportPresetValue(preset: preset, options: options))
                            .accessibilityAddTraits(
                                ThumbnailAccessibilityText.isExportPresetSelected(preset, options: options) ? .isSelected : []
                            )
                            .accessibilityIdentifier("exportPreset-\(preset.id)")
                        }
                    }

                    if let safeZone = options.activeSafeZone {
                        exportSection(title: "Safe Zone") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Image(systemName: "shield.lefthalf.filled")
                                        .font(.body)
                                        .foregroundStyle(.blue)
                                        .accessibilityHidden(true)

                                    Text(safeZone.name)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Text(safeZone.guidance)
                                    .font(.footnote)
                                    .foregroundColor(.accessibleSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }

                    exportSection(title: "Format") {
                        ForEach(ThumbnailExportFormat.allCases) { format in
                            Button {
                                options.format = format
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(format.displayName)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .fixedSize(horizontal: false, vertical: true)

                                        if !format.canEncodeOnCurrentPlatform {
                                            Text("Unavailable on this platform")
                                                .font(.caption)
                                                .foregroundColor(.accessibleSecondaryText)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    .layoutPriority(1)

                                    Spacer(minLength: 12)

                                    if options.format == format {
                                        Image(systemName: "checkmark")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.blue)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!format.canEncodeOnCurrentPlatform)
                            .accessibilityLabel(format.displayName)
                            .accessibilityValue(accessibilityValue(for: format))
                            .accessibilityAddTraits(options.format == format ? .isSelected : [])
                        }

                        if options.format.supportsCompressionQuality {
                            Stepper(
                                value: $options.compressionQuality,
                                in: 0.4...1.0,
                                step: 0.05
                            ) {
                                HStack {
                                    Text("Quality")
                                    Spacer()
                                    Text("\(Int(options.compressionQuality * 100))%")
                                        .foregroundColor(.accessibleSecondaryText)
                                }
                                .font(.body)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .accessibilityElement(children: .ignore)
                            .accessibilityIdentifier("exportQualityStepper")
                            .accessibilityLabel("Quality")
                            .accessibilityValue("\(Int(options.compressionQuality * 100)) percent")
                            .accessibilityHint("Swipe up or down to adjust compression quality")
                            .accessibilityAdjustableAction { direction in
                                adjustCompressionQuality(direction)
                            }
                        }
                    }

                    exportSection(title: "Custom Size") {
                        Toggle("Custom Size", isOn: $options.usesCustomSize)
                            .font(.body)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                        if options.usesCustomSize {
                            Stepper(
                                "Width \(options.customSize.width) px",
                                value: $options.customSize.width,
                                in: 320...4096,
                                step: 10
                            )
                            .font(.body)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                            Stepper(
                                "Height \(options.customSize.height) px",
                                value: $options.customSize.height,
                                in: 320...4096,
                                step: 10
                            )
                            .font(.body)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Export Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Done")
                }
            }
        }
    }

    @ViewBuilder
    private func exportSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
    }

    private func accessibilityValue(for format: ThumbnailExportFormat) -> String {
        if !format.canEncodeOnCurrentPlatform {
            return "Unavailable"
        }
        return options.format == format ? "Selected" : "Available"
    }

    private func adjustCompressionQuality(_ direction: AccessibilityAdjustmentDirection) {
        let delta: Double
        switch direction {
        case .increment:
            delta = 0.05
        case .decrement:
            delta = -0.05
        @unknown default:
            return
        }

        let adjusted = options.compressionQuality + delta
        options.compressionQuality = min(1.0, max(0.4, adjusted))
    }
}

#Preview {
    ExportSettingsView(
        selectedRatio: .constant(.ratio16_9),
        options: .constant(ThumbnailExportOptions())
    )
}
