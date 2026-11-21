//
//  ThumbnailVariantHistoryTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-02: undo stacks are independent per variant slot.
//

import Foundation
import Testing
@testable import ThumbnailMaker

@MainActor
struct ThumbnailVariantHistoryTests {
    private func document(_ text: String) -> ThumbnailDocument {
        var configuration = SimpleMakerConfigurationModel()
        configuration.overlayText = text
        return ThumbnailDocument(configuration: configuration)
    }

    @Test func undoStacksAreIndependentPerSlot() {
        var book = ThumbnailVariantHistoryBook(defaultBaseline: document("base"))
        var historyA = book.history(for: .a)
        historyA.record(document("a1"))
        historyA.record(document("a2"))
        book.setHistory(historyA, for: .a)
        var historyB = book.history(for: .b)
        historyB.record(document("b1"))
        book.setHistory(historyB, for: .b)

        #expect(book.history(for: .a).undoStack.count == 2)
        #expect(book.history(for: .b).undoStack.count == 1)

        var undoB = book.history(for: .b)
        let undone = undoB.undo(current: document("b2"))
        book.setHistory(undoB, for: .b)
        #expect(undone?.text.value == "b1")
        #expect(book.history(for: .a).undoStack.count == 2)
        #expect(book.history(for: .b).canRedo)
        #expect(book.history(for: .a).canRedo == false)
    }

    @Test func switchingAwayAndBackRestoresTheSameStack() {
        var workspace = ThumbnailVariantWorkspace(seedDocument: document("A0"), editorMode: .simple)
        workspace.activeHistory.record(document("A0"))
        workspace.activeBaseline = ThumbnailDocumentHistory.snapshot(document("A1"))
        let result1 = workspace.duplicateActive(committing: document("A1"))
        #expect(result1 != nil)
        #expect(workspace.activeSlot == .b)
        #expect(workspace.activeHistory.canUndo == false)
        workspace.activeHistory.record(document("B0"))

        let result2 = workspace.select(.a, committing: document("B1"))
        #expect(result2?.text.value == "A1")
        #expect(workspace.activeHistory.undoStack.count == 1)
        #expect(workspace.activeHistory.undoStack.first?.text.value == "A0")
        #expect(workspace.activeBaseline.text.value == "A1")

        let result3 = workspace.select(.b, committing: document("A1"))
        #expect(result3?.text.value == "B1")
        #expect(workspace.activeHistory.undoStack.first?.text.value == "B0")
    }

    @Test func discardSlotClearsOnlyThatSlot() {
        var book = ThumbnailVariantHistoryBook(defaultBaseline: document("base"))
        book.resetSlot(.a, to: document("a"))
        book.resetSlot(.b, to: document("b"))
        var history = book.history(for: .b)
        history.record(document("b-old"))
        book.setHistory(history, for: .b)
        history = book.history(for: .a)
        history.record(document("a-old"))
        book.setHistory(history, for: .a)

        book.discardSlot(.b)
        #expect(book.history(for: .b).canUndo == false)
        #expect(book.hasBaseline(for: .b) == false)
        #expect(book.history(for: .a).canUndo)
        #expect(book.baseline(for: .a).text.value == "a")
    }

    @Test func defaultBaselineIsUsedForAnUntouchedSlot() {
        let book = ThumbnailVariantHistoryBook(defaultBaseline: document("base"))
        #expect(book.baseline(for: .c).text.value == "base")
        #expect(book.baseline(for: .c).updatedAt == Date(timeIntervalSince1970: 0))
        #expect(book.history(for: .c).canUndo == false)
    }

    @Test func removingTheActiveVariantLoadsTheLowestRemaining() {
        var workspace = ThumbnailVariantWorkspace(seedDocument: document("A"), editorMode: .simple)
        _ = workspace.duplicateActive(committing: document("A"))
        _ = workspace.duplicateActive(committing: document("B"))
        #expect(workspace.activeSlot == .c)
        let result = workspace.remove(.c, committing: document("C"))
        #expect(result.removed)
        #expect(result.documentToLoad?.text.value == "A")
        #expect(workspace.activeSlot == .a)
        #expect(workspace.variantSet.slots == [.a, .b])
        #expect(workspace.variantSet.document(for: .b)?.text.value == "B")
    }
}
