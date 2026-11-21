//
//  ThumbnailDocumentHistory.swift
//  ThumbnailMaker
//

import Foundation

struct ThumbnailDocumentHistory: Equatable {
    private(set) var undoStack: [ThumbnailDocument] = []
    private(set) var redoStack: [ThumbnailDocument] = []
    var limit = 20

    var canUndo: Bool {
        !undoStack.isEmpty
    }

    var canRedo: Bool {
        !redoStack.isEmpty
    }

    mutating func record(_ previous: ThumbnailDocument) {
        let snapshot = Self.snapshot(previous)
        // APP-09: identical photo buffers are not byte-compared.
        if let last = undoStack.last, ThumbnailDocumentPayloads.isEquivalent(last, snapshot) { return }

        undoStack.append(snapshot)
        trimUndoStack()
        redoStack.removeAll()
    }

    mutating func undo(current: ThumbnailDocument) -> ThumbnailDocument? {
        guard let previous = undoStack.popLast() else { return nil }

        redoStack.append(Self.snapshot(current))
        trimRedoStack()
        return previous
    }

    mutating func redo(current: ThumbnailDocument) -> ThumbnailDocument? {
        guard let next = redoStack.popLast() else { return nil }

        undoStack.append(Self.snapshot(current))
        trimUndoStack()
        return next
    }

    static func snapshot(_ document: ThumbnailDocument) -> ThumbnailDocument {
        var snapshot = document
        snapshot.updatedAt = Date(timeIntervalSince1970: 0)
        return snapshot
    }

    // MARK: APP-09 payload budget

    /// Every snapshot held by the stacks.
    var allSnapshots: [ThumbnailDocument] {
        undoStack + redoStack
    }

    /// Drops the oldest undo step while more than `minimum` remain.
    @discardableResult
    mutating func dropOldestUndo(keeping minimum: Int = 0) -> Bool {
        guard undoStack.count > max(0, minimum) else { return false }
        undoStack.removeFirst()
        return true
    }

    /// Drops the redo step furthest from the current state while more than
    /// `minimum` remain.
    @discardableResult
    mutating func dropFurthestRedo(keeping minimum: Int = 0) -> Bool {
        guard redoStack.count > max(0, minimum) else { return false }
        redoStack.removeFirst()
        return true
    }

    private mutating func trimUndoStack() {
        while undoStack.count > limit {
            undoStack.removeFirst()
        }
    }

    private mutating func trimRedoStack() {
        while redoStack.count > limit {
            redoStack.removeFirst()
        }
    }
}
