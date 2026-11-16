import CryptoKit
import Foundation

/// A file iikb downloads and can download again: fetched to a temporary file of its own, checked against its size and
/// SHA-256, then put in place in one move, so nothing ever reads half a file or a changed one. It's marked as left out
/// of backups, which iCloud's and iikb's own `Backup` follow.
nonisolated public struct Download: Sendable {
    public let url: URL
    public let size: Int
    public let sha256: String

    public init(url: URL, size: Int, sha256: String) {
        self.url = url
        self.size = size
        self.sha256 = sha256
    }

    public struct Failure: Error {
        public let reason: String
        /// What came before it broke off, to go on from.
        public var resumeData: Data?
    }

    /// Downloads it to `place`, going on from `resumeData` when there's some, and saying how much has come, from 0 to 1.
    /// Cancelling the task it runs in stops it as a broken-off download, with what came to go on from.
    public func fetch(
        to place: URL, resumingFrom resumeData: Data? = nil, progress: @escaping @Sendable (Double) -> Void
    ) async throws(Failure) {
        do {
            let (file, response) = try await downloaded(resumingFrom: resumeData, progress: progress)
            defer { try? FileManager.default.removeItem(at: file) }
            if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
                throw Failure(reason: "The download didn’t finish.")
            }
            // file: a download, checked before it's put in place
            let data = try Data(contentsOf: file, options: .alwaysMapped)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard data.count == size, digest == sha256 else {
                throw Failure(reason: "The download came through damaged.")
            }
            try FileManager.default.createDirectory(
                at: place.deletingLastPathComponent(), withIntermediateDirectories: true)
            _ = try FileManager.default.replaceItemAt(place, withItemAt: file)
            var placed = place
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try placed.setResourceValues(values)
        } catch let failure as Failure {
            throw failure
        } catch let error as URLError {
            throw Failure(reason: error.localizedDescription, resumeData: error.downloadTaskResumeData)
        } catch {
            throw Failure(reason: error.localizedDescription)
        }
    }

    /// Downloads it to a temporary file of its own, saying how much has come against `size`, since a server may not
    /// say. A task's own count, not `download(from:delegate:)`, whose delegate hears nothing as it goes.
    private func downloaded(
        resumingFrom resumeData: Data?, progress: @escaping @Sendable (Double) -> Void
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
                        URLSession.shared.downloadTask(with: url, completionHandler: done)
                    }
                let whole = Double(max(size, 1))
                running.watch = task.observe(\.countOfBytesReceived) { task, _ in
                    let left = task.countOfBytesExpectedToReceive
                    let had = left > 0 ? whole - Double(left) : 0
                    progress(min(max((had + Double(task.countOfBytesReceived)) / whole, 0), 1))
                }
                running.task = task
                task.resume()
                if Task.isCancelled { task.cancel(byProducingResumeData: { _ in }) }
            }
        } onCancel: {
            running.task?.cancel(byProducingResumeData: { _ in })
        }
    }
}
