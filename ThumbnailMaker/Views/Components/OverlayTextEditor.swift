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
                    .frame(minHeight: 96, idealHeight: 120, maxHeight: 240)
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

                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .animation(.easeOut(duration: 0.2), value: isOverLimit)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .imageScale(.small)
                    Text("Aim for around \(characterLimit) characters for legible thumbnails.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)

                Spacer()

                Text("\(text.count)/\(characterLimit)")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(isOverLimit ? Color.red : Color.secondary)
                    .accessibilityLabel("Overlay text character count \(text.count) of \(characterLimit)")
            }
            .padding(.horizontal, 4)
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

