//
//  BrandKitLibraryTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-08: brand kit library model, persistence and legacy migration.
//

import Foundation
import Testing
@testable import ThumbnailMaker

@MainActor
struct BrandKitLibraryTests {

    // MARK: Fixtures

    static func color(_ r: Double, _ g: Double, _ b: Double) -> ThumbnailDocumentColor {
        ThumbnailDocumentColor(red: r, green: g, blue: b, alpha: 1)
    }

    static func kit(
        id: String,
        name: String,
        text: ThumbnailDocumentColor,
        background: ThumbnailDocumentColor,
        accent: ThumbnailDocumentColor? = nil,
        font: CustomFont,
        styles: [ThumbnailLayerStyle] = []
    ) -> BrandKit {
        var palette = [
            BrandColor(id: "\(id)-text", name: "Text", color: text),
            BrandColor(id: "\(id)-background", name: "Background", color: background)
        ]
        if let accent {
            palette.append(BrandColor(id: "\(id)-accent", name: "Accent", color: accent))
        }
        return BrandKit(
            id: id,
            name: name,
            palette: palette,
            primaryFontRawValue: font.rawValue,
            secondaryFontRawValue: nil,
            logoImageData: nil,
            styles: styles,
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    static func threeKits() -> [BrandKit] {
        [
            kit(id: "kit-a", name: "Kit A", text: color(1, 0, 0), background: color(0, 0, 0), font: .montserrat),
            kit(id: "kit-b", name: "Kit B", text: color(0, 1, 0), background: color(0.1, 0.1, 0.1), accent: color(0, 0, 1), font: .roboto),
            kit(id: "kit-c", name: "Kit C", text: color(0, 0, 1), background: color(1, 1, 1), font: .oswald)
        ]
    }

    static func temporaryStore() -> (store: BrandKitStore, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = BrandKitStore(
            fileURL: directory.appendingPathComponent("brand-kit.json"),
            libraryFileURL: directory.appendingPathComponent("brand-kits.json")
        )
        return (store, directory)
    }

    // MARK: Persistence

    @Test func threeIndependentKitsSurviveRestart() throws {
        let (store, directory) = Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        var library = BrandKitLibrary.empty
        for kit in Self.threeKits() {
            let added = library.upsert(kit, activate: false)
            #expect(added)
        }
        library.setActive(id: "kit-b")
        try store.saveLibrary(library)

        let restarted = BrandKitStore(fileURL: store.fileURL, libraryFileURL: store.libraryFileURL)
        let restored = try restarted.loadLibrary()

        #expect(restored.kits.count == 3)
        #expect(restored.kits.map(\.id) == ["kit-a", "kit-b", "kit-c"])
        #expect(restored.activeKitID == "kit-b")
        #expect(restored.activeKit?.name == "Kit B")
        for (original, loaded) in zip(Self.threeKits(), restored.kits) {
            #expect(loaded.palette == original.palette)
            #expect(loaded.primaryFontRawValue == original.primaryFontRawValue)
            #expect(loaded.name == original.name)
        }
        #expect(Set(restored.kits.map { $0.palette[0].color.red * 4 + $0.palette[0].color.green * 2 }).count == 3)
    }

    @Test func libraryMigratesLegacySingleKitFileWithoutRewritingIt() throws {
        let (store, directory) = Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let legacy = Self.threeKits()[0]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let legacyData = try encoder.encode(legacy)
        try legacyData.write(to: store.fileURL)

        let migrated = try store.loadLibrary()
        #expect(migrated.kits.map(\.id) == [legacy.id])
        #expect(migrated.activeKitID == legacy.id)
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path))
        #expect(!FileManager.default.fileExists(atPath: store.libraryFileURL.path))
        #expect(try Data(contentsOf: store.fileURL) == legacyData)

        var library = migrated
        library.upsert(Self.threeKits()[1], activate: true)
        try store.saveLibrary(library)

        let reloaded = try store.loadLibrary()
        #expect(reloaded.kits.map(\.id) == ["kit-a", "kit-b"])
        #expect(reloaded.activeKitID == "kit-b")
    }

    @Test func legacySaveAndLoadShimsStillWork() throws {
        let (store, directory) = Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(try store.load() == nil)
        let kit = Self.threeKits()[2]
        try store.save(kit)
        #expect(try store.load()?.id == kit.id)
        #expect(try store.loadLibrary().activeKitID == kit.id)

        try store.delete()
        #expect(try store.load() == nil)
        #expect(try store.loadLibrary().kits.isEmpty)
    }

    @Test func corruptLibraryFileThrowsInsteadOfSilentlyEmptying() throws {
        let (store, directory) = Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: store.libraryFileURL)
        #expect(throws: (any Error).self) { try store.loadLibrary() }
    }

    @Test func viewModelSurfacesCorruptLibraryOnLaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: directory.appendingPathComponent("brand-kits.json"))

        let viewModel = SimpleMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple-maker-draft.json")),
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        )
        #expect(viewModel.brandKitLibrary.kits.isEmpty)
        #expect(viewModel.saveError?.contains("brand kits") == true)
    }

    // MARK: Library operations

    @Test func duplicateProducesIndependentCopy() throws {
        let styles = [
            ThumbnailLayerStyle(id: "s1", name: "Headline", target: .text, textColor: Self.color(1, 1, 0)),
            ThumbnailLayerStyle(id: "s2", name: "Badge", target: .shape, fillColor: Self.color(1, 0, 1))
        ]
        var library = BrandKitLibrary.empty
        library.upsert(Self.kit(id: "x", name: "X", text: Self.color(1, 1, 1), background: Self.color(0, 0, 0), font: .lato, styles: styles))

        let duplicated = library.duplicate(id: "x", newID: "x2")
        var copy = try #require(duplicated)
        #expect(copy.id == "x2")
        #expect(copy.name == "X Copy")
        #expect(library.activeKitID == "x2")
        #expect(Set(copy.styles.map(\.id)).isDisjoint(with: ["s1", "s2"]))
        #expect(copy.styles.map(\.name) == ["Headline", "Badge"])

        copy.palette[0] = BrandColor(id: "changed", name: "Text", color: Self.color(0.5, 0.5, 0.5))
        library.upsert(copy)
        #expect(library.kit(id: "x")?.palette[0].color == Self.color(1, 1, 1))

        let secondCopy = library.duplicate(id: "x", newID: "x3")
        let second = try #require(secondCopy)
        #expect(second.name == "X Copy 2")
    }

    @Test func renameTrimsAndDeDuplicates() {
        var library = BrandKitLibrary.empty
        for kit in Self.threeKits() { library.upsert(kit) }

        library.rename(id: "kit-a", to: "  Gaming  ")
        #expect(library.kit(id: "kit-a")?.name == "Gaming")

        library.rename(id: "kit-c", to: "Gaming")
        #expect(library.kit(id: "kit-c")?.name == "Gaming 2")
    }

    @Test func renameToEmptyKeepsExistingName() {
        var library = BrandKitLibrary.empty
        library.upsert(Self.threeKits()[0])
        library.rename(id: "kit-a", to: "   ")
        #expect(library.kit(id: "kit-a")?.name == "Kit A")
    }

    @Test func removingActiveKitReassignsActiveAndRestoreUndoesIt() throws {
        var library = BrandKitLibrary.empty
        for kit in Self.threeKits() { library.upsert(kit, activate: false) }
        library.setActive(id: "kit-b")

        let removal = library.remove(id: "kit-b")
        let removed = try #require(removal)
        #expect(removed.kit.id == "kit-b")
        #expect(removed.index == 1)
        #expect(library.kits.count == 2)
        let newActive = try #require(library.activeKitID)
        #expect(library.kit(id: newActive) != nil)

        library.restore(removed.kit, at: removed.index)
        #expect(library.kits.map(\.id) == ["kit-a", "kit-b", "kit-c"])
        #expect(library.activeKitID == "kit-b")

        library.remove(id: "kit-a")
        library.remove(id: "kit-b")
        library.remove(id: "kit-c")
        #expect(library.kits.isEmpty)
        #expect(library.activeKitID == nil)
    }

    @Test func libraryRefusesToExceedMaximumKitCount() {
        var library = BrandKitLibrary.empty
        for index in 0..<BrandKitLibrary.maximumKitCount {
            let added = library.upsert(BrandKit.defaultCreatorKit(id: "k\(index)"))
            #expect(added)
        }
        #expect(library.isFull)
        let overflowAdded = library.upsert(BrandKit.defaultCreatorKit(id: "overflow"))
        #expect(!overflowAdded)
        let overflowCopy = library.duplicate(id: "k0")
        #expect(overflowCopy == nil)
        #expect(library.kits.count == BrandKitLibrary.maximumKitCount)
        // Replacing an existing kit is still allowed when full.
        var edited = BrandKit.defaultCreatorKit(id: "k0")
        edited.name = "Edited"
        let replaced = library.upsert(edited)
        #expect(replaced)
        #expect(library.kit(id: "k0")?.name == "Edited")
    }

    @Test func brandKitCodableBackCompatAndStylesRoundTrip() throws {
        let legacyJSON = Data("""
        {
          "version": 1,
          "id": "legacy",
          "name": "Legacy",
          "palette": [],
          "primaryFontRawValue": "Montserrat-Regular"
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(BrandKit.self, from: legacyJSON)
        #expect(decoded.styles.isEmpty)
        #expect(decoded.version == BrandKit.currentVersion)

        let styled = Self.kit(
            id: "k",
            name: "K",
            text: Self.color(1, 1, 1),
            background: Self.color(0, 0, 0),
            font: .poppins,
            styles: [ThumbnailLayerStyle(id: "s", name: "S", target: .shape, fillColor: Self.color(1, 0, 0), strokeWidth: 0.02, updatedAt: Date(timeIntervalSince1970: 1_000))]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let roundTripped = try decoder.decode(BrandKit.self, from: encoder.encode(styled))
        #expect(roundTripped == styled)
    }

    // MARK: View model library commands

    @Test func viewModelLibraryCommandsPersistAcrossRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let draftStore = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("premium-maker-draft.json"))
        let brandStore = BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))

        let viewModel = PremiumMakerViewModel(draftStore: draftStore, brandKitStore: brandStore)
        let first = try #require(viewModel.createBrandKit(named: "Gaming"))
        let second = try #require(viewModel.createBrandKit(named: "Cooking"))
        let copy = try #require(viewModel.duplicateBrandKit(id: first.id))
        #expect(viewModel.renameBrandKit(id: copy.id, to: "Gaming Shorts"))
        #expect(viewModel.selectBrandKit(id: second.id))

        let removed = try #require(viewModel.deleteBrandKit(id: first.id))
        #expect(viewModel.brandKitLibrary.kits.count == 2)
        #expect(viewModel.restoreBrandKit(removed.kit, at: removed.index))

        let restarted = PremiumMakerViewModel(draftStore: draftStore, brandKitStore: brandStore)
        #expect(restarted.brandKitLibrary.kits.map(\.name) == ["Gaming", "Cooking", "Gaming Shorts"])
        #expect(restarted.brandKit?.id == first.id) // restore re-activates the restored kit
    }
}
