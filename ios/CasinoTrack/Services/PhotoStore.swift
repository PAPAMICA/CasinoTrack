import Foundation
import UIKit
import SwiftData

enum PhotoStore {
    private static var root: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func url(for relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }

    static func exists(_ relativePath: String?) -> Bool {
        guard let relativePath, !relativePath.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: url(for: relativePath).path)
    }

    static func loadImage(relativePath: String?) -> UIImage? {
        guard let relativePath, exists(relativePath) else { return nil }
        return UIImage(contentsOfFile: url(for: relativePath).path)
    }

    static func image(data: Data?, path: String?) -> UIImage? {
        if let data, let img = UIImage(data: data) { return img }
        return loadImage(relativePath: path)
    }

    static func loadData(relativePath: String?) -> Data? {
        guard let relativePath, exists(relativePath) else { return nil }
        return try? Data(contentsOf: url(for: relativePath))
    }

    /// Compresse et retourne JPEG pour stockage SwiftData / iCloud
    static func jpegData(from image: UIImage, quality: CGFloat = 0.72, maxSide: CGFloat = 1600) -> Data? {
        let scaled = image.scaledToMaxSide(maxSide)
        return scaled.jpegData(compressionQuality: quality)
    }

    static func saveJPEG(_ data: Data, folder: String = "bonuses") throws -> String {
        let name = UUID().uuidString + ".jpg"
        let relative = "\(folder)/\(name)"
        let dest = url(for: relative)
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: dest, options: .atomic)
        return relative
    }

    static func copyFromBundleIfNeeded(relativePath: String) {
        let dest = url(for: relativePath)
        if FileManager.default.fileExists(atPath: dest.path) { return }
        let candidates: [URL] = [
            Bundle.main.resourceURL?.appendingPathComponent("SeedData/photos/\(relativePath)"),
            Bundle.main.url(
                forResource: (relativePath as NSString).deletingPathExtension,
                withExtension: (relativePath as NSString).pathExtension,
                subdirectory: "SeedData/photos"
            ),
            Bundle.main.url(forResource: "SeedData", withExtension: nil)?
                .appendingPathComponent("photos")
                .appendingPathComponent(relativePath),
        ].compactMap { $0 }
        guard let src = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { return }
        try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: src, to: dest)
    }

    static func dataFromBundleOrDisk(relativePath: String) -> Data? {
        copyFromBundleIfNeeded(relativePath: relativePath)
        if let data = loadData(relativePath: relativePath) { return data }
        let bundleCandidates: [URL] = [
            Bundle.main.resourceURL?.appendingPathComponent("SeedData/photos/\(relativePath)"),
            Bundle.main.url(forResource: "SeedData", withExtension: nil)?
                .appendingPathComponent("photos")
                .appendingPathComponent(relativePath),
        ].compactMap { $0 }
        for src in bundleCandidates where FileManager.default.fileExists(atPath: src.path) {
            return try? Data(contentsOf: src)
        }
        return nil
    }
}

enum PhotoMigrator {
    private static let flagKey = "photos.migrated.to.data.v1"

    static func migrateFilePhotosIfNeeded(container: ModelContainer) {
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }
        let context = ModelContext(container)
        do {
            let machines = try context.fetch(FetchDescriptor<Machine>())
            for m in machines where m.photoData == nil {
                if let path = m.photoPath, let data = PhotoStore.dataFromBundleOrDisk(relativePath: path) {
                    m.photoData = data
                }
            }
            let bonuses = try context.fetch(FetchDescriptor<BonusEvent>())
            for b in bonuses where b.photoData == nil {
                if let path = b.photoPath, let data = PhotoStore.dataFromBundleOrDisk(relativePath: path) {
                    b.photoData = data
                }
            }
            try context.save()
            UserDefaults.standard.set(true, forKey: flagKey)
        } catch {
            print("Photo migration failed: \(error)")
        }
    }
}

private extension UIImage {
    func scaledToMaxSide(_ maxSide: CGFloat) -> UIImage {
        let side = max(size.width, size.height)
        guard side > maxSide, side > 0 else { return self }
        let scale = maxSide / side
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
