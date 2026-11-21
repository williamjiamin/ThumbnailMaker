//
//  UndoRedoToolbarButtons.swift
//  ThumbnailMaker
//

import SwiftUI

struct UndoRedoToolbarButtons: View {
    let canUndo: Bool
    let canRedo: Bool
    let undo: () -> Void
    let redo: () -> Void

    var body: some View {
        Button(action: {
            guard canUndo else { return }
            undo()
        }) {
            Image(systemName: "arrow.uturn.backward")
                .foregroundStyle(canUndo ? Color.blue : Color.accessibleSecondaryText)
        }
        .disabled(!canUndo)
        .keyboardShortcut("z", modifiers: .command)
        .accessibilityLabel("Undo")
        .accessibilityValue(canUndo ? "Available" : "Unavailable")
        .help("Undo")

        Button(action: {
            guard canRedo else { return }
            redo()
        }) {
            Image(systemName: "arrow.uturn.forward")
                .foregroundStyle(canRedo ? Color.blue : Color.accessibleSecondaryText)
        }
        .disabled(!canRedo)
        .keyboardShortcut("z", modifiers: [.command, .shift])
        .accessibilityLabel("Redo")
        .accessibilityValue(canRedo ? "Available" : "Unavailable")
        .help("Redo")
    }
}
