//
//  OverlayTextEditor.swift
//  ThumbnailMaker
//
//  Created by AI on 2024/11/30.
//

import SwiftUI

struct OverlayTextEditor: View {
    @Binding var text: String
    let placeholder: String
    let characterLimit: Int
    var focus: FocusState<Bool>.Binding
    /// APP-08: a shorter editor on phones so the layer strip stays on screen.
    var isCompact = false

    private var isOverLimit: Bool {
        text.count > characterLimit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .focused(focus)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .frame(
                        minHeight: isCompact ? 72 : 96,
                        idealHeight: isCompact ? 88 : 120,
                        maxHeight: isCompact ? 160 : 240
                    )
                    .scrollContentBackground(.hidden)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 1)
                    )
                    .accessibilityLabel("Overlay text")
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()

                            Button("Done") {
                                focus.wrappedValue = false
                            }
                            .accessibilityIdentifier("overlayTextKeyboardDoneButton")
                            .accessibilityLabel("Done editing overlay text")
                        }
                    }

                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(Color.accessibleSecondaryText)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .animation(.easeOut(duration: 0.2), value: isOverLimit)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .imageScale(.small)
                    Text(isCompact
                         ? "Aim for about \(characterLimit) characters."
                         : "Aim for around \(characterLimit) characters for legible thumbnails.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.footnote)
                .foregroundStyle(Color.accessibleSecondaryText)
                .accessibilityElement(children: .combine)

                Text("\(text.count)/\(characterLimit)")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(isOverLimit ? Color.red : Color.accessibleSecondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Overlay text guidance")
            .accessibilityValue("Aim for around \(characterLimit) characters. \(text.count) of \(characterLimit) characters used.")
        }
        .accessibilityHint("Enter the text that appears on your thumbnail.")
    }

    private var borderColor: Color {
        isOverLimit ? .red : Color.gray.opacity(0.3)
    }
}

struct OverlayTextEditor_Previews: PreviewProvider {
    struct PreviewHarness: View {
        @State private var text = "Your next viral idea"
        @FocusState private var isFocused: Bool

        var body: some View {
            OverlayTextEditor(
                text: $text,
                placeholder: "Add headline copy",
                characterLimit: 120,
                focus: $isFocused
            )
            .padding()
        }
    }

    static var previews: some View {
        PreviewHarness()
            .previewLayout(.sizeThatFits)
    }
}
