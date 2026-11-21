//
//  ThumbnailSeriesRowsHistory.swift
//  ThumbnailMaker
//
//  FEATURE-15: undo/redo for series table edits, with the same record / undo /
//  redo semantics as ThumbnailDocumentHistory. Kept separate from the editor's
//  document history so series edits never cross the per-variant stacks.
//

import Foundation

struct ThumbnailSeriesRowsHistory: Equatable {
    static let defaultLimit = 30

    private(set) var undoStack: [[ThumbnailSeriesRow]] = []
    private(set) var redoStack: [[ThumbnailSeriesRow]] = []
    let limit: Int

    init(limit: Int = ThumbnailSeriesRowsHistory.defaultLimit) {
        self.limit = max(1, limit)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Records the state BEFORE an edit.
    mutating func record(_ rows: [ThumbnailSeriesRow]) {
        if undoStack.last == rows { return }
        undoStack.append(rows)
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
        redoStack.removeAll()
    }

    mutating func undo(current: [ThumbnailSeriesRow]) -> [ThumbnailSeriesRow]? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    mutating func redo(current: [ThumbnailSeriesRow]) -> [ThumbnailSeriesRow]? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }

    mutating func reset() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
