//
//  FirstExportGuideCard.swift
//  ThumbnailMaker
//
//  FEATURE-13: inline checklist card for the first-export guide. It is not a
//  sheet or overlay, so it never covers the canvas. Every button relays to an
//  existing editor action; the card never edits the document itself.
//

import PhotosUI
import SwiftUI

struct FirstExportGuideActions {
    var imageSelection: Binding<PhotosPickerItem?>
    var openTemplates: () -> Void
    var focusTitle: () -> Void
    var checkSize: () -> Void
    var saveToPhotos: () -> Void
    var exportToFiles: () -> Void
    var share: () -> Void
    var startNewProject: (() -> Void)?
    var isBusy: Bool
}

struct FirstExportGuideCard: View {
    @ObservedObject var guide: FirstExportGuideController
    let snapshot: FirstExportGuideSnapshot
    let actions: FirstExportGuideActions

    var body: some View {
        switch guide.presentation {
        case .hidden:
            EmptyView()
        case .resumePill:
            resumePill
        case .completed:
            completedRow
        case .card:
            card
        }
    }

    // MARK: Card

    private var steps: [FirstExportGuideStep] { FirstExportGuideStep.allCases }

    private var currentStep: FirstExportGuideStep? { guide.progress.currentStep }

    private var stepNumber: Int {
        guard let currentStep, let index = steps.firstIndex(of: currentStep) else {
            return steps.count
        }
        return index + 1
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("First export", systemImage: "flag.checkered")
                    .font(.headline)
                Spacer()
                Text("Step \(stepNumber) of \(steps.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(steps) { step in
                    stepRow(step)
                }
            }

            if let currentStep {
                Text(currentStep.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                primaryActions(for: currentStep)
            }

            HStack(spacing: 16) {
                Button("Hide for now") { guide.pause() }
                    .accessibilityIdentifier("firstExportGuideHideButton")
                Button("Skip guide", role: .destructive) { guide.skip() }
                    .accessibilityIdentifier("firstExportGuideSkipButton")
                Spacer(minLength: 0)
                if let startNewProject = actions.startNewProject {
                    Button("New Project", action: startNewProject)
                        .accessibilityIdentifier("firstExportGuideNewProjectButton")
                        .accessibilityHint("Saves the current project to the library and opens an empty one")
                }
            }
            .font(.footnote)
            .buttonStyle(.borderless)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.25))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("firstExportGuideCard")
    }

    private func stepRow(_ step: FirstExportGuideStep) -> some View {
        let isDone = guide.progress.completedStepSet.contains(step)
        let isCurrent = step == currentStep
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: isDone ? "checkmark.circle.fill" : (isCurrent ? "circle.inset.filled" : "circle"))
                .foregroundStyle(isDone ? Color.green : (isCurrent ? Color.accentColor : Color.secondary))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                    .strikethrough(isDone, color: .secondary)
                if step == .checkReadiness, let score = snapshot.readinessScore, snapshot.hasExportableContent {
                    Text(snapshot.readinessHasWarnings ? "Readiness \(score), with notes below" : "Readiness \(score)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isDone ? "Done" : (isCurrent ? "Current step" : "Not done"))
        .accessibilityIdentifier("firstExportGuideStep-\(step.rawValue)")
    }

    @ViewBuilder
    private func primaryActions(for step: FirstExportGuideStep) -> some View {
        switch step {
        case .addVisual:
            HStack(spacing: 10) {
                PhotosPicker(selection: actions.imageSelection, matching: .images) {
                    Label(step.showMeTitle, systemImage: "photo")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("firstExportGuideShowMeButton")

                Button {
                    actions.openTemplates()
                } label: {
                    Label("Use a Template", systemImage: "square.grid.2x2")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("firstExportGuideTemplatesButton")
            }
        case .writeTitle:
            Button {
                actions.focusTitle()
            } label: {
                Label(step.showMeTitle, systemImage: "character.cursor.ibeam")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("firstExportGuideShowMeButton")
        case .checkReadiness:
            Button {
                actions.checkSize()
            } label: {
                Label(step.showMeTitle, systemImage: "gauge.with.dots.needle.33percent")
            }
            .buttonStyle(.borderedProminent)
            .disabled(actions.isBusy || !snapshot.hasExportableContent)
            .accessibilityIdentifier("firstExportGuideShowMeButton")
        case .export:
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { exportButtons }
                VStack(alignment: .leading, spacing: 8) { exportButtons }
            }
            .disabled(actions.isBusy || !snapshot.hasExportableContent)
        }
    }

    @ViewBuilder
    private var exportButtons: some View {
        Button {
            actions.saveToPhotos()
        } label: {
            Label("Photos", systemImage: "square.and.arrow.down")
        }
        .buttonStyle(.borderedProminent)
        .accessibilityLabel("Export: Save to Photos")
        .accessibilityIdentifier("firstExportGuideShowMeButton")

        Button {
            actions.exportToFiles()
        } label: {
            Label("Files", systemImage: "folder")
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Export: Save to Files")
        .accessibilityIdentifier("firstExportGuideFilesButton")

        Button {
            actions.share()
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Export: Share")
        .accessibilityIdentifier("firstExportGuideShareButton")
    }

    // MARK: Collapsed states

    private var resumePill: some View {
        HStack {
            Button {
                guide.resume()
            } label: {
                Label(
                    "Resume guide (\(guide.progress.completedSteps.count) of \(steps.count) done)",
                    systemImage: "flag.checkered"
                )
                .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("firstExportGuideResumeButton")
            Spacer(minLength: 0)
        }
    }

    private var completedRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("First export done")
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
            Button("Dismiss") { guide.dismissCompletion() }
                .font(.footnote)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("firstExportGuideDismissButton")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.green.opacity(0.1))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("firstExportGuideCompletedRow")
    }
}

// MARK: - Editor tracking hook

extension View {
    /// FEATURE-13: feeds editor state and confirmed export events into the
    /// shared guide. `offersOnLaunch` is true only for the editor that hosts
    /// the card (Simple); Premium only reports exports.
    func firstExportGuideTracking(
        _ guide: FirstExportGuideController,
        snapshot: FirstExportGuideSnapshot,
        exportEvent: ThumbnailExportEvent?,
        offersOnLaunch: Bool
    ) -> some View {
        self
            .onAppear {
                if offersOnLaunch {
                    guide.offerIfFirstRun(snapshot: snapshot)
                }
                guide.observe(snapshot)
            }
            .onChange(of: snapshot) { _, newValue in
                guide.observe(newValue)
            }
            .onChange(of: exportEvent) { _, newValue in
                guide.recordExport(newValue)
            }
    }
}
