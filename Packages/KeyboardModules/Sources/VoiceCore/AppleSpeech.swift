import AVFoundation
import Foundation
import KeyboardStore
import Speech

/// Apple's SpeechTranscriber (the iOS 26 model, not the older one behind the system's dictation key), else the dictation
/// model with punctuation.
public nonisolated enum AppleSpeech {
    /// `recording` written down, listening for `vocabulary`'s words. The app downloads the model's assets when iOS
    /// hasn't yet; a keyboard (`installs` false) leaves that to the app and throws `NotInstalled`, since a download
    /// started there ends with the keyboard.
    public static func write(_ recording: [Float], vocabulary: [String] = [], installs: Bool = true) async throws
        -> String
    {
        let (module, heard) = try await transcriber()
        defer { heard.cancel() }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw Unsupported()
        }
        guard let sound = Recording.converted(recording, to: format) else { throw Unconvertible() }
        if !installs {
            guard await AssetInventory.status(forModules: [module]) == .installed else { throw NotInstalled() }
        } else if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
        let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [module])
        if !vocabulary.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = vocabulary
            try? await analyzer.setContext(context)
        }
        try await analyzer.start(inputSequence: stream)
        input.yield(AnalyzerInput(buffer: sound))
        input.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await heard.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func transcriber() async throws -> (any SpeechModule, Task<String, any Error>) {
        if SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) {
            let module = SpeechTranscriber(locale: locale, preset: .transcription)
            return (
                module,
                Task {
                    var text = ""
                    for try await result in module.results where result.isFinal {
                        text += String(result.text.characters)
                    }
                    return text
                }
            )
        }
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: .current) else {
            throw Unsupported()
        }
        let module = DictationTranscriber(
            locale: locale, contentHints: [], transcriptionOptions: [.punctuation], reportingOptions: [],
            attributeOptions: [])
        return (
            module,
            Task {
                var text = ""
                for try await result in module.results where result.isFinal { text += String(result.text.characters) }
                return text
            }
        )
    }

    private struct Unsupported: LocalizedError {
        var errorDescription: String? { "Apple's model doesn't support this language." }
    }

    private struct NotInstalled: LocalizedError {
        var errorDescription: String? { "Apple's model isn't downloaded yet." }
    }

    private struct Unconvertible: LocalizedError {
        var errorDescription: String? { "This recording can't be read by Apple's model." }
    }
}
