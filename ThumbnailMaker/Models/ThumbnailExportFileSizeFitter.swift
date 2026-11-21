//
//  ThumbnailExportFileSizeFitter.swift
//  ThumbnailMaker
//
//  FEATURE-10: fits an encoded image under a byte budget by lowering ONLY the
//  compression quality, never below the budget's floor. It has no size or
//  format parameter, so it cannot change either. The result is always the
//  real encoded bytes, never an estimate.
//

import Foundation

enum ThumbnailExportFileSizeFitter {
    static let maxAttempts = 6
    static let pngOverBudgetMessage = "PNG has no quality setting; choose JPEG or WebP in the recipe to fit a file-size budget."

    enum Outcome: Equatable {
        case noBudget
        case withinBudget
        case reducedQuality(from: Double, to: Double)
        case overBudgetAtFloor(bytes: Int)
    }

    struct FitResult {
        let data: Data
        let quality: Double
        let attempts: Int
        let outcome: Outcome

        var fitsBudget: Bool {
            if case .overBudgetAtFloor = outcome { return false }
            return true
        }
    }

    static func fit(
        requestedQuality: Double,
        budget: ThumbnailExportFileSizeBudget?,
        format: ThumbnailExportFormat,
        encode: (Double) throws -> Data
    ) throws -> FitResult {
        let requested = ThumbnailExportRecipe.clampedQuality(requestedQuality)
        var attempts = 0

        func encodeAt(_ quality: Double) throws -> Data {
            if attempts > 0 { try Task.checkCancellation() }
            attempts += 1
            return try encode(quality)
        }

        let first = try encodeAt(requested)
        guard let budget else {
            return FitResult(data: first, quality: requested, attempts: attempts, outcome: .noBudget)
        }
        if first.count <= budget.maxBytes {
            return FitResult(data: first, quality: requested, attempts: attempts, outcome: .withinBudget)
        }
        guard format.supportsCompressionQuality else {
            return FitResult(data: first, quality: requested, attempts: attempts, outcome: .overBudgetAtFloor(bytes: first.count))
        }

        let floor = budget.effectiveFloor(requestedQuality: requested)
        var low = Int((floor * 100).rounded())
        var high = Int((requested * 100).rounded())
        guard low < high else {
            return FitResult(data: first, quality: requested, attempts: attempts, outcome: .overBudgetAtFloor(bytes: first.count))
        }

        let floorData = try encodeAt(Double(low) / 100)
        guard floorData.count <= budget.maxBytes else {
            return FitResult(
                data: floorData,
                quality: Double(low) / 100,
                attempts: attempts,
                outcome: .overBudgetAtFloor(bytes: floorData.count)
            )
        }

        // Invariant: `low` fits, `high` does not. Keep the highest that fits.
        var best = (quality: Double(low) / 100, data: floorData)
        while high - low > 1 && attempts < maxAttempts {
            let mid = (low + high) / 2
            let quality = Double(mid) / 100
            let data = try encodeAt(quality)
            if data.count <= budget.maxBytes {
                low = mid
                best = (quality, data)
            } else {
                high = mid
            }
        }

        return FitResult(
            data: best.data,
            quality: best.quality,
            attempts: attempts,
            outcome: .reducedQuality(from: requested, to: best.quality)
        )
    }
}
