//
//  PersonalTemplateTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-05: personal templates - model, capture, instantiation, library, store.
//

import Foundation
import Testing
@testable import ThumbnailMaker

enum PersonalTemplateFixtures {
    static let bgData = Data([0xB0, 0x01, 0x02])
    static let profileData = Data([0xF0, 0x01])
    static let logoData = Data([0x10, 0x60])
    static let photoData = Data([0x50, 0x40, 0x30])

    static func projectDocument(
        title: String = "Project Headline",
        logoID: String = UUID().uuidString,
        photoID: String = UUID().uuidString,
        shapeID: String = UUID().uuidString
    ) -> ThumbnailDocument {
        var layers = ThumbnailDocumentLayer.defaultLayers(hasText: true, hasProfile: true)
        layers.append(.imageLayer(id: logoID, imageData: logoData, name: "Logo", zIndex: 30))
        layers.append(.imageLayer(id: photoID, imageData: photoData, name: "Photo", zIndex: 31))
        layers.append(.shapeLayer(id: shapeID, zIndex: 32))
        return ThumbnailDocument(
            updatedAt: Date(timeIntervalSince1970: 10),
            editorMode: .premium,
            imageData: bgData,
            text: ThumbnailDocumentText(value: title),
            profile: ThumbnailDocumentProfile(imageData: profileData),
            layers: layers
        )
    }

    static func personal(
        id: String = UUID().uuidString,
        name: String = "Mine",
        category: ThumbnailTemplateCategory = .youtube,
        updatedAt: Date = Date(timeIntervalSince1970: 1_000),
        isFavorite: Bool = false
    ) -> ThumbnailTemplate {
        var template = ThumbnailTemplate.capture(
            from: projectDocument(),
            id: id,
            name: name,
            category: category,
            now: updatedAt
        )
        template.isFavorite = isFavorite
        return template
    }

    static func contentIDs(_ document: ThumbnailDocument) -> [String] {
        document.layers.filter { $0.content != nil }.map(\.id)
    }

    static func temporaryURL() -> (directory: URL, file: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FEATURE05-\(UUID().uuidString)", isDirectory: true)
        return (directory, directory.appendingPathComponent("personal-templates.json"))
    }
}

@MainActor
struct PersonalTemplateModelTests {
    typealias F = PersonalTemplateFixtures

    @Test func templateCodableRoundTripsWithNewFields() throws {
        var template = F.personal(isFavorite: true)
        template.deletedAt = Date(timeIntervalSince1970: 5_000)
        template.sourceTemplateID = "source"
        template.slots.backgroundImage = .placeholder

        let data = try JSONEncoder().encode(template)
        let decoded = try JSONDecoder().decode(ThumbnailTemplate.self, from: data)

        #expect(decoded == template)
        #expect(decoded.origin == .personal)
    }

    @Test func legacyTemplateJSONWithoutNewKeysStillDecodes() throws {
        let builtIn = try #require(ThumbnailTemplate.builtIns.first)
        let documentData = try JSONEncoder().encode(builtIn.document)
        let documentJSON = try #require(String(data: documentData, encoding: .utf8))
        let json = """
        {"version":1,"id":"legacy","name":"Legacy","category":"podcast","document":\(documentJSON)}
        """

        let decoded = try JSONDecoder().decode(ThumbnailTemplate.self, from: Data(json.utf8))

        #expect(decoded.id == "legacy")
        #expect(decoded.category == .podcast)
        #expect(decoded.origin == .builtIn)
        #expect(decoded.slots == .builtInDefaults)
        #expect(decoded.isFavorite == false)
        #expect(decoded.deletedAt == nil)
        #expect(decoded.version == ThumbnailTemplate.currentVersion)
    }

    @Test func unknownCategoryAndPolicyRawValuesFallBack() throws {
        let category = try JSONDecoder().decode([ThumbnailTemplateCategory].self, from: Data("[\"cooking\"]".utf8))
        #expect(category == [.youtube])

        let slots = try JSONDecoder().decode(
            ThumbnailTemplateSlots.self,
            from: Data("{\"backgroundImage\":\"hologram\"}".utf8)
        )
        #expect(slots.backgroundImage == .replaceFromProject)
        #expect(slots.title == ThumbnailTemplateSlots.builtInDefaults.title)
    }

    @Test func builtInTemplatesKeepBuiltInOriginAndSlots() {
        let builtIns = ThumbnailTemplate.builtIns
        #expect(builtIns.count == 5)
        #expect(builtIns.allSatisfy { $0.origin == .builtIn && !$0.isEditable })
        #expect(builtIns.allSatisfy { $0.slots == .builtInDefaults })
        #expect(builtIns == ThumbnailTemplate.builtIns)
    }

    @Test func builtInApplicationMatchesLegacyPath() {
        let project = F.projectDocument()
        let updatedAt = Date(timeIntervalSince1970: 42)
        for template in ThumbnailTemplate.builtIns {
            let application = template.application(over: project, mode: .composition, updatedAt: updatedAt)
            let legacy = template.makeDocument(preservingImagesFrom: project, updatedAt: updatedAt)
            #expect(application.document == legacy, "\(template.id) diverged from the legacy path")
            #expect(application.warnings.isEmpty)
        }
    }

    @Test func captureStripsProjectMediaButKeepsRetainedAssets() throws {
        let logoID = UUID().uuidString
        let photoID = UUID().uuidString
        let shapeID = UUID().uuidString
        let project = F.projectDocument(logoID: logoID, photoID: photoID, shapeID: shapeID)

        let template = ThumbnailTemplate.capture(
            from: project,
            id: "t1",
            name: "Brand",
            category: .gaming,
            retainedLayerIDs: [logoID],
            now: Date(timeIntervalSince1970: 100)
        )

        #expect(template.origin == .personal)
        #expect(template.document.imageData == nil)
        #expect(template.document.profile != nil)
        #expect(template.document.profile?.imageData == nil)
        let ids = F.contentIDs(template.document)
        #expect(ids == ["tpl-0", "tpl-1"])
        #expect(!ids.contains(logoID) && !ids.contains(photoID) && !ids.contains(shapeID))
        let logo = try #require(template.document.layers.record(id: "tpl-0"))
        guard case .image(let content) = logo.content else {
            Issue.record("Retained logo should stay an image layer")
            return
        }
        #expect(content.imageData == F.logoData)
        #expect(template.document.layers.allSatisfy { layer in
            if case .image(let content) = layer.content { return content.imageData != F.photoData }
            return true
        })
        #expect(template.slots.retainedLayerIDs == ["tpl-0"])
        #expect(template.slots.omittedImageLayerCount == 1)
        #expect(template.document.text.value == "Project Headline")
    }

    @Test func captureRetainsBackgroundOnlyWhenAsked() {
        let template = ThumbnailTemplate.capture(
            from: F.projectDocument(),
            name: "Keep BG",
            category: .vlog,
            backgroundPolicy: .retained,
            profilePolicy: .retained
        )
        #expect(template.document.imageData == F.bgData)
        #expect(template.document.profile?.imageData == F.profileData)
    }

    @Test func captureIsDeterministic() {
        let project = F.projectDocument()
        let now = Date(timeIntervalSince1970: 7)
        let first = ThumbnailTemplate.capture(from: project, id: "same", name: "A", category: .youtube, now: now)
        let second = ThumbnailTemplate.capture(from: project, id: "same", name: "A", category: .youtube, now: now)
        #expect(first == second)
    }

    @Test func instantiationCreatesFreshLayerIDs() {
        let logoID = UUID().uuidString
        let project = F.projectDocument(logoID: logoID)
        let template = ThumbnailTemplate.capture(
            from: project, name: "T", category: .youtube, retainedLayerIDs: [logoID]
        )
        var counter = 0
        let result = template.application(over: project, mode: .composition) {
            counter += 1
            return "fresh-\(counter)"
        }

        let resultIDs = F.contentIDs(result.document)
        #expect(resultIDs == ["fresh-1", "fresh-2"])
        #expect(result.newContentLayerIDs == resultIDs)
        #expect(counter == F.contentIDs(template.document).count)
        #expect(Set(resultIDs).isDisjoint(with: F.contentIDs(project)))
        #expect(Set(resultIDs).isDisjoint(with: F.contentIDs(template.document)))
        #expect(result.idMap["tpl-0"] == "fresh-1")
        for singleton in [ThumbnailDocumentLayer.backgroundID, ThumbnailDocumentLayer.textID, ThumbnailDocumentLayer.profileID] {
            #expect(result.document.layers.record(id: singleton) != nil, "\(singleton) must be kept")
        }
    }

    @Test func instantiationDoesNotLeakUnrelatedProjectLayers() {
        let source = F.projectDocument()
        let template = ThumbnailTemplate.capture(from: source, name: "Shape only", category: .youtube)
        // Template keeps only the shape (images were not retained).
        #expect(F.contentIDs(template.document).count == 1)

        let otherProject = F.projectDocument(title: "Other")
        let result = template.instantiate(over: otherProject)
        #expect(F.contentIDs(result.document).count == 1)
        #expect(result.document.layers.allSatisfy { layer in
            if case .image = layer.content { return false }
            return true
        })
    }

    @Test func slotPoliciesResolveAndReportMissingAssets() {
        let source = F.projectDocument()
        var template = ThumbnailTemplate.capture(from: source, name: "Slots", category: .youtube)

        // replaceFromProject pulls the project's background, profile and headline.
        let replaced = template.instantiate(over: F.projectDocument(title: "New Video"))
        #expect(replaced.document.imageData == F.bgData)
        #expect(replaced.document.profile?.imageData == F.profileData)
        #expect(replaced.document.text.value == "New Video")
        #expect(replaced.warnings.isEmpty)

        // Empty project headline falls back to the template sample text.
        let blankTitle = template.instantiate(over: F.projectDocument(title: "  "))
        #expect(blankTitle.document.text.value == "Project Headline")

        // Placeholder slots stay empty and are explained.
        template.slots.backgroundImage = .placeholder
        template.slots.profileImage = .placeholder
        template.slots.title = .retained
        let placeholder = template.instantiate(over: F.projectDocument(title: "Ignored"))
        #expect(placeholder.document.imageData == nil)
        #expect(placeholder.document.profile?.imageData == nil)
        #expect(placeholder.document.text.value == "Project Headline")
        #expect(placeholder.warnings.contains(.missingBackgroundImage))
        #expect(placeholder.warnings.contains(.missingProfileImage))
        #expect(placeholder.warnings.allSatisfy { !$0.message.isEmpty })
    }

    @Test func profileIsSplicedWhenTemplateHasNoProfileBlock() {
        var source = F.projectDocument()
        source.profile = nil
        source.layers = source.layers.reconciledForCurrentOverlays(hasText: true, hasProfile: false)
        let template = ThumbnailTemplate.capture(from: source, name: "No profile", category: .youtube)
        #expect(template.document.profile == nil)

        let result = template.instantiate(over: F.projectDocument())
        #expect(result.document.profile?.imageData == F.profileData)
        #expect(result.document.layers.record(id: ThumbnailDocumentLayer.profileID) != nil)
    }

    @Test func styleOnlyModeKeepsLayersAndImagesAndOnlyAdoptsStyle() throws {
        let builtIn = try #require(ThumbnailTemplate.builtIns.first { $0.id == "gaming-impact" })
        let project = F.projectDocument()

        let result = builtIn.application(over: project, mode: .styleOnly)

        #expect(result.document.layers == project.layers)
        #expect(result.document.imageData == project.imageData)
        #expect(result.document.profile == project.profile)
        #expect(result.document.text.value == project.text.value)
        #expect(result.document.text.transform == project.text.transform)
        #expect(result.document.canvas.aspectRatioRawValue == project.canvas.aspectRatioRawValue)
        #expect(result.document.canvas.backgroundColor == builtIn.document.canvas.backgroundColor)
        #expect(result.document.text.color == builtIn.document.text.color)
        #expect(result.document.text.selectedFontRawValue == builtIn.document.text.selectedFontRawValue)
        #expect(result.document.text.size == builtIn.document.text.size)
    }

    @Test func unsupportedFontIsReported() {
        var template = F.personal()
        template.document.text.selectedFontRawValue = "Nonexistent-Font"
        let result = template.instantiate(over: F.projectDocument())
        #expect(result.warnings.contains(.unsupportedFont(rawValue: "Nonexistent-Font")))
    }

    @Test func editingATemplateDoesNotMutateDocumentsAlreadyCreatedFromIt() throws {
        var library = PersonalTemplateLibrary()
        let template = try library.insert(F.personal(id: "edit-me"))
        let created = template.instantiate(over: F.projectDocument()).document
        let snapshot = created

        try library.update(id: "edit-me") { template in
            template.document.text.value = "Changed"
            template.document.canvas.backgroundColor = ThumbnailDocumentColor(red: 1, green: 0, blue: 0, alpha: 1)
        }

        #expect(created == snapshot)
        #expect(library.template(id: "edit-me")?.document.text.value == "Changed")
    }
}

@MainActor
struct PersonalTemplateLibraryTests {
    typealias F = PersonalTemplateFixtures
    typealias LibraryError = PersonalTemplateLibrary.LibraryError

    @Test func libraryEnforcesCapAndUniquifiesNames() throws {
        var library = PersonalTemplateLibrary()
        let first = try library.insert(F.personal(name: "Name"))
        let second = try library.insert(F.personal(name: "name"))
        let third = try library.insert(F.personal(name: "Name"))
        #expect(first.name == "Name")
        #expect(second.name == "name 2")
        #expect(third.name == "Name 3")

        for index in 3..<PersonalTemplateLibrary.maximumActiveTemplates {
            try library.insert(F.personal(name: "Bulk \(index)"))
        }
        #expect(library.active.count == PersonalTemplateLibrary.maximumActiveTemplates)
        #expect(throws: LibraryError.libraryFull(limit: 60)) {
            try library.insert(F.personal(name: "One too many"))
        }
        #expect(throws: LibraryError.emptyName) {
            try library.rename(id: first.id, to: "   ")
        }
    }

    @Test func libraryRejectsBuiltInOriginOnInsertAndUpdate() throws {
        var library = PersonalTemplateLibrary()
        let builtIn = try #require(ThumbnailTemplate.builtIns.first)
        #expect(throws: LibraryError.builtInNotEditable(builtIn.id)) {
            try library.insert(builtIn)
        }
        library.templates.append(builtIn)
        #expect(throws: LibraryError.builtInNotEditable(builtIn.id)) {
            try library.rename(id: builtIn.id, to: "Hacked")
        }
        #expect(throws: LibraryError.notFound("missing")) {
            try library.setFavorite(true, id: "missing")
        }
    }

    @Test func duplicateProducesIndependentCopy() throws {
        var library = PersonalTemplateLibrary()
        let original = try library.insert(F.personal(id: "orig", name: "Launch", isFavorite: true))
        let copy = try library.duplicate(id: "orig", newID: "copy", now: Date(timeIntervalSince1970: 2_000))

        #expect(copy.id == "copy")
        #expect(copy.name == "Launch Copy")
        #expect(copy.sourceTemplateID == "orig")
        #expect(copy.isFavorite == false)

        try library.update(id: "copy") { $0.document.text.value = "Only the copy" }
        #expect(library.template(id: "orig")?.document == original.document)
    }

    @Test func softDeleteIsRecoverable() throws {
        var library = PersonalTemplateLibrary()
        try library.insert(F.personal(id: "a", name: "A"))
        try library.insert(F.personal(id: "b", name: "B"))
        let deletedAt = Date(timeIntervalSince1970: 10_000)

        try library.softDelete(id: "a", now: deletedAt)
        #expect(library.active.map(\.id) == ["b"])
        #expect(library.trashed.map(\.id) == ["a"])
        #expect(library.template(id: "a")?.document.layers.isEmpty == false)

        #expect(throws: LibraryError.notInTrash("b")) { try library.purge(id: "b") }

        try library.restore(id: "a")
        #expect(Set(library.active.map(\.id)) == ["a", "b"])

        try library.softDelete(id: "a", now: deletedAt)
        try library.softDelete(id: "b", now: deletedAt.addingTimeInterval(PersonalTemplateLibrary.trashRetention - 10))
        let expired = library.purgeExpired(now: deletedAt.addingTimeInterval(PersonalTemplateLibrary.trashRetention + 1))
        #expect(expired == ["a"])
        #expect(library.trashed.map(\.id) == ["b"])

        try library.purge(id: "b")
        #expect(library.templates.isEmpty)
    }

    @Test func restoreRenamesWhenTheNameWasTakenMeanwhile() throws {
        var library = PersonalTemplateLibrary()
        try library.insert(F.personal(id: "a", name: "Launch"))
        try library.softDelete(id: "a")
        try library.insert(F.personal(id: "b", name: "Launch"))
        try library.restore(id: "a")
        #expect(library.template(id: "a")?.name == "Launch 2")
    }

    @Test func activeOrderingPutsFavoritesFirst() throws {
        var library = PersonalTemplateLibrary()
        try library.insert(F.personal(id: "old", name: "Old", updatedAt: Date(timeIntervalSince1970: 1)))
        try library.insert(F.personal(id: "new", name: "New", updatedAt: Date(timeIntervalSince1970: 3)))
        try library.insert(F.personal(id: "fav", name: "Fav", updatedAt: Date(timeIntervalSince1970: 0), isFavorite: true))

        #expect(library.active.map(\.id) == ["fav", "new", "old"])
        #expect(library.favorites.map(\.id) == ["fav"])
        #expect(library.active(in: .youtube).count == 3)
    }
}

@MainActor
struct PersonalTemplateStoreTests {
    typealias F = PersonalTemplateFixtures

    @Test func storeSavesAndReloadsAcrossInstances() throws {
        let (directory, url) = F.temporaryURL()
        defer { try? FileManager.default.removeItem(at: directory) }

        var library = PersonalTemplateLibrary()
        try library.insert(F.personal(id: "one", name: "One", isFavorite: true), now: Date(timeIntervalSince1970: 100))
        try library.insert(F.personal(id: "two", name: "Two"), now: Date(timeIntervalSince1970: 100))
        try library.insert(F.personal(id: "three", name: "Three"), now: Date(timeIntervalSince1970: 100))
        let now = Date()
        try library.softDelete(id: "three", now: Date(timeIntervalSince1970: floor(now.timeIntervalSince1970)))

        try PersonalTemplateStore(fileURL: url).save(library)
        let reloaded = try PersonalTemplateStore(fileURL: url).load(now: now)

        #expect(reloaded == library)
        #expect(reloaded.favorites.map(\.id) == ["one"])
        #expect(reloaded.trashed.map(\.id) == ["three"])

        try PersonalTemplateStore(fileURL: url).delete()
        #expect(try PersonalTemplateStore(fileURL: url).load().templates.isEmpty)
    }

    @Test func storeCreatesIntermediateDirectoriesAndSweepsExpiredTrash() throws {
        let (directory, _) = F.temporaryURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("a/b/c/personal-templates.json")

        var library = PersonalTemplateLibrary()
        try library.insert(F.personal(id: "gone", name: "Gone"))
        try library.softDelete(id: "gone", now: Date(timeIntervalSince1970: 0))
        try PersonalTemplateStore(fileURL: url).save(library)
        #expect(FileManager.default.fileExists(atPath: url.path))

        let loaded = try PersonalTemplateStore(fileURL: url).load(now: Date(timeIntervalSince1970: 40 * 24 * 3600))
        #expect(loaded.templates.isEmpty)
        let resaved = try PersonalTemplateStore(fileURL: url).load(now: Date(timeIntervalSince1970: 40 * 24 * 3600))
        #expect(resaved.templates.isEmpty)
    }

    @Test func storeRecoversFromCorruptFile() throws {
        let (directory, url) = F.temporaryURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)

        let result = PersonalTemplateStore(fileURL: url).loadRecoveringFromCorruption()

        #expect(result.library.templates.isEmpty)
        let quarantined = try #require(result.quarantined)
        #expect(FileManager.default.fileExists(atPath: quarantined.path))
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try Data(contentsOf: quarantined) == Data("{ not json".utf8))
    }

    @Test func storeRejectsOversizedRetainedPayloadWithoutWriting() throws {
        let (directory, url) = F.temporaryURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PersonalTemplateStore(fileURL: url)

        var library = PersonalTemplateLibrary()
        try library.insert(F.personal(id: "ok", name: "OK"))
        try store.save(library)
        let before = try Data(contentsOf: url)

        var heavy = F.personal(id: "heavy", name: "Heavy")
        heavy.slots.backgroundImage = .retained
        heavy.document.imageData = Data(repeating: 7, count: PersonalTemplateStore.maximumTemplateBytes)
        try library.insert(heavy)

        #expect(throws: PersonalTemplateLibrary.LibraryError.self) {
            try store.save(library)
        }
        #expect(try Data(contentsOf: url) == before)
    }
}
