import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct HistoryItem: Identifiable {
    let id: UUID
    let date: Date
    let pixelSize: CGSize?
    private let storage: HistoryImageStorage

    @MainActor
    init(image: NSImage, date: Date, compressInBackground: Bool = false) {
        let id = UUID()
        self.id = id
        self.date = date
        let storage = HistoryImageStorage(id: id, image: image, compressInBackground: compressInBackground)
        self.storage = storage
        self.pixelSize = storage.pixelSize
    }

    @MainActor
    var image: NSImage {
        storage.resolvedImage()
    }

    @MainActor
    var thumbnail: NSImage {
        storage.resolvedThumbnail()
    }

    @MainActor
    func releaseResources() {
        storage.releaseResources()
    }
}

@MainActor
private final class HistoryImageStorage {
    private static let decodedCache: NSCache<NSUUID, NSImage> = {
        let cache = NSCache<NSUUID, NSImage>()
        cache.countLimit = 4
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()

    private static let compressionPixelThreshold = 256 * 256
    private static let maxThumbnailPixelDimension: CGFloat = 380

    private let id: UUID
    private let pointSize: NSSize
    let pixelSize: CGSize?
    private let pixelCost: Int

    private var liveImage: NSImage?
    private var compressedPNGData: Data?
    private var thumbnailImage: NSImage?
    private var compressionTask: Task<Void, Never>?

    init(id: UUID, image: NSImage, compressInBackground: Bool) {
        self.id = id
        self.pointSize = image.size
        self.liveImage = image

        let cgImage = image.cgImageRepresentation
        if let cgImage {
            self.pixelSize = CGSize(width: cgImage.width, height: cgImage.height)
            self.pixelCost = cgImage.width * cgImage.height * 4
        } else {
            self.pixelSize = nil
            self.pixelCost = 0
        }

        if compressInBackground,
           let cgImage,
           cgImage.width * cgImage.height > Self.compressionPixelThreshold {
            startBackgroundCompression(cgImage: cgImage)
        }
    }

    func resolvedImage() -> NSImage {
        if let liveImage {
            return liveImage
        }
        let key = id as NSUUID
        if let cached = Self.decodedCache.object(forKey: key) {
            return cached
        }
        if let compressedPNGData,
           let source = CGImageSourceCreateWithData(compressedPNGData as CFData, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            let decoded = NSImage(cgImage: cgImage, size: pointSize)
            Self.decodedCache.setObject(decoded, forKey: key, cost: pixelCost)
            return decoded
        }
        if let thumbnailImage {
            return thumbnailImage
        }
        return NSImage(size: pointSize)
    }

    func resolvedThumbnail() -> NSImage {
        if let thumbnailImage {
            return thumbnailImage
        }
        return resolvedImage()
    }

    func releaseResources() {
        compressionTask?.cancel()
        compressionTask = nil
        Self.decodedCache.removeObject(forKey: id as NSUUID)
    }

    private func startBackgroundCompression(cgImage: CGImage) {
        let maxThumb = Self.maxThumbnailPixelDimension
        compressionTask = Task.detached(priority: .utility) { [weak self] in
            guard !Task.isCancelled else { return }
            let thumbCG = Self.makeThumbnailCGImage(from: cgImage, maxPixelDimension: maxThumb)
            guard !Task.isCancelled else { return }
            let pngData = Self.encodePNG(cgImage)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                if let thumbCG {
                    let thumbSize = NSSize(width: CGFloat(thumbCG.width) / 2, height: CGFloat(thumbCG.height) / 2)
                    self.thumbnailImage = NSImage(cgImage: thumbCG, size: thumbSize)
                }
                if let pngData {
                    self.compressedPNGData = pngData
                    if let currentImage = self.liveImage {
                        Self.decodedCache.setObject(currentImage, forKey: self.id as NSUUID, cost: self.pixelCost)
                        self.liveImage = nil
                    }
                }
                self.compressionTask = nil
            }
        }
    }

    nonisolated private static func makeThumbnailCGImage(from cgImage: CGImage, maxPixelDimension: CGFloat) -> CGImage? {
        let srcWidth = CGFloat(cgImage.width)
        let srcHeight = CGFloat(cgImage.height)
        let longestSide = max(srcWidth, srcHeight)
        guard longestSide > maxPixelDimension else { return cgImage }

        let scale = maxPixelDimension / longestSide
        let dstWidth = max(1, Int((srcWidth * scale).rounded()))
        let dstHeight = max(1, Int((srcHeight * scale).rounded()))
        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: dstWidth,
            height: dstHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace.model == .rgb ? colorSpace : CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: dstWidth, height: dstHeight))
        return context.makeImage()
    }

    nonisolated private static func encodePNG(_ cgImage: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }
}

@MainActor
final class ScreenshotHistory: ObservableObject {
    static let shared = ScreenshotHistory()

    @Published private(set) var items: [HistoryItem] = []

    private let maxCount = 50

    private init() {}

    func add(_ image: NSImage) {
        items.insert(HistoryItem(image: image, date: Date(), compressInBackground: true), at: 0)
        if items.count > maxCount {
            let removed = items.removeLast()
            removed.releaseResources()
        }
    }

    func remove(_ item: HistoryItem) {
        for existing in items where existing.id == item.id {
            existing.releaseResources()
        }
        items.removeAll { $0.id == item.id }
    }

    func removeAll(where predicate: (HistoryItem) -> Bool) {
        for existing in items where predicate(existing) {
            existing.releaseResources()
        }
        items.removeAll(where: predicate)
    }

    func clear() {
        for existing in items {
            existing.releaseResources()
        }
        items.removeAll()
    }
}
