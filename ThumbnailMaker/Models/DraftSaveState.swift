//
//  DraftSaveState.swift
//  ThumbnailMaker
//
//  Tracks the lifecycle of a draft autosave so the UI can publish
//  saving / saved / failed states and offer a working retry.
//

import Foundation

enum DraftSaveState: Equatable {
    case idle
    case saving
    case saved(Date)
    case failed(message: String, attemptedAt: Date)

    var isSaving: Bool {
        if case .saving = self { return true } else { return false }
    }

    var lastSavedDate: Date? {
        if case .saved(let date) = self { return date } else { return nil }
    }

    var failureMessage: String? {
        if case .failed(let message, _) = self { return message } else { return nil }
    }
}
