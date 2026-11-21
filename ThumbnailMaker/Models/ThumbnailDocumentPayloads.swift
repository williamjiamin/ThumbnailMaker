//
//  ThumbnailDocumentPayloads.swift
//  ThumbnailMaker
//
//  APP-09: buffer-identity helpers for the image payloads a document carries
//  (background photo, premium profile photo, image layers).
//
//  Foundation `Data` shares one heap buffer between copies until one is
//  mutated. When two payloads point at the same buffer with the same length
//  they are byte-identical, so equality can be answered without comparing
//  megabytes, and memory accounting can count that buffer once. When the
//  buffers differ we always fall back to a real byte comparison, so this only
//  ever changes speed, never results.
//

import Foundation

/// Identity of a heap-backed payload buffer. Only payloads of at least
/// `minimumByteCount` bytes get a key: smaller `Data` values may be stored
/// inline, where `withUnsafeBytes` hands out a temporary address.
struct ThumbnailPayloadBufferKey: Hashable {
    static let minimumByteCount = 64

    let address: UInt
    let count: Int

    init?(_ data: Data) {
        let count = data.count
        guard count >= Self.minimumByteCount else { return nil }
        let address = data.withUnsafeBytes { buffer in
            buffer.baseAddress.map { UInt(bitPattern: $0) }
        }
        guard let address else { return nil }
        self.address = address
        self.count = count
    }
}

enum ThumbnailDocumentPayloads {
    /// True only when both values are views of the same heap buffer.
    static func sharesBuffer(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count, lhs.count >= ThumbnailPayloadBufferKey.minimumByteCount else {
            return false
        }
        // Nested so neither temporary pointer can be reused by the other.
        return lhs.withUnsafeBytes { left in
            rhs.withUnsafeBytes { right in
                left.baseAddress != nil && left.baseAddress == right.baseAddress
            }
        }
    }

    /// Every image payload in the document.
    static func payloads(of document: ThumbnailDocument) -> [Data] {
        var result: [Data] = []
        if let imageData = document.imageData {
            result.append(imageData)
        }
        if let profileData = document.profile?.imageData {
            result.append(profileData)
        }
        for layer in document.layers {
            if case .image(let content) = layer.content, !content.imageData.isEmpty {
                result.append(content.imageData)
            }
        }
        return result
    }

    /// Same result as `lhs == rhs`, but payloads that share a buffer are not
    /// byte-compared.
    static func isEquivalent(_ lhs: ThumbnailDocument, _ rhs: ThumbnailDocument) -> Bool {
        var left = lhs
        var right = rhs

        if let leftData = left.imageData, let rightData = right.imageData,
           sharesBuffer(leftData, rightData) {
            left.imageData = nil
            right.imageData = nil
        }

        if let leftData = left.profile?.imageData, let rightData = right.profile?.imageData,
           sharesBuffer(leftData, rightData) {
            left.profile?.imageData = nil
            right.profile?.imageData = nil
        }

        if left.layers.count == right.layers.count {
            for index in left.layers.indices where left.layers[index].id == right.layers[index].id {
                guard case .image(var leftContent) = left.layers[index].content,
                      case .image(var rightContent) = right.layers[index].content,
                      sharesBuffer(leftContent.imageData, rightContent.imageData) else {
                    continue
                }
                leftContent.imageData = Data()
                rightContent.imageData = Data()
                left.layers[index].content = .image(leftContent)
                right.layers[index].content = .image(rightContent)
            }
        }

        return left == right
    }

    /// Bytes of distinct payload buffers across `documents`; a photo shared by
    /// many snapshots counts once. Small inline payloads are counted per copy.
    static func uniqueByteCount<S: Sequence>(of documents: S) -> Int where S.Element == ThumbnailDocument {
        var seen = Set<ThumbnailPayloadBufferKey>()
        var total = 0
        for document in documents {
            for payload in payloads(of: document) {
                if let key = ThumbnailPayloadBufferKey(payload) {
                    if seen.insert(key).inserted {
                        total += payload.count
                    }
                } else {
                    total += payload.count
                }
            }
        }
        return total
    }
}
