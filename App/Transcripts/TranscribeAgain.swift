import SwiftUI

/// What's done with a transcript, right under its text: its words copied or shared, and, when iikb kept its sound, that
/// sent on in a new message in Messages' own audio format or as a voice memo through the share sheet.
struct TranscriptActions: View {
    let transcript: Transcript
    @State private var failure: String?

    var body: some View {
        let kept = Transcripts.shared.hasRecording(transcript.id)
        if !transcript.text.isEmpty || kept {
            Box {
                if !transcript.text.isEmpty {
                    CopyRow(text: transcript.text)
                    ShareLink(item: transcript.text) {
                        HStack(spacing: 10) {
                            Text("Share Text")
                            Spacer()
                            Image(systemName: "square.and.arrow.up").font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(Color.blue)
                        .row()
                    }
                    .buttonStyle(.plain)
                }
                if kept {
                    ActionRow(title: "Send in Messages", symbol: "message") { send(as: .message) }
                    ActionRow(title: "Share Recording", symbol: "square.and.arrow.up") { send(as: .memo) }
                }
                if let failure { Text(failure).foregroundStyle(.red).row() }
            }
        }
    }

    private func send(as kind: Recording.Export) {
        failure = nil
        do { try RecordingShare.send(transcript, as: kind) } catch { failure = error.localizedDescription }
    }
}

/// The microphone a transcript was said into and whether voice processing heard it, and, when iikb kept its sound,
/// writing it again with the voice model picked now, to keep or not.
struct RecordingSection: View {
    let transcript: Transcript
    @State private var again: VoiceModel.Written?
    @State private var writing = false
    @State private var failure: String?

    var body: some View {
        let kept = Transcripts.shared.hasRecording(transcript.id)
        if kept || transcript.mic != nil {
            Box(footer: kept ? "iikb keeps the sound of each dictation on this \(ThisDevice.name), so it can be sent or written again with \(VoiceModel.shared.model.title)." : nil) {
                if let mic = transcript.mic { Fact(title: "Microphone", value: mic) }
                if let voiceProcessing = transcript.voiceProcessing { Fact(title: "Voice Processing", value: voiceProcessing ? "On" : "Off") }
                if let capture = transcript.capture.flatMap(Capture.init) { Fact(title: "Heard As", value: capture.title) }
                if kept {
                    ActionRow(title: writing ? VoiceModel.shared.state == .ready ? "Transcribing Again…" : "Transcribing Again once \(VoiceModel.shared.model.title) is ready…" : "Transcribe Again", symbol: "arrow.clockwise") { Task { await write() } }
                        .disabled(writing)
                }
                if let again, again.text.isEmpty {
                    RowText(title: "Nothing heard", detail: "Written by \(again.model)").row()
                } else if let again {
                    RowText(title: again.text, detail: "Written by \(again.model)")
                        .textSelection(.enabled)
                        .row()
                    ActionRow(title: "Use This Transcript") {
                        Transcripts.shared.replace(transcript.id, with: again.text, heard: again.heard, model: again.model)
                        self.again = nil
                    }
                    CopyRow(text: again.text)
                }
                if let failure { Text(failure).foregroundStyle(.red).row() }
            }
        }
    }

    private func write() async {
        writing = true
        failure = nil
        defer { writing = false }
        do {
            again = try await VoiceModel.shared.write(try Recording.read(Transcripts.shared.recording(of: transcript.id)), for: transcript.app)
        } catch {
            failure = error.localizedDescription
        }
    }
}
