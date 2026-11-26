import AVFoundation
import Observation

/// One transcript's sound played back at a time, through the microphone's session while it's on, else a playback
/// session of its own that lets other audio resume once it ends.
@Observable @MainActor final class RecordingPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = RecordingPlayer()

    private(set) var playing: Transcript.ID?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ownsSession = false

    func toggle(_ id: Transcript.ID) throws {
        let again = playing != id
        stop()
        guard again else { return }
        let player = try AVAudioPlayer(contentsOf: Transcripts.shared.recording(of: id))
        if !Listener.shared.isMicOn {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            ownsSession = true
        }
        player.delegate = self
        guard player.play() else {
            stop()
            return
        }
        self.player = player
        playing = id
    }

    func stop() {
        player?.stop()
        player = nil
        playing = nil
        if ownsSession, !Listener.shared.isMicOn {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        ownsSession = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if self.player === player { self.stop() }
        }
    }
}
