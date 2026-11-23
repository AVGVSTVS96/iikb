import Foundation
import KeyboardCore

public enum SessionLogs {
    public static let mostBytes = 64 << 20

    public struct Saved: Identifiable, Sendable {
        public let url: URL
        public let date: Date
        public let size: Int
        public var id: URL { url }
    }

    nonisolated static var folder: URL? {
        AppGroup.library?.appending(path: "SessionLogs")
    }

    public static func name(at date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        return "iikb typing \(formatter.string(from: date))"
    }

    public static func save(_ log: SessionLog, as name: String) {
        guard var folder, log.steps.contains(where: { $0.edits != nil }) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        StoredFile<SessionLog>(folder.appending(path: "\(name).json")).save(log)
        var kept = 0
        for saved in saved() {
            kept += saved.size
            if kept > mostBytes { delete(saved) }
        }
    }

    public static func saved() -> [Saved] {
        guard let folder else { return [] }
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        let files =
            (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys))) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys), let size = values.fileSize,
                let date = values.contentModificationDate
            else { return nil }
            return Saved(url: url, date: date, size: size)
        }.sorted { $0.date > $1.date }
    }

    public static func delete(_ saved: Saved) {
        try? FileManager.default.removeItem(at: saved.url)
    }

    public static func deleteAll() {
        if let folder { try? FileManager.default.removeItem(at: folder) }
    }
}
