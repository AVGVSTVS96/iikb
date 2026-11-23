import AVFAudio
import Testing
import VoiceCore

@testable import FullKeyboard

struct LocalDictationTests {
    static let megabyte = 1_048_576

    static func room(limit: Int, left: Int) -> ParakeetRoom {
        ParakeetRoom(limit: limit * megabyte, available: left * megabyte)
    }

    @Test func parakeetLoadsOnlyWithRoomForItsFirstLoad() {
        #expect(Self.room(limit: 177, left: 60).loads)
        #expect(!Self.room(limit: 177, left: 59).loads)
        #expect(!Self.room(limit: 130, left: 100).loads)
        #expect(ParakeetRoom(limit: 0, available: 0).loads)
    }

    @Test func writingTakesRoomForTheRecording() {
        #expect(Self.room(limit: 177, left: 34).writes(20))
        #expect(!Self.room(limit: 177, left: 33).writes(20))
    }

    @Test func appleWritesWhatParakeetCantLoadForOrWrite() {
        let roomy = Self.room(limit: 177, left: 80)
        #expect(roomy.model(picked: .v3, seconds: 10, loaded: false, setAside: false, warned: false) == .v3)
        #expect(roomy.model(picked: .ultra, seconds: 10, loaded: false, setAside: false, warned: false) == .v3)
        #expect(roomy.model(picked: .apple, seconds: 10, loaded: true, setAside: false, warned: false) == .apple)
        #expect(roomy.model(picked: .v3, seconds: 10, loaded: false, setAside: true, warned: false) == .apple)
        #expect(roomy.model(picked: .v3, seconds: 10, loaded: false, setAside: false, warned: true) == .apple)
        #expect(roomy.model(picked: .v3, seconds: 10, loaded: true, setAside: false, warned: true) == .v3)
        let loadedTight = Self.room(limit: 177, left: 40)
        #expect(loadedTight.model(picked: .v3, seconds: 10, loaded: true, setAside: false, warned: false) == .v3)
        #expect(loadedTight.model(picked: .v3, seconds: 10, loaded: false, setAside: false, warned: false) == .apple)
        #expect(loadedTight.model(picked: .v3, seconds: 40, loaded: true, setAside: false, warned: false) == .apple)
    }

    @Test func automaticTakesAWiredOrUSBMicrophoneNeverBluetooth() {
        let builtIn = (port: AVAudioSession.Port.builtInMic, name: "iPhone Microphone")
        let wired = (port: AVAudioSession.Port.headsetMic, name: "Headset Microphone")
        let usb = (port: AVAudioSession.Port.usbAudio, name: "USB Audio")
        let bluetooth = (port: AVAudioSession.Port.bluetoothHFP, name: "AirPods")
        let car = (port: AVAudioSession.Port.carAudio, name: "CarPlay")
        #expect(LocalDictation.automaticMicrophone(of: [builtIn, usb, wired]) == "Headset Microphone")
        #expect(LocalDictation.automaticMicrophone(of: [builtIn, usb]) == "USB Audio")
        #expect(LocalDictation.automaticMicrophone(of: [builtIn, bluetooth, car]) == nil)
    }
}
