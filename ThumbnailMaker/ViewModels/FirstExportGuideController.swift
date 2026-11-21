//
//  FirstExportGuideController.swift
//  ThumbnailMaker
//
//  FEATURE-13: app-wide owner of the first-export guide. Shared by both
//  editors, so a first export in Premium also completes the guide in Simple.
//  Every mutation runs the pure reducer and then persists; a persistence
//  failure is kept in memory and surfaced quietly in Settings (never an alert).
//

import Foundation

@MainActor
final class FirstExportGuideController: ObservableObject {
    static let shared = FirstExportGuideController(
        store: .forLaunch(arguments: ProcessInfo.processInfo.arguments)
    )

    @Published private(set) var progress: FirstExportGuideProgress
    @Published private(set) var persistenceError: String?

    private let store: FirstExportGuideStore
    private let isWritable: Bool
    private let now: () -> Date
    private var hasEvaluatedLaunchOffer = false
    private var lastSnapshot: FirstExportGuideSnapshot?

    init(store: FirstExportGuideStore, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
        let loaded = store.load()
        self.progress = loaded.progress
        self.isWritable = loaded.isWritable
    }

    var presentation: FirstExportGuidePresentation {
        FirstExportGuideReducer.presentation(for: progress)
    }

    var statusDescription: String {
        switch progress.status {
        case .notStarted: "Not started"
        case .active: "In progress (\(progress.completedSteps.count) of \(FirstExportGuideStep.allCases.count))"
        case .paused: "Hidden (\(progress.completedSteps.count) of \(FirstExportGuideStep.allCases.count) done)"
        case .skipped: "Skipped"
        case .completed: "First export done"
        }
    }

    /// Called when an editor appears. Only a true first run (never started,
    /// nothing on the canvas) starts the guide, and only once per launch.
    func offerIfFirstRun(snapshot: FirstExportGuideSnapshot) {
        guard !hasEvaluatedLaunchOffer else { return }
        hasEvaluatedLaunchOffer = true
        guard FirstExportGuideReducer.shouldOfferOnLaunch(progress, snapshot: snapshot) else { return }
        apply(.start(now()))
        observe(snapshot)
    }

    func start() { apply(.start(now())); replayLastSnapshot() }
    func pause() { apply(.pause(now())) }
    func resume() { apply(.resume(now())); replayLastSnapshot() }
    func skip() { apply(.skip(now())) }
    func restart() { apply(.restart) }
    func dismissCompletion() { apply(.dismissCompletion) }

    /// Settings entry point: resume where the user left off, or start over
    /// after a completed/never-started guide. Touches guide progress only.
    func showFromSettings() {
        switch progress.status {
        case .paused, .skipped, .active:
            resume()
        case .completed, .notStarted:
            apply(.restart)
            start()
        }
    }

    /// SHELL: finishing the Quick Create wizard is itself guided onboarding,
    /// so a guide that never started is not offered on top of it (the user
    /// can still start it from Settings). Progress already made is kept.
    func recordQuickCreateCompleted() {
        guard progress.status == .notStarted else { return }
        skip()
    }

    func observe(_ snapshot: FirstExportGuideSnapshot) {
        lastSnapshot = snapshot
        apply(.observe(snapshot))
    }

    func recordExport(_ event: ThumbnailExportEvent?) {
        guard let event else { return }
        apply(.exportSucceeded(event))
    }

    private func replayLastSnapshot() {
        if let lastSnapshot {
            apply(.observe(lastSnapshot))
        }
    }

    private func apply(_ action: FirstExportGuideAction) {
        let next = FirstExportGuideReducer.reduce(progress, action)
        guard next != progress else { return }
        progress = next
        guard isWritable else { return }
        do {
            try store.save(next)
            persistenceError = nil
        } catch {
            persistenceError = "Guide progress could not be saved: \(error.localizedDescription)"
        }
    }
}
