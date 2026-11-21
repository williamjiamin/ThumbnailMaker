//
//  ThumbnailEncodedImageCache.swift
//  ThumbnailMaker
//
//  APP-09: every `configuration.document` used to re-encode the full photo as
//  PNG, so a single text edit paid several multi-megabyte encodes on the main
//  actor and every undo snapshot held its own copy of the bytes.
//
//  This cache attaches the encoded PNG to the UIImage it came from (an
//  associated object, so the entry lives exactly as long as the image). An
//  unchanged photo is encoded once; every later document, history snapshot,
//  baseline and variant shares that single buffer. Images decoded from a
//  document's PNG are paired with the bytes they came from, so a
//  document -> configuration -> document round trip does not re-encode either.
//
//  The encoded bytes are exactly what `ThumbnailDocument` produced before
//  (PNG, orientation normalized), so the on-disk format is unchanged.
//

import CryptoKit
import Foundation
import ObjectiveC
import UIKit

final class ThumbnailEncodedImageCache: @unchecked Sendable {
    static let shared = ThumbnailEncodedImageCache()

    final class Entry: @unchecked Sendable {
        let data: Data
        /// Set only for images this cache decoded itself, which are plain
        /// `.up` PNG decodes and can therefore be handed out again for the same
        /// bytes without changing what callers observed before.
        weak var decodedImage: UIImage?
        private let lock = NSLock()
        private var memoizedDigest: String?

        init(data: Data) {
            self.data = data
        }

        func digest(_ compute: () -> String) -> String {
            lock.lock()
            defer { lock.unlock() }
            if let memoizedDigest { return memoizedDigest }
            let value = compute()
            memoizedDigest = value
            return value
        }
    }

    private struct WeakEntry {
        weak var entry: Entry?
    }

    private static let associationKey = UnsafeRawPointer(UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1))
    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    private let lock = NSLock()
    private var index: [ThumbnailPayloadBufferKey: WeakEntry] = [:]
    private var memoryWarningObserver: NSObjectProtocol?

    init() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.pruneIndex()
        }
    }

    deinit {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }

    // MARK: Encoding

    /// The document PNG for `image`. Encodes on the first call for this image
    /// instance and returns the same buffer afterwards.
    func encodedPNG(for image: UIImage) -> Data? {
        if let entry = entry(for: image) {
            return entry.data
        }
        let encoded = ThumbnailPerformanceProbe.measure(.imageEncode) {
            Self.encodeDocumentPNG(image)
        }
        guard let encoded else { return nil }
        return register(image, encoded: encoded).data
    }

    /// Pairs `image` with bytes that already represent it as a document PNG.
    @discardableResult
    func register(_ image: UIImage, encoded data: Data) -> Entry {
        let entry = Entry(data: data)
        objc_setAssociatedObject(image, Self.associationKey, entry, .OBJC_ASSOCIATION_RETAIN)
        if let key = ThumbnailPayloadBufferKey(data) {
            lock.lock()
            index[key] = WeakEntry(entry: entry)
            if index.count > 256 {
                index = index.filter { $0.value.entry != nil }
            }
            lock.unlock()
        }
        return entry
    }

    func hasEncodedPNG(for image: UIImage) -> Bool {
        entry(for: image) != nil
    }

    // MARK: Decoding

    /// `UIImage(data:)` that remembers where the image came from. For a PNG
    /// that decodes upright, re-encoding that image yields `data` itself, and
    /// decoding the same buffer again returns the same image instance.
    func image(decoding data: Data) -> UIImage? {
        if let entry = liveEntry(sharing: data), let image = entry.decodedImage {
            return image
        }
        guard let image = UIImage(data: data) else { return nil }
        if image.imageOrientation == .up, Self.isPNG(data) {
            let entry = register(image, encoded: data)
            entry.decodedImage = image
        }
        return image
    }

    // MARK: Digests

    /// SHA-256 hex of `data`, memoized for buffers owned by a live entry.
    func digest(for data: Data) -> String {
        if let entry = liveEntry(sharing: data) {
            return entry.digest { Self.sha256Hex(data) }
        }
        return Self.sha256Hex(data)
    }

    // MARK: Maintenance

    /// Forgets the buffer index (entries stay attached to their images).
    func removeAll() {
        lock.lock()
        index.removeAll()
        lock.unlock()
    }

    private func pruneIndex() {
        lock.lock()
        index = index.filter { $0.value.entry != nil }
        lock.unlock()
    }

    private func entry(for image: UIImage) -> Entry? {
        objc_getAssociatedObject(image, Self.associationKey) as? Entry
    }

    private func liveEntry(sharing data: Data) -> Entry? {
        guard let key = ThumbnailPayloadBufferKey(data) else { return nil }
        lock.lock()
        let entry = index[key]?.entry
        lock.unlock()
        guard let entry, ThumbnailDocumentPayloads.sharesBuffer(entry.data, data) else { return nil }
        return entry
    }

    // MARK: Primitives

    static func sha256Hex(_ data: Data) -> String {
        ThumbnailPerformanceProbe.measure(.assetDigest) {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }

    static func isPNG(_ data: Data) -> Bool {
        data.count >= pngSignature.count && data.prefix(pngSignature.count).elementsEqual(pngSignature)
    }

    /// The historical document encoding: lossless PNG, orientation normalized
    /// so rotated imports keep their displayed composition.
    static func encodeDocumentPNG(_ image: UIImage) -> Data? {
        if image.imageOrientation != .up {
            let format = UIGraphicsImageRendererFormat()
            format.scale = image.scale
            format.opaque = false
            return UIGraphicsImageRenderer(size: image.size, format: format)
                .image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
                .pngData()
        }
        return image.pngData()
    }
}
