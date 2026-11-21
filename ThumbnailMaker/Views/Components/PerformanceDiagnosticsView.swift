//
//  PerformanceDiagnosticsView.swift
//  ThumbnailMaker
//
//  APP-09: shows the probe recorder against the budgets. Reachable from
//  Settings in Debug builds, or in any build launched with
//  `-ShowPerfDiagnostics`.
//

import SwiftUI

enum ThumbnailPerformanceDiagnostics {
    static var isAvailable: Bool {
        #if DEBUG
        // Hidden while capturing App Store screenshots so marketing shots show only
        // what customers see (release builds never show it without the launch flag).
        return !ProcessInfo.processInfo.arguments.contains("-UITestSeedShowcaseDesign")
        #else
        return ProcessInfo.processInfo.arguments.contains("-ShowPerfDiagnostics")
        #endif
    }
}

/// Plain values the view renders; built from a recorder so it is testable.
struct PerformanceDiagnosticsSnapshot: Equatable {
    struct OperationRow: Equatable, Identifiable {
        let op: ThumbnailPerfOp
        let count: Int
        let lastMs: Double?
        let budgetMs: Double?
        var id: String { op.rawValue }
        var isOverBudget: Bool {
            guard let lastMs, let budgetMs else { return false }
            return lastMs > budgetMs
        }
    }

    let rows: [OperationRow]
    let footprintBytes: UInt64?
    let peakFootprintBytes: UInt64?
    let historyPayloadBytes: Int?

    static func make(
        recorder: ThumbnailPerformanceRecorder,
        currentFootprint: UInt64? = ThumbnailMemoryFootprint.currentBytes()
    ) -> PerformanceDiagnosticsSnapshot {
        let samples = recorder.recentSamples
        return PerformanceDiagnosticsSnapshot(
            rows: ThumbnailPerfOp.allCases.map { op in
                OperationRow(
                    op: op,
                    count: recorder.count(of: op),
                    lastMs: samples.last { $0.op == op }?.durationMs,
                    budgetMs: op.budgetMs
                )
            },
            footprintBytes: currentFootprint,
            peakFootprintBytes: ThumbnailMemoryFootprint.peak(in: samples),
            historyPayloadBytes: recorder.historyPayloadBytes
        )
    }

    func row(for op: ThumbnailPerfOp) -> OperationRow? {
        rows.first { $0.op == op }
    }

    var isFootprintOverBudget: Bool {
        (footprintBytes ?? 0) > ThumbnailPerformanceBudget.editingFootprintBytes
    }

    var isHistoryPayloadOverBudget: Bool {
        (historyPayloadBytes ?? 0) > ThumbnailPerformanceBudget.historyPayloadByteBudget
    }

    static func megabytes<T: BinaryInteger>(_ bytes: T?) -> String {
        guard let bytes else { return "—" }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    static func milliseconds(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f ms", value)
    }
}

struct PerformanceDiagnosticsView: View {
    var recorder: ThumbnailPerformanceRecorder = .shared
    @State private var snapshot: PerformanceDiagnosticsSnapshot?

    var body: some View {
        List {
            if let snapshot {
                Section(header: Text("Memory")) {
                    metricRow(
                        "Footprint now",
                        value: PerformanceDiagnosticsSnapshot.megabytes(snapshot.footprintBytes),
                        budget: PerformanceDiagnosticsSnapshot.megabytes(ThumbnailPerformanceBudget.editingFootprintBytes),
                        isOverBudget: snapshot.isFootprintOverBudget,
                        identifier: "perfDiagnostics.footprintMB"
                    )
                    metricRow(
                        "Peak while editing",
                        value: PerformanceDiagnosticsSnapshot.megabytes(snapshot.peakFootprintBytes),
                        budget: nil,
                        isOverBudget: false,
                        identifier: "perfDiagnostics.peakFootprintMB"
                    )
                    metricRow(
                        "Undo history photos",
                        value: PerformanceDiagnosticsSnapshot.megabytes(snapshot.historyPayloadBytes),
                        budget: PerformanceDiagnosticsSnapshot.megabytes(ThumbnailPerformanceBudget.historyPayloadByteBudget),
                        isOverBudget: snapshot.isHistoryPayloadOverBudget,
                        identifier: "perfDiagnostics.historyPayloadMB"
                    )
                }

                Section(
                    header: Text("Operations"),
                    footer: Text("Last duration on this device. Photo encodes should only happen when a photo changes, not on text or style edits.")
                ) {
                    ForEach(snapshot.rows) { row in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.op.displayName)
                                Text("\(row.count) times")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .accessibilityIdentifier(row.op == .imageEncode ? "perfDiagnostics.encodeCount" : "perfDiagnostics.count.\(row.op.rawValue)")
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(PerformanceDiagnosticsSnapshot.milliseconds(row.lastMs))
                                    .foregroundColor(row.isOverBudget ? .red : .primary)
                                    .accessibilityIdentifier(row.op == .historyCommit ? "perfDiagnostics.lastCommitMs" : "perfDiagnostics.lastMs.\(row.op.rawValue)")
                                if let budget = row.budgetMs {
                                    Text("budget \(PerformanceDiagnosticsSnapshot.milliseconds(budget))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button("Refresh") { refresh() }
                    Button("Reset Counters") {
                        recorder.reset()
                        refresh()
                    }
                }
            } else {
                ProgressView()
            }
        }
        .accessibilityIdentifier("perfDiagnostics.panel")
        .navigationTitle("Performance")
        .onAppear { refresh() }
    }

    private func refresh() {
        snapshot = .make(recorder: recorder)
    }

    private func metricRow(
        _ title: String,
        value: String,
        budget: String?,
        isOverBudget: Bool,
        identifier: String
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .foregroundColor(isOverBudget ? .red : .primary)
                    .accessibilityIdentifier(identifier)
                if let budget {
                    Text("budget \(budget)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
