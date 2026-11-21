//
//  ThumbnailExportQueueRunnerTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-10: sequential run, partial failure, retry of only failed jobs,
//  cooperative cancel, write-time conflict recheck.
//

import Foundation
import Testing
@testable import ThumbnailMaker

@MainActor
struct ThumbnailExportQueueRunnerTests {
    private typealias Support = ExportQueueTestSupport

    private func plan(
        _ destination: InMemoryExportDestination,
        recipe: ThumbnailExportRecipe = ExportQueueTestSupport.smallRecipe()
    ) throws -> ThumbnailExportQueuePlan {
        Support.plan(recipe: recipe, destination: try destination.snapshot())
    }

    @Test func allNineJobsSucceed() async throws {
        let renderer = CountingExportRenderer()
        let runner = ThumbnailExportQueueRunner(renderer: renderer)
        let destination = InMemoryExportDestination()
        let plan = try plan(destination)

        #expect(runner.progress == 0)
        await runner.run(plan, destination: destination)

        #expect(runner.completedCount == 9)
        #expect(runner.totalCount == 9)
        #expect(runner.progress == 1)
        #expect(runner.succeededCount == 9)
        #expect(runner.hasFinishedRun)
        #expect(!runner.isRunning)
        #expect(renderer.renderCount == 9)
        #expect(destination.writtenNames == plan.jobs.map(\.targetFileName))
        #expect(runner.resultSummary == "9 exported")
    }

    @Test func partialFailureContinuesAndRetryRedoesOnlyFailures() async throws {
        let renderer = CountingExportRenderer()
        let runner = ThumbnailExportQueueRunner(renderer: renderer)
        let destination = InMemoryExportDestination()
        let plan = try plan(destination)
        let failing = [plan.jobs[1].targetFileName, plan.jobs[6].targetFileName]
        destination.failingFileNames = Set(failing)
        destination.failOnce = true

        await runner.run(plan, destination: destination)

        #expect(runner.succeededCount == 7)
        #expect(runner.failedCount == 2)
        #expect(renderer.renderCount == 9)
        guard case .failed(let message)? = runner.state(for: plan.jobs[1].id) else {
            Issue.record("expected failure state")
            return
        }
        #expect(message.contains("Injected failure"))
        #expect(runner.retryableJobIDs == [plan.jobs[1].id, plan.jobs[6].id])

        let succeededBefore = plan.jobs.filter { !failing.contains($0.targetFileName) }
            .compactMap { destination.data(named: $0.targetFileName) }

        let retryPlan = Support.plan(recipe: Support.smallRecipe(), destination: try destination.snapshot())
        await runner.run(retryPlan, destination: destination, onlyJobIDs: runner.retryableJobIDs)

        #expect(renderer.renderCount == 11)
        #expect(runner.succeededCount == 9)
        #expect(runner.failedCount == 0)
        // The retried files keep their planned names (they never existed).
        #expect(destination.data(named: failing[0]) != nil)
        #expect(destination.data(named: failing[1]) != nil)
        let succeededAfter = plan.jobs.filter { !failing.contains($0.targetFileName) }
            .compactMap { destination.data(named: $0.targetFileName) }
        #expect(succeededBefore == succeededAfter)
        #expect(destination.writtenNames.count == 9)
    }

    @Test func cancelLeavesRemainingJobsNotRunAndRetryRunsThem() async throws {
        let renderer = CountingExportRenderer()
        let runner = ThumbnailExportQueueRunner(renderer: renderer)
        let destination = InMemoryExportDestination()
        destination.afterWrite = { count in
            if count == 3 { runner.cancel() }
        }
        let plan = try plan(destination)

        await runner.run(plan, destination: destination)

        #expect(destination.writtenNames.count == 3)
        #expect(runner.succeededCount == 3)
        #expect(runner.notRunCount == 6)
        #expect(renderer.renderCount == 3)
        #expect(runner.resultSummary == "3 exported · 6 not run")
        for job in plan.jobs.dropFirst(3) {
            #expect(runner.state(for: job.id) == .notRun)
            #expect(destination.data(named: job.targetFileName) == nil)
        }

        destination.afterWrite = nil
        let retryPlan = Support.plan(recipe: Support.smallRecipe(), destination: try destination.snapshot())
        await runner.run(retryPlan, destination: destination, onlyJobIDs: runner.retryableJobIDs)
        #expect(renderer.renderCount == 9)
        #expect(runner.succeededCount == 9)
        #expect(destination.writtenNames.count == 9)
    }

    @Test func fileAppearingAfterReviewIsNotOverwrittenWithKeepBoth() async throws {
        let runner = ThumbnailExportQueueRunner(renderer: CountingExportRenderer())
        let destination = InMemoryExportDestination()
        let plan = try plan(destination)
        // Appears between review and run.
        destination.seed([plan.jobs[0].fileName])
        let original = destination.data(named: plan.jobs[0].fileName)

        await runner.run(plan, destination: destination)

        #expect(destination.data(named: plan.jobs[0].fileName) == original)
        let renamed = plan.jobs[0].fileName.replacingOccurrences(of: ".jpg", with: "-2.jpg")
        #expect(destination.data(named: renamed) != nil)
        guard case .succeeded(let outcome)? = runner.state(for: plan.jobs[0].id) else {
            Issue.record("expected success")
            return
        }
        #expect(outcome.fileName == renamed)
    }

    @Test func skipPolicyConflictIsSkippedNotFailed() async throws {
        let renderer = CountingExportRenderer()
        let runner = ThumbnailExportQueueRunner(renderer: renderer)
        let destination = InMemoryExportDestination()
        let recipe = Support.smallRecipe(policy: .skip)
        let firstName = Support.plan(recipe: recipe).jobs[0].fileName
        destination.seed([firstName])
        let plan = try plan(destination, recipe: recipe)

        await runner.run(plan, destination: destination)

        #expect(runner.state(for: plan.jobs[0].id) == .skipped("\(firstName) already exists"))
        #expect(runner.skippedCount == 1)
        #expect(runner.failedCount == 0)
        #expect(renderer.renderCount == 8)
        #expect(runner.retryableJobIDs.isEmpty)
    }

    @Test func overBudgetAtFloorFailsAndWritesNothing() async throws {
        let runner = ThumbnailExportQueueRunner(renderer: CountingExportRenderer())
        let destination = InMemoryExportDestination()
        var recipe = Support.smallRecipe()
        recipe.formatRawValue = ThumbnailExportFormat.png.rawValue
        recipe.fileSizeBudget = ThumbnailExportFileSizeBudget(maxBytes: 10)
        recipe.sizes = [recipe.sizes[0]]
        let plan = try plan(destination, recipe: recipe)

        await runner.run(plan, destination: destination)

        #expect(runner.failedCount == 3)
        #expect(destination.writtenNames.isEmpty)
        #expect(runner.state(for: plan.jobs[0].id) == .failed(ThumbnailExportFileSizeFitter.pngOverBudgetMessage))
    }

    @Test func blockedJobsAreNeverRendered() async throws {
        let renderer = CountingExportRenderer()
        let runner = ThumbnailExportQueueRunner(renderer: renderer)
        let destination = InMemoryExportDestination()
        var recipe = Support.smallRecipe()
        recipe.sizes.append(ThumbnailExportRecipeSize(width: 1080, height: 1920))
        let plan = try plan(destination, recipe: recipe)
        #expect(plan.blockedJobs.count == 3)

        await runner.run(plan, destination: destination)

        #expect(renderer.renderCount == 9)
        #expect(runner.totalCount == 9)
        for job in plan.blockedJobs {
            #expect(runner.state(for: job.id) == nil)
        }
    }
}
