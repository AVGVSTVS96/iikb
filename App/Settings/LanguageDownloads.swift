import Foundation
import KeyboardStore

/// The languages' word data, downloaded on a tap from where the manifest says, checked against its size and SHA-256
/// before it's put in place (`LanguageFiles`, `Download`), so the keyboard never reads a file cut short or changed on the
/// way. A download that fails keeps what it got and goes on from there on Try Again; Cancel drops it.
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
            if LanguageFiles.isCurrent(id, as: item) {
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
            let result: Result<Void, Download.Failure>
            do throws(Download.Failure) {
                try await LanguageFiles.install(id, from: item, resumingFrom: self?.resumeData[id]) { done in
                    Task { @MainActor in
                        guard let self, case .downloading = self.states[id] else { return }
                        self.states[id] = .downloading(done)
                    }
                }
                result = .success(())
            } catch {
                result = .failure(error)
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

    private func finish(_ id: String, _ result: Result<Void, Download.Failure>) {
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
}
