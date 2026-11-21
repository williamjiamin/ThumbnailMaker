//
//  FirstExportGuide.swift
//  ThumbnailMaker
//
//  FEATURE-13: a short, optional, resumable first-export guide.
//
//  The guide is app-level state (never stored in a ThumbnailDocument or a
//  project). Its steps are *derived* from a read-only snapshot of the editor,
//  so the guide can never change the document by itself, and starting it on
//  existing work simply shows those steps as already done. The export step is
//  only satisfied by a confirmed export event (Photos saved, Files export
//  succeeded, or a share activity completed) — never by a size check.
//

import Foundation

enum FirstExportGuideStep: String, Codable, CaseIterable, Identifiable {
    case addVisual
    case writeTitle
    case checkReadiness
    case export

    var id: String { rawValue }

    var title: String {
        switch self {
        case .addVisual: "Add a photo or template"
        case .writeTitle: "Write a short title"
        case .checkReadiness: "Check readiness and size"
        case .export: "Export your thumbnail"
        }
    }

    var detail: String {
        switch self {
        case .addVisual:
            "Pick a background photo, or start from a template."
        case .writeTitle:
            "Type the overlay text viewers will read."
        case .checkReadiness:
            "Run the export size check and review the readiness notes."
        case .export:
            "Save to Photos, export to Files, or share."
        }
    }

    var showMeTitle: String {
        switch self {
        case .addVisual: "Choose Photo"
        case .writeTitle: "Edit Title"
        case .checkReadiness: "Check Size"
        case .export: "Export"
        }
    }
}

enum FirstExportGuideStatus: String, Codable, Equatable {
    case notStarted
    case active
    case paused
    case skipped
    case completed
}

enum ThumbnailExportEventKind: String, Codable, Equatable {
    case photos
    case files
    case share
}

/// A confirmed, user-visible export. Published by the editor view models only
/// from success paths; `checkExportSize` never produces one.
struct ThumbnailExportEvent: Equatable, Identifiable {
    let id: UUID
    let kind: ThumbnailExportEventKind
    let date: Date
    let editorMode: ThumbnailDocumentEditorMode

    init(
        id: UUID = UUID(),
        kind: ThumbnailExportEventKind,
        date: Date = Date(),
        editorMode: ThumbnailDocumentEditorMode
    ) {
        self.id = id
        self.kind = kind
        self.date = date
        self.editorMode = editorMode
    }
}

struct FirstExportGuideProgress: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = FirstExportGuideProgress.currentSchemaVersion
    var status: FirstExportGuideStatus = .notStarted
    var currentStep: FirstExportGuideStep?
    var completedSteps: [FirstExportGuideStep] = []
    var startedAt: Date?
    var pausedAt: Date?
    var skippedAt: Date?
    var completedAt: Date?
    var firstExportKind: ThumbnailExportEventKind?
    var lastEditorMode: ThumbnailDocumentEditorMode?
    /// True once the "first export done" row has been seen and dismissed, or
    /// when completion happened outside the guide (nothing to celebrate).
    var completionAcknowledged: Bool = false

    init(
        status: FirstExportGuideStatus = .notStarted,
        currentStep: FirstExportGuideStep? = nil,
        completedSteps: [FirstExportGuideStep] = []
    ) {
        self.status = status
        self.currentStep = currentStep
        self.completedSteps = completedSteps
    }

    var isSupported: Bool {
        schemaVersion <= FirstExportGuideProgress.currentSchemaVersion
    }

    var completedStepSet: Set<FirstExportGuideStep> {
        Set(completedSteps)
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, status, currentStep, completedSteps, startedAt, pausedAt
        case skippedAt, completedAt, firstExportKind, lastEditorMode, completionAcknowledged
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        let statusRaw = try container.decodeIfPresent(String.self, forKey: .status)
        status = statusRaw.flatMap(FirstExportGuideStatus.init(rawValue:)) ?? .notStarted
        let currentRaw = try container.decodeIfPresent(String.self, forKey: .currentStep)
        currentStep = currentRaw.flatMap(FirstExportGuideStep.init(rawValue:))
        // Unknown step names (from a future build) are dropped, not fatal.
        let rawSteps = (try? container.decodeIfPresent([String].self, forKey: .completedSteps)) ?? nil
        completedSteps = FirstExportGuideReducer.ordered(
            Set((rawSteps ?? []).compactMap(FirstExportGuideStep.init(rawValue:)))
        )
        startedAt = try? container.decodeIfPresent(Date.self, forKey: .startedAt)
        pausedAt = try? container.decodeIfPresent(Date.self, forKey: .pausedAt)
        skippedAt = try? container.decodeIfPresent(Date.self, forKey: .skippedAt)
        completedAt = try? container.decodeIfPresent(Date.self, forKey: .completedAt)
        let kindRaw = (try? container.decodeIfPresent(String.self, forKey: .firstExportKind)) ?? nil
        firstExportKind = kindRaw.flatMap(ThumbnailExportEventKind.init(rawValue:))
        let modeRaw = (try? container.decodeIfPresent(String.self, forKey: .lastEditorMode)) ?? nil
        lastEditorMode = modeRaw.flatMap(ThumbnailDocumentEditorMode.init(rawValue:))
        let acknowledged = (try? container.decodeIfPresent(Bool.self, forKey: .completionAcknowledged)) ?? nil
        completionAcknowledged = acknowledged ?? (status == .completed)
    }
}

/// Read-only facts about the editor. Built from configurations only; holding
/// one can never mutate a document.
struct FirstExportGuideSnapshot: Equatable {
    var hasVisual: Bool
    var hasTitle: Bool
    var hasSizeCheck: Bool
    var readinessScore: String?
    var readinessHasWarnings: Bool
    var hasExportableContent: Bool

    static let empty = FirstExportGuideSnapshot(
        hasVisual: false,
        hasTitle: false,
        hasSizeCheck: false,
        readinessScore: nil,
        readinessHasWarnings: false,
        hasExportableContent: false
    )

    static func make(
        simple configuration: SimpleMakerConfigurationModel,
        exportReport: ThumbnailExportReport?
    ) -> FirstExportGuideSnapshot {
        make(
            hasBackgroundVisual: configuration.selectedImage != nil,
            overlayText: configuration.overlayText,
            layers: configuration.layers,
            exportReport: exportReport,
            readiness: ThumbnailReadinessAnalyzer.analyze(configuration)
        )
    }

    static func make(
        premium configuration: PremiumMakerConfigurationModel,
        exportReport: ThumbnailExportReport?
    ) -> FirstExportGuideSnapshot {
        make(
            hasBackgroundVisual: configuration.selectedImage != nil
                || configuration.circularProfile?.image != nil,
            overlayText: configuration.overlayText,
            layers: configuration.layers,
            exportReport: exportReport,
            readiness: ThumbnailReadinessAnalyzer.analyze(configuration)
        )
    }

    static func make(
        hasBackgroundVisual: Bool,
        overlayText: String,
        layers: [ThumbnailDocumentLayer],
        exportReport: ThumbnailExportReport?,
        readiness: ThumbnailReadinessReport?
    ) -> FirstExportGuideSnapshot {
        var hasVisualLayer = false
        var hasTextLayer = false
        for layer in layers {
            switch layer.content {
            case .image, .shape:
                hasVisualLayer = true
            case .text(let content):
                if !content.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    hasTextLayer = true
                }
            case nil:
                break
            }
        }
        let hasOverlayText = !overlayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasVisual = hasBackgroundVisual || hasVisualLayer
        let hasTitle = hasOverlayText || hasTextLayer
        return FirstExportGuideSnapshot(
            hasVisual: hasVisual,
            hasTitle: hasTitle,
            hasSizeCheck: exportReport != nil,
            readinessScore: readiness?.displayScore,
            readinessHasWarnings: readiness?.hasWarnings ?? false,
            hasExportableContent: hasBackgroundVisual || !overlayText.isEmpty
                || layers.hasContentLayers
        )
    }
}

enum FirstExportGuideAction: Equatable {
    case start(Date)
    case pause(Date)
    case resume(Date)
    case skip(Date)
    case restart
    case dismissCompletion
    case observe(FirstExportGuideSnapshot)
    case exportSucceeded(ThumbnailExportEvent)
}

/// What the editor should show for the current progress.
enum FirstExportGuidePresentation: Equatable {
    case hidden
    case card
    case resumePill
    case completed
}

enum FirstExportGuideReducer {
    static func ordered(_ steps: Set<FirstExportGuideStep>) -> [FirstExportGuideStep] {
        FirstExportGuideStep.allCases.filter { steps.contains($0) }
    }

    static func satisfiedSteps(
        _ snapshot: FirstExportGuideSnapshot,
        exported: Bool
    ) -> Set<FirstExportGuideStep> {
        var steps = Set<FirstExportGuideStep>()
        if snapshot.hasVisual { steps.insert(.addVisual) }
        if snapshot.hasTitle { steps.insert(.writeTitle) }
        // Readiness is advisory: a size check marks the step done even when the
        // analyzer still has warnings.
        if snapshot.hasSizeCheck && snapshot.hasExportableContent { steps.insert(.checkReadiness) }
        if exported { steps.insert(.export) }
        return steps
    }

    static func nextStep(_ satisfied: Set<FirstExportGuideStep>) -> FirstExportGuideStep? {
        FirstExportGuideStep.allCases.first { !satisfied.contains($0) }
    }

    static func reduce(
        _ progress: FirstExportGuideProgress,
        _ action: FirstExportGuideAction
    ) -> FirstExportGuideProgress {
        var next = progress
        switch action {
        case .start(let now), .resume(let now):
            guard progress.status != .completed else { return progress }
            next.status = .active
            if next.startedAt == nil { next.startedAt = now }
            next.pausedAt = nil
            next.skippedAt = nil
            if next.currentStep == nil {
                next.currentStep = nextStep(progress.completedStepSet) ?? .addVisual
            }
        case .pause(let now):
            guard progress.status == .active else { return progress }
            next.status = .paused
            next.pausedAt = now
        case .skip(let now):
            guard progress.status != .completed, progress.status != .skipped else { return progress }
            next.status = .skipped
            next.skippedAt = now
        case .restart:
            next = FirstExportGuideProgress()
        case .dismissCompletion:
            guard progress.status == .completed else { return progress }
            next.completionAcknowledged = true
        case .observe(let snapshot):
            // Only a running guide follows the editor. Paused keeps its place,
            // and completion never regresses.
            guard progress.status == .active else { return progress }
            let exported = progress.completedStepSet.contains(.export)
            let satisfied = satisfiedSteps(snapshot, exported: exported)
            next.completedSteps = ordered(satisfied)
            next.currentStep = nextStep(satisfied)
        case .exportSucceeded(let event):
            next.lastEditorMode = event.editorMode
            guard progress.status != .completed else { return next }
            let wasGuiding = progress.status == .active || progress.status == .paused
            var steps = progress.completedStepSet
            steps.insert(.export)
            next.completedSteps = ordered(steps)
            next.currentStep = nil
            next.status = .completed
            next.completedAt = event.date
            next.firstExportKind = event.kind
            next.pausedAt = nil
            // A direct journey (guide never started / skipped) completes silently.
            next.completionAcknowledged = !wasGuiding
        }
        return next
    }

    static func shouldOfferOnLaunch(
        _ progress: FirstExportGuideProgress,
        snapshot: FirstExportGuideSnapshot
    ) -> Bool {
        progress.isSupported
            && progress.status == .notStarted
            && !snapshot.hasExportableContent
    }

    static func presentation(for progress: FirstExportGuideProgress) -> FirstExportGuidePresentation {
        guard progress.isSupported else { return .hidden }
        switch progress.status {
        case .active: return .card
        case .paused: return .resumePill
        case .completed: return progress.completionAcknowledged ? .hidden : .completed
        case .notStarted, .skipped: return .hidden
        }
    }
}
