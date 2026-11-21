//
//  ThumbnailVariantHistoryBook.swift
//  ThumbnailMaker
//
//  FEATURE-02: independent undo/redo per variant slot. Composes the existing
//  `ThumbnailDocumentHistory` rather than changing it.
//

import Foundation

struct ThumbnailVariantHistoryBook: Equatable {
    private var histories: [ThumbnailVariantSlot: ThumbnailDocumentHistory] = [:]
    private var baselines: [ThumbnailVariantSlot: ThumbnailDocument] = [:]
    private let defaultBaseline: ThumbnailDocument

    init(defaultBaseline: ThumbnailDocument) {
        self.defaultBaseline = ThumbnailDocumentHistory.snapshot(defaultBaseline)
    }

    func history(for slot: ThumbnailVariantSlot) -> ThumbnailDocumentHistory {
        histories[slot] ?? ThumbnailDocumentHistory()
    }

    mutating func setHistory(_ history: ThumbnailDocumentHistory, for slot: ThumbnailVariantSlot) {
        histories[slot] = history
    }

    func baseline(for slot: ThumbnailVariantSlot) -> ThumbnailDocument {
        baselines[slot] ?? defaultBaseline
    }

    func hasBaseline(for slot: ThumbnailVariantSlot) -> Bool {
        baselines[slot] != nil
    }

    mutating func setBaseline(_ document: ThumbnailDocument, for slot: ThumbnailVariantSlot) {
        baselines[slot] = document
    }

    /// Fresh stacks and a baseline equal to `document`.
    mutating func resetSlot(_ slot: ThumbnailVariantSlot, to document: ThumbnailDocument) {
        histories[slot] = ThumbnailDocumentHistory()
        baselines[slot] = ThumbnailDocumentHistory.snapshot(document)
    }

    mutating func discardSlot(_ slot: ThumbnailVariantSlot) {
        histories[slot] = nil
        baselines[slot] = nil
    }

    // MARK: APP-09 payload budget

    /// Distinct image bytes held by every slot's stacks and baselines. A photo
    /// shared across snapshots or slots counts once.
    func totalPayloadBytes() -> Int {
        var documents: [ThumbnailDocument] = [defaultBaseline]
        for slot in ThumbnailVariantSlot.allCases {
            if let history = histories[slot] {
                documents.append(contentsOf: history.allSnapshots)
            }
            if let baseline = baselines[slot] {
                documents.append(baseline)
            }
        }
        return ThumbnailDocumentPayloads.uniqueByteCount(of: documents)
    }

    /// Trims history until the distinct payload bytes fit `budget`. Inactive
    /// slots lose their oldest undo steps, then their redo steps; the active
    /// slot then loses its oldest undo and furthest redo steps but always keeps
    /// one of each it had. Baselines are never trimmed. Returns the bytes left.
    @discardableResult
    mutating func enforcePayloadBudget(_ budget: Int, activeSlot: ThumbnailVariantSlot) -> Int {
        var total = totalPayloadBytes()
        guard total > budget else { return total }

        let inactiveSlots = ThumbnailVariantSlot.allCases.filter { $0 != activeSlot && histories[$0] != nil }
        let steps: [(ThumbnailVariantSlot, (inout ThumbnailDocumentHistory) -> Bool)] =
            inactiveSlots.map { ($0, { $0.dropOldestUndo() }) }
            + inactiveSlots.map { ($0, { $0.dropFurthestRedo() }) }
            + [
                (activeSlot, { $0.dropOldestUndo(keeping: 1) }),
                (activeSlot, { $0.dropFurthestRedo(keeping: 1) })
            ]

        for (slot, drop) in steps {
            guard var history = histories[slot] else { continue }
            while total > budget, drop(&history) {
                histories[slot] = history
                total = totalPayloadBytes()
            }
            if total <= budget { break }
        }
        return total
    }
}
