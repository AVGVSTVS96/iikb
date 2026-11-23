import CoreAudio

let wanted = CommandLine.arguments[1]
var address = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)
var size: UInt32 = 0
AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
var devices = [AudioDeviceID](repeating: 0, count: Int(size) / 4)
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices)
let input = devices.first { device in
    var name: CFString = "" as CFString
    var nameSize = UInt32(MemoryLayout<CFString>.size)
    var nameAddress = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &nameSize, &name)
    var streams = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain)
    var streamSize: UInt32 = 0
    AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamSize)
    return (name as String).hasPrefix(wanted) && streamSize > 0
}
guard var input else { exit(1) }
var defaultInput = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)
exit(AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultInput, 0, nil, 4, &input) == 0 ? 0 : 1)
