//
//  PersonalTemplateLibraryModel.swift
//  ThumbnailMaker
//
//  FEATURE-05: shared by both editors so neither view model grows a second
//  store. Every mutation is transactional: it is applied to a copy, saved,
//  and only published when the save succeeded. A failed save leaves the
//  previous library (in memory and on disk) intact and explains why.
//

import Foundation
import SwiftUI

@MainActor
final class PersonalTemplateLibraryModel: ObservableObject {
    static let shared: PersonalTemplateLibraryModel = {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-DisableDraftPersistence") {
            // UI tests: keep templates in memory so runs never leak into each other.
            return PersonalTemplateLibraryModel(store: nil)
        }
        return PersonalTemplateLibraryModel(store: PersonalTemplateStore())
    }()

    @Published private(set) var library = PersonalTemplateLibrary()
    @Published var errorMessage: String?
    /// Set when an unreadable library file was moved aside on launch.
    @Published var recoveryNotice: String?
    /// Warnings from the most recent template application, shown by the editor
    /// once the gallery sheet has finished dismissing.
    @Published var applicationWarnings: [ThumbnailTemplateWarning] = []
    private var pendingWarnings: [ThumbnailTemplateWarning] = []

    let store: PersonalTemplateStore?
    private let now: () -> Date

    init(store: PersonalTemplateStore?, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
        reload()
    }

    var activeTemplates: [ThumbnailTemplate] { library.active }
    var favoriteTemplates: [ThumbnailTemplate] { library.favorites }
    var trashedTemplates: [ThumbnailTemplate] { library.trashed }

    func reload() {
        guard let store else { return }
        let result = store.loadRecoveringFromCorruption(now: now())
        library = result.library
        if let quarantined = result.quarantined {
            recoveryNotice = "Your saved templates could not be read, so a fresh library was started. The old file was kept as \(quarantined.lastPathComponent)."
        }
    }

    // MARK: - Capture

    @discardableResult
    func saveTemplate(
        from document: ThumbnailDocument,
        name: String,
        category: ThumbnailTemplateCategory,
        isFavorite: Bool = false,
        retainedLayerIDs: Set<String> = [],
        backgroundPolicy: ThumbnailTemplateSlotPolicy = .replaceFromProject,
        profilePolicy: ThumbnailTemplateSlotPolicy = .replaceFromProject,
        titlePolicy: ThumbnailTemplateSlotPolicy = .replaceFromProject
    ) -> ThumbnailTemplate? {
        let template = ThumbnailTemplate.capture(
            from: document,
            name: name,
            category: category,
            retainedLayerIDs: retainedLayerIDs,
            backgroundPolicy: backgroundPolicy,
            profilePolicy: profilePolicy,
            titlePolicy: titlePolicy,
            isFavorite: isFavorite,
            now: now()
        )
        return commit { library, date in
            try PersonalTemplateStore.validateSize(of: template)
            return try library.insert(template, now: date)
        }
    }

    // MARK: - Management

    @discardableResult
    func rename(id: String, to name: String) -> Bool {
        commit { library, date in try library.rename(id: id, to: name, now: date) } != nil
    }

    @discardableResult
    func setFavorite(_ isFavorite: Bool, id: String) -> Bool {
        commit { library, date in try library.setFavorite(isFavorite, id: id, now: date) } != nil
    }

    @discardableResult
    func duplicate(id: String) -> ThumbnailTemplate? {
        commit { library, date in try library.duplicate(id: id, now: date) }
    }

    @discardableResult
    func moveToTrash(id: String) -> Bool {
        commit { library, date in try library.softDelete(id: id, now: date) } != nil
    }

    @discardableResult
    func restore(id: String) -> Bool {
        commit { library, date in try library.restore(id: id, now: date) } != nil
    }

    @discardableResult
    func purge(id: String) -> Bool {
        commit { library, date in try library.purge(id: id, now: date) } != nil
    }

    // MARK: - Application feedback

    func reportApplication(_ warnings: [ThumbnailTemplateWarning]) {
        pendingWarnings = warnings
    }

    /// Called from the gallery sheet's onDismiss so the alert never races the sheet.
    func presentPendingWarnings() {
        guard !pendingWarnings.isEmpty else { return }
        applicationWarnings = pendingWarnings
        pendingWarnings = []
    }

    // MARK: - Transaction

    private func commit<T>(_ mutate: (inout PersonalTemplateLibrary, Date) throws -> T) -> T? {
        var candidate = library
        do {
            let result = try mutate(&candidate, now())
            try store?.save(candidate)
            library = candidate
            errorMessage = nil
            return result
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }
}
