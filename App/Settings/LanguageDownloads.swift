import CryptoKit
import Foundation
import KeyboardStore

/// The languages' word data, downloaded on a tap from where the manifest says, checked against its size and SHA-256
/// before it's put in place (`LanguageFiles`), so the keyboard never reads a file cut short or changed on the way. A
/// download that fails keeps what it got and goes on from there on Try Again; Cancel drops it.
@Observable final class LanguageDownloads {
    static let shared = LanguageDownloads()

    enum State: Equatable {
        case absent
        case downloading(Double)
        case failed(String)
        case ready
    }

    let items = LanguageFiles.downloads
    private(set) var states: [String: State] = [:]
    private var running: [String: Task<Void, Never>] = [:]
    private var resumeData: [String: Data] = [:]
    /// Downloads started from a tap on the language itself, which it becomes once it's here.
    private var picking: Set<String> = []
    var picked: (String) -> Void = { _ in }

    private init() {
        reload()
    }

    func state(of id: String) -> State {
        id == "en" ? .ready : states[id] ?? .absent
    }

    /// What's on disk now, keeping a download under way.
    func reload() {
        for id in items.keys where running[id] == nil {
            states[id] = LanguageFiles.has(id) ? .ready : states[id] == nil ? .absent : states[id]
        }
    }

    func download(_ id: String, thenPick: Bool = false) {
        if thenPick { picking.insert(id) }
        guard let item = items[id], running[id] == nil else { return }
        states[id] = .downloading(0)
        running[id] = Task { [weak self] in
            let result = await Self.fetch(item, resumingFrom: self?.resumeData[id]) { done in
                Task { @MainActor in
                    guard let self, case .downloading = self.states[id] else { return }
                    self.states[id] = .downloading(done)
                }
            }
            self?.finish(id, result)
        }
    }

    func cancel(_ id: String) {
        running[id]?.cancel()
        running[id] = nil
        resumeData[id] = nil
        picking.remove(id)
        states[id] = .absent
    }

    func remove(_ id: String) {
        cancel(id)
        LanguageFiles.remove(id)
    }

    private func finish(_ id: String, _ result: Result<Void, Failure>) {
        guard running[id] != nil else { return }
        running[id] = nil
        switch result {
        case .success:
            resumeData[id] = nil
            states[id] = .ready
            if picking.remove(id) != nil { picked(id) }
        case .failure(let failure):
            resumeData[id] = failure.resumeData
            states[id] = .failed(failure.reason)
        }
    }

    struct Failure: Error {
        let reason: String
        var resumeData: Data?
    }

    private nonisolated static func fetch(
        _ item: LanguageFiles.Download, resumingFrom resumeData: Data?, progress: @escaping @Sendable (Double) -> Void
    ) async -> Result<Void, Failure> {
        let watcher = Watcher(size: item.size, progress: progress)
        do {
            let (file, response) =
                if let resumeData {
                    try await URLSession.shared.download(resumeFrom: resumeData, delegate: watcher)
                } else {
                    try await URLSession.shared.download(from: item.url, delegate: watcher)
                }
            defer { try? FileManager.default.removeItem(at: file) }
            if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
                return .failure(Failure(reason: "The download didn’t finish."))
            }
            // file: a downloaded language, checked before it's put in place
            let data = try Data(contentsOf: file, options: .alwaysMapped)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard data.count == item.size, digest == item.sha256 else {
                return .failure(Failure(reason: "The download came through damaged."))
            }
            try LanguageFiles.install(file, as: item.id)
            return .success(())
        } catch let error as URLError {
            return .failure(Failure(reason: error.localizedDescription, resumeData: error.downloadTaskResumeData))
        } catch {
            return .failure(Failure(reason: error.localizedDescription))
        }
    }

    /// Reports how much of a file has come, against the manifest's size, since a server may not say.
    private final class Watcher: NSObject, URLSessionDownloadDelegate, Sendable {
        let size: Int
        let progress: @Sendable (Double) -> Void

        init(size: Int, progress: @escaping @Sendable (Double) -> Void) {
            self.size = size
            self.progress = progress
        }

        func urlSession(
            _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
        ) {
            progress(min(Double(totalBytesWritten) / Double(max(size, 1)), 1))
        }

        func urlSession(
            _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
        ) {}
    }
}
