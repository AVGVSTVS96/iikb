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

    private init() {}

    func state(of id: String) -> State {
        id == "en" ? .ready : states[id] ?? .absent
    }

    /// What's on disk now, keeping a download under way. A list an older build downloaded is downloaded again as this
    /// build's manifest names it, while the keyboard goes on with the old one until it's here.
    func reload() {
        for (id, item) in items where running[id] == nil {
            if LanguageFiles.isCurrent(item) {
                states[id] = .ready
            } else if LanguageFiles.has(id) {
                download(id)
            } else if states[id] == nil || states[id] == .ready {
                states[id] = .absent
            }
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
        states[id] = LanguageFiles.has(id) ? .ready : .absent
    }

    func remove(_ id: String) {
        cancel(id)
        LanguageFiles.remove(id)
        states[id] = .absent
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
        do {
            let (file, response) = try await download(item, resumingFrom: resumeData, progress: progress)
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
            try LanguageFiles.install(file, as: item)
            return .success(())
        } catch let error as URLError {
            return .failure(Failure(reason: error.localizedDescription, resumeData: error.downloadTaskResumeData))
        } catch {
            return .failure(Failure(reason: error.localizedDescription))
        }
    }

    /// Downloads `item` to a temporary file of its own, saying how much has come against the manifest's size, since a
    /// server may not say. A task's own count, not `download(from:delegate:)`, whose delegate hears nothing as it goes.
    private nonisolated static func download(
        _ item: LanguageFiles.Download, resumingFrom resumeData: Data?, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> (URL, URLResponse) {
        final class Running: @unchecked Sendable {
            var task: URLSessionDownloadTask?
            var watch: NSKeyValueObservation?
        }
        let running = Running()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let done: @Sendable (URL?, URLResponse?, (any Error)?) -> Void = { file, response, error in
                    running.watch?.invalidate()
                    guard let file, let response else {
                        return continuation.resume(throwing: error ?? URLError(.unknown))
                    }
                    // URLSession deletes `file` once this returns.
                    let kept = URL.temporaryDirectory.appending(path: UUID().uuidString)
                    do {
                        try FileManager.default.moveItem(at: file, to: kept)
                        continuation.resume(returning: (kept, response))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                let task =
                    if let resumeData {
                        URLSession.shared.downloadTask(withResumeData: resumeData, completionHandler: done)
                    } else {
                        URLSession.shared.downloadTask(with: item.url, completionHandler: done)
                    }
                let size = Double(max(item.size, 1))
                running.watch = task.observe(\.countOfBytesReceived) { task, _ in
                    let left = task.countOfBytesExpectedToReceive
                    let had = left > 0 ? size - Double(left) : 0
                    progress(min(max((had + Double(task.countOfBytesReceived)) / size, 0), 1))
                }
                running.task = task
                task.resume()
                if Task.isCancelled { task.cancel() }
            }
        } onCancel: {
            running.task?.cancel()
        }
    }
}
