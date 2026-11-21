//
//  ThumbnailExportQueueRunner.swift
//  ThumbnailMaker
//
//  FEATURE-10: runs a reviewed ThumbnailExportQueuePlan one job at a time.
//
//  - Render on the main actor (SwiftUI ImageRenderer requires it), then encode
//    and fit the file size off the main actor, then write.
//  - A failing job is marked failed and the queue continues.
//  - Cancel is cooperative: it takes effect between jobs or between fitter
//    attempts. A job cancelled before its write writes nothing, so there are
//    never partial files. Unprocessed jobs become "not run".
//  - Retry runs only failed / not-run jobs; succeeded files are never redone.
//

import Foundation
import UIKit

struct ThumbnailExportJobOutcome: Equatable {
    let fileName: String
    let url: URL?
    let bytes: Int
    let requestedQuality: Double
    let quality: Double

    var qualityReduced: Bool { quality < requestedQuality - 0.0001 }
}

enum ThumbnailExportJobState: Equatable {
    case pending
    case running
    case succeeded(ThumbnailExportJobOutcome)
    case failed(String)
    case skipped(String)
    case notRun

    var isRetryable: Bool {
        switch self {
        case .failed, .notRun: return true
        default: return false
        }
    }
}

@MainActor
final class ThumbnailExportQueueRunner: ObservableObject {
    @Published private(set) var jobStates: [String: ThumbnailExportJobState] = [:]
    @Published private(set) var isRunning = false
    @Published private(set) var isCancelling = false
    @Published private(set) var totalCount = 0
    @Published private(set) var completedCount = 0
    @Published private(set) var hasFinishedRun = false

    private let renderer: ThumbnailExportJobRendering
    private var runTask: Task<Void, Never>?

    init(renderer: ThumbnailExportJobRendering? = nil) {
        self.renderer = renderer ?? ThumbnailQueueDocumentRenderer()
    }

    var progress: Double {
        totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount)
    }

    func state(for jobID: String) -> ThumbnailExportJobState? { jobStates[jobID] }

    var succeededCount: Int { count { if case .succeeded = $0 { return true }; return false } }
    var failedCount: Int { count { if case .failed = $0 { return true }; return false } }
    var skippedCount: Int { count { if case .skipped = $0 { return true }; return false } }
    var notRunCount: Int { count { $0 == .notRun } }
    var retryableJobIDs: Set<String> { Set(jobStates.filter { $0.value.isRetryable }.map(\.key)) }

    var resultSummary: String {
        var parts = ["\(succeededCount) exported"]
        if failedCount > 0 { parts.append("\(failedCount) failed") }
        if skippedCount > 0 { parts.append("\(skippedCount) skipped") }
        if notRunCount > 0 { parts.append("\(notRunCount) not run") }
        return parts.joined(separator: " · ")
    }

    private func count(where predicate: (ThumbnailExportJobState) -> Bool) -> Int {
        jobStates.values.filter(predicate).count
    }

    func reset() {
        guard !isRunning else { return }
        jobStates = [:]
        totalCount = 0
        completedCount = 0
        hasFinishedRun = false
    }

    /// Runs `plan`. With `onlyJobIDs`, runs just those jobs and keeps every
    /// other job's state (used by Retry).
    func run(
        _ plan: ThumbnailExportQueuePlan,
        destination: ThumbnailExportDestinationWriting,
        onlyJobIDs: Set<String>? = nil
    ) async {
        guard !isRunning else { return }

        let jobs = plan.jobs.filter { job in
            guard !job.isBlocked else { return false }
            return onlyJobIDs.map { $0.contains(job.id) } ?? true
        }

        var states = onlyJobIDs == nil ? [:] : jobStates
        var runnable: [ThumbnailExportQueueJob] = []
        for job in jobs {
            switch job.conflict {
            case .existsWillSkip:
                states[job.id] = .skipped("\(job.fileName) already exists")
            case .duplicateInQueue:
                states[job.id] = .skipped("Same file name as an earlier row")
            default:
                states[job.id] = .pending
                runnable.append(job)
            }
        }

        jobStates = states
        totalCount = runnable.count
        completedCount = 0
        isRunning = true
        isCancelling = false
        hasFinishedRun = false

        let task = Task { [weak self] in
            guard let self else { return }
            await self.process(runnable, destination: destination)
        }
        runTask = task
        await task.value

        runTask = nil
        isRunning = false
        isCancelling = false
        hasFinishedRun = true
    }

    func cancel() {
        guard isRunning, let runTask else { return }
        isCancelling = true
        runTask.cancel()
    }

    // MARK: Processing

    private func process(_ jobs: [ThumbnailExportQueueJob], destination: ThumbnailExportDestinationWriting) async {
        for (index, job) in jobs.enumerated() {
            if Task.isCancelled {
                markNotRun(jobs[index...])
                return
            }

            jobStates[job.id] = .running
            do {
                let image = try autoreleasepool {
                    try renderer.render(job.document, size: job.size)
                }
                let fit = try await Self.encodeAndFit(image: image, job: job)
                try Task.checkCancellation()

                guard fit.fitsBudget else {
                    throw ThumbnailExportQueueError.overBudget(Self.overBudgetMessage(job: job, fit: fit))
                }

                let result = try await destination.write(
                    fit.data,
                    fileName: job.targetFileName,
                    format: job.format,
                    policy: job.overwritePolicy
                )
                switch result {
                case let .written(fileName, url):
                    jobStates[job.id] = .succeeded(
                        ThumbnailExportJobOutcome(
                            fileName: fileName,
                            url: url,
                            bytes: fit.data.count,
                            requestedQuality: job.quality,
                            quality: fit.quality
                        )
                    )
                case .skippedExisting(let fileName):
                    jobStates[job.id] = .skipped("\(fileName) already exists")
                }
            } catch is CancellationError {
                markNotRun(jobs[index...])
                return
            } catch {
                jobStates[job.id] = .failed(Self.message(for: error))
            }
            completedCount += 1
        }
    }

    private func markNotRun(_ jobs: ArraySlice<ThumbnailExportQueueJob>) {
        for job in jobs {
            jobStates[job.id] = .notRun
        }
    }

    nonisolated private static func encodeAndFit(
        image: UIImage,
        job: ThumbnailExportQueueJob
    ) async throws -> ThumbnailExportFileSizeFitter.FitResult {
        let options = job.exportOptions
        let quality = job.quality
        let budget = job.budget
        let format = job.format
        let work = Task.detached(priority: .utility) {
            try ThumbnailExportFileSizeFitter.fit(
                requestedQuality: quality,
                budget: budget,
                format: format
            ) { attemptQuality in
                var attemptOptions = options
                attemptOptions.compressionQuality = attemptQuality
                return try ThumbnailExporter.encodedData(for: image, options: attemptOptions)
            }
        }
        return try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
        }
    }

    static func overBudgetMessage(job: ThumbnailExportQueueJob, fit: ThumbnailExportFileSizeFitter.FitResult) -> String {
        guard job.format.supportsCompressionQuality else {
            return ThumbnailExportFileSizeFitter.pngOverBudgetMessage
        }
        let size = ThumbnailExportFileSize(byteCount: fit.data.count).formatted
        let budget = ThumbnailExportFileSize(byteCount: job.budget?.maxBytes ?? 0).formatted
        let floor = Int((fit.quality * 100).rounded())
        return "Still \(size) at the lowest allowed quality (\(floor)%), over the \(budget) budget. Nothing was written. Lower the quality floor or remove this size."
    }

    static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
