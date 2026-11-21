//
//  ThumbnailHistoryPayloadBudgetTests.swift
//  ThumbnailMakerTests
//
//  APP-09: history memory is bounded by distinct photo bytes, shared buffers
//  count once, and inactive variants give up history before the active one.
//

import Foundation
import Testing
@testable import ThumbnailMaker

@MainActor
struct ThumbnailHistoryPayloadBudgetTests {
    private typealias Support = ThumbnailPerformanceTestSupport

    @Test func equivalenceMatchesEqualityWithAndWithoutSharedBuffers() {
        let photo = Support.payload(bytes: 4_000, fill: 1)
        let a = Support.document(text: "Hello", imageData: photo)
        let sameBuffer = Support.document(text: "Hello", imageData: photo)
        let copiedBytes = Support.document(text: "Hello", imageData: Data(Array(photo)))
        let otherText = Support.document(text: "Bye", imageData: photo)
        let otherPhoto = Support.document(text: "Hello", imageData: Support.payload(bytes: 4_000, fill: 2))

        #expect(ThumbnailDocumentPayloads.isEquivalent(a, sameBuffer))
        #expect(ThumbnailDocumentPayloads.isEquivalent(a, copiedBytes))
        #expect(!ThumbnailDocumentPayloads.isEquivalent(a, otherText))
        #expect(!ThumbnailDocumentPayloads.isEquivalent(a, otherPhoto))
        #expect(!ThumbnailDocumentPayloads.isEquivalent(a, Support.document(text: "Hello", imageData: nil)))
    }

    @Test func sharedBuffersCountOnce() {
        let photo = Support.payload(bytes: 5_000, fill: 3)
        let documents = (0..<10).map { Support.document(text: "v\($0)", imageData: photo) }
        #expect(ThumbnailDocumentPayloads.uniqueByteCount(of: documents) == 5_000)

        let distinct = (0..<3).map { Support.document(text: "d\($0)", imageData: Support.payload(bytes: 1_000, fill: UInt8($0))) }
        #expect(ThumbnailDocumentPayloads.uniqueByteCount(of: distinct) == 3_000)
    }

    @Test func recordStillSkipsIdenticalSnapshots() {
        let photo = Support.payload(bytes: 2_000, fill: 4)
        var history = ThumbnailDocumentHistory()
        history.record(Support.document(text: "A", imageData: photo))
        history.record(Support.document(text: "A", imageData: photo))
        history.record(Support.document(text: "A", imageData: Data(Array(photo))))
        #expect(history.undoStack.count == 1)
        history.record(Support.document(text: "B", imageData: photo))
        #expect(history.undoStack.count == 2)
        #expect(history.limit == 20)
    }

    @Test func dropHelpersRespectMinimums() {
        var history = ThumbnailDocumentHistory()
        for index in 0..<3 {
            history.record(Support.document(text: "\(index)", imageData: nil))
        }
        let firstDrop = history.dropOldestUndo(keeping: 1)
        #expect(firstDrop)
        #expect(history.undoStack.first?.text.value == "1")
        let secondDrop = history.dropOldestUndo(keeping: 1)
        #expect(secondDrop)
        let thirdDrop = history.dropOldestUndo(keeping: 1)
        #expect(!thirdDrop)
        #expect(history.undoStack.count == 1)
        let redoDrop = history.dropFurthestRedo()
        #expect(!redoDrop)
    }

    private func history(photos count: Int, fill: UInt8) -> ThumbnailDocumentHistory {
        var history = ThumbnailDocumentHistory()
        for index in 0..<count {
            history.record(Support.document(text: "\(fill)-\(index)", imageData: Support.payload(bytes: 1_000, fill: fill &+ UInt8(index))))
        }
        return history
    }

    @Test func budgetTrimsInactiveSlotsBeforeTheActiveOne() {
        let baseline = Support.document(text: "base", imageData: nil)
        var book = ThumbnailVariantHistoryBook(defaultBaseline: baseline)
        book.setHistory(history(photos: 5, fill: 10), for: .a)
        book.setHistory(history(photos: 5, fill: 100), for: .b)
        #expect(book.totalPayloadBytes() == 10_000)

        let remaining = book.enforcePayloadBudget(6_500, activeSlot: .a)
        #expect(remaining <= 6_500)
        #expect(book.history(for: .a).undoStack.count == 5, "Active slot untouched while inactive history remains.")
        #expect(book.history(for: .b).undoStack.count == 1)
        // Oldest steps go first.
        #expect(book.history(for: .b).undoStack.first?.text.value == "100-4")

        let tight = book.enforcePayloadBudget(500, activeSlot: .a)
        #expect(book.history(for: .b).undoStack.isEmpty)
        #expect(book.history(for: .a).undoStack.count == 1, "The active slot keeps one undo step.")
        #expect(book.history(for: .a).undoStack.first?.text.value == "10-4")
        #expect(tight == 1_000)
    }

    @Test func budgetUnderLimitChangesNothing() {
        var book = ThumbnailVariantHistoryBook(defaultBaseline: Support.document(text: "base", imageData: nil))
        let original = history(photos: 4, fill: 1)
        book.setHistory(original, for: .a)
        #expect(book.enforcePayloadBudget(1_000_000, activeSlot: .a) == 4_000)
        #expect(book.history(for: .a) == original)
    }

    @Test func totalPayloadDedupsAcrossSlotsAndBaselines() {
        let photo = Support.payload(bytes: 3_000, fill: 7)
        var book = ThumbnailVariantHistoryBook(defaultBaseline: Support.document(text: "base", imageData: photo))
        var shared = ThumbnailDocumentHistory()
        shared.record(Support.document(text: "1", imageData: photo))
        shared.record(Support.document(text: "2", imageData: photo))
        book.setHistory(shared, for: .a)
        book.setHistory(shared, for: .b)
        book.setBaseline(Support.document(text: "b", imageData: photo), for: .b)
        #expect(book.totalPayloadBytes() == 3_000)
    }

    @Test func workspaceEnforcesBudgetWhenHistoryChanges() {
        var workspace = ThumbnailVariantWorkspace(
            seedDocument: Support.document(text: "seed", imageData: nil),
            editorMode: .simple
        )
        #expect(workspace.historyPayloadByteBudget == ThumbnailPerformanceBudget.historyPayloadByteBudget)
        workspace.historyPayloadByteBudget = 2_500

        let recorder = ThumbnailPerformanceRecorder()
        ThumbnailPerformanceRecorder.$scoped.withValue(recorder) {
            workspace.activeHistory = history(photos: 5, fill: 20)
        }
        #expect(workspace.activeHistory.undoStack.count == 2)
        #expect(recorder.historyPayloadBytes == 2_000)

        workspace.historyPayloadByteBudget = nil
        workspace.activeHistory = history(photos: 5, fill: 40)
        #expect(workspace.activeHistory.undoStack.count == 5)
    }

    @Test func replacingTheSetKeepsTheConfiguredBudget() {
        var workspace = ThumbnailVariantWorkspace(
            seedDocument: Support.document(text: "seed", imageData: nil),
            editorMode: .simple
        )
        workspace.historyPayloadByteBudget = 1_234
        workspace.replaceSet(ThumbnailVariantSet(seedDocument: Support.document(text: "new", imageData: nil), editorMode: .simple))
        #expect(workspace.historyPayloadByteBudget == 1_234)
    }
}
