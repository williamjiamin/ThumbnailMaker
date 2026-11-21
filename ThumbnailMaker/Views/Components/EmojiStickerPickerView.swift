//
//  EmojiStickerPickerView.swift
//  ThumbnailMaker
//
//  DONOR (Simple Meme Maker App/EditorBars.swift StickerPicker): 32 reaction
//  emoji plus "type any emoji". The pick is handed back as text; the view
//  model renders it into a sticker image layer (ThumbnailEmojiSticker).
//

import SwiftUI

struct EmojiStickerPickerView: View {
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 8)], spacing: 8) {
                    ForEach(ThumbnailEmojiSticker.favourites, id: \.self) { emoji in
                        Button {
                            pick(emoji)
                        } label: {
                            Text(emoji)
                                .font(.system(size: 36))
                                .frame(width: 56, height: 56)
                                .background(
                                    Color(uiColor: .secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(emoji))
                        .accessibilityHint("Adds this emoji as a sticker layer")
                    }
                }
                .padding(16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Or type any emoji")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("Emoji", text: $typed)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.done)
                            .onSubmit { pick(typed) }
                            .accessibilityIdentifier("emojiStickerField")
                        Button("Add") { pick(typed) }
                            .buttonStyle(.borderedProminent)
                            .disabled(ThumbnailEmojiSticker.sanitized(typed) == nil)
                            .accessibilityIdentifier("emojiStickerAddButton")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .navigationTitle("Emoji Stickers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func pick(_ text: String) {
        guard let sticker = ThumbnailEmojiSticker.sanitized(text) else { return }
        onPick(sticker)
        dismiss()
    }
}

/// DONOR: presents the emoji picker and the drawing sheet for either editor,
/// kept out of the editors' already-long body modifier chains.
struct DonorLayerSheetsModifier<DrawingBackground: View>: ViewModifier {
    @Binding var isEmojiPickerPresented: Bool
    @Binding var isDrawingPresented: Bool
    let aspectRatio: AspectRatio
    let addEmoji: (String) -> Void
    let addDrawing: (ThumbnailDrawingResult) -> Void
    @ViewBuilder let drawingBackground: (CGSize) -> DrawingBackground

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isEmojiPickerPresented) {
                EmojiStickerPickerView(onPick: addEmoji)
            }
            .fullScreenCover(isPresented: $isDrawingPresented) {
                ThumbnailDrawingSheet(
                    aspectRatio: aspectRatio,
                    onPlace: addDrawing,
                    background: drawingBackground
                )
            }
    }
}

/// The two DONOR add actions as icon buttons, matching CreatorActionIcon.
struct DonorAddLayerIconButtons: View {
    let showEmojiPicker: () -> Void
    let showDrawing: () -> Void

    var body: some View {
        Button(action: showEmojiPicker) {
            CreatorActionIcon(
                systemName: "face.smiling.inverse",
                colors: [.yellow, .orange.opacity(0.82)]
            )
        }
        .accessibilityIdentifier("addEmojiStickerButton")
        .accessibilityLabel("Add Emoji Sticker")

        Button(action: showDrawing) {
            CreatorActionIcon(
                systemName: "pencil.tip.crop.circle",
                colors: [.red, .pink.opacity(0.82)]
            )
        }
        .accessibilityIdentifier("addDrawingButton")
        .accessibilityLabel("Draw")
    }
}
