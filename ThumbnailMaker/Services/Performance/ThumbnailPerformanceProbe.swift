//
//  ThumbnailPerformanceProbe.swift
//  ThumbnailMaker
//
//  APP-09: lightweight measurement. Each probe emits an os_signpost interval
//  (subsystem "ThumbnailMaker", category "Performance") for Instruments and a
//  sample to the shared in-memory recorder that backs the diagnostics panel.
//  Tests bind a private recorder with `ThumbnailPerformanceRecorder.$scoped`
//  so parallel tests never see each other's events.
//

import Foundation
import os

enum ThumbnailPerfOp: String, CaseIterable, Sendable {
    case historyCommit
    case draftSave
    case undoRedo
    case variantSwitch
    case imageEncode
    case assetDigest

    var displayName: String {
        switch self {
        case .historyCommit: return "Edit commit"
        case .draftSave: return "Save"
        case .undoRedo: return "Undo / redo"
        case .variantSwitch: return "Variant switch"
        case .imageEncode: return "Photo encode"
        case .assetDigest: return "Photo hash"
        }
    }

    /// Main-thread budget for this operation, when one is defined.
    var budgetMs: Double? {
        switch self {
        case .historyCommit: return ThumbnailPerformanceBudget.textCommitMainMs
        case .undoRedo: return ThumbnailPerformanceBudget.undoRedoMs
        case .variantSwitch: return ThumbnailPerformanceBudget.variantSwitchMs
        case .draftSave, .imageEncode, .assetDigest: return nil
        }
    }

    /// Footprint sampling costs a syscall; only top-level editor operations take it.
    fileprivate var samplesFootprint: Bool {
        switch self {
        case .imageEncode, .assetDigest: return false
        default: return true
        }
    }
}

struct ThumbnailPerformanceSample: Equatable, Sendable {
    let op: ThumbnailPerfOp
    let durationMs: Double
    let footprintBytes: UInt64?
    let recordedAt: Date
}

final class ThumbnailPerformanceRecorder: @unchecked Sendable {
    static let shared = ThumbnailPerformanceRecorder()

    /// A recorder bound to the current task (tests). Receives every sample the
    /// shared recorder does while the binding is active.
    @TaskLocal static var scoped: ThumbnailPerformanceRecorder?

    private let lock = NSLock()
    private let capacity: Int
    private var samples: [ThumbnailPerformanceSample] = []
    private var counts: [ThumbnailPerfOp: Int] = [:]
    private var historyPayload: Int?

    init(capacity: Int = 200) {
        self.capacity = max(1, capacity)
    }

    static func emit(_ sample: ThumbnailPerformanceSample) {
        shared.record(sample)
        scoped?.record(sample)
    }

    static func emitHistoryPayload(bytes: Int) {
        shared.setHistoryPayloadBytes(bytes)
        scoped?.setHistoryPayloadBytes(bytes)
    }

    func record(_ sample: ThumbnailPerformanceSample) {
        lock.lock()
        defer { lock.unlock() }
        samples.append(sample)
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
        counts[sample.op, default: 0] += 1
    }

    func setHistoryPayloadBytes(_ bytes: Int) {
        lock.lock()
        historyPayload = bytes
        lock.unlock()
    }

    /// Total events of `op` since the last reset (not limited by capacity).
    func count(of op: ThumbnailPerfOp) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[op] ?? 0
    }

    var recentSamples: [ThumbnailPerformanceSample] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    func lastSample(of op: ThumbnailPerfOp) -> ThumbnailPerformanceSample? {
        lock.lock()
        defer { lock.unlock() }
        return samples.last { $0.op == op }
    }

    var historyPayloadBytes: Int? {
        lock.lock()
        defer { lock.unlock() }
        return historyPayload
    }

    func reset() {
        lock.lock()
        samples.removeAll()
        counts.removeAll()
        lock.unlock()
    }
}

enum ThumbnailPerformanceProbe {
    private static let signposter = OSSignposter(subsystem: "ThumbnailMaker", category: "Performance")

    /// A running measurement. Call `end()` exactly once (typically via `defer`).
    struct Span {
        fileprivate let op: ThumbnailPerfOp
        fileprivate let start: UInt64
        fileprivate let state: OSSignpostIntervalState

        func end() {
            ThumbnailPerformanceProbe.signposter.endInterval("ThumbnailPerf", state)
            let elapsed = DispatchTime.now().uptimeNanoseconds &- start
            ThumbnailPerformanceRecorder.emit(
                ThumbnailPerformanceSample(
                    op: op,
                    durationMs: Double(elapsed) / 1_000_000,
                    footprintBytes: op.samplesFootprint ? ThumbnailMemoryFootprint.currentBytes() : nil,
                    recordedAt: Date()
                )
            )
        }
    }

    static func begin(_ op: ThumbnailPerfOp) -> Span {
        let state = signposter.beginInterval("ThumbnailPerf", id: signposter.makeSignpostID(), "\(op.rawValue, privacy: .public)")
        return Span(op: op, start: DispatchTime.now().uptimeNanoseconds, state: state)
    }

    static func measure<T>(_ op: ThumbnailPerfOp, _ body: () throws -> T) rethrows -> T {
        let span = begin(op)
        defer { span.end() }
        return try body()
    }
}
