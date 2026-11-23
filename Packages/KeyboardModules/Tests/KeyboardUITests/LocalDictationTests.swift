import AVFAudio
import Testing

@testable import FullKeyboard

struct LocalDictationTests {
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
