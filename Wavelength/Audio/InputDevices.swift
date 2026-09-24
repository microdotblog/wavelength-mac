import CoreAudio
import Foundation

nonisolated struct InputDevice: Identifiable, Hashable, Sendable {
  let id: AudioDeviceID
  let uid: String
  let name: String
}

nonisolated enum InputDevices {
  static func all() -> [InputDevice] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0

    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
      return []
    }

    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)

    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else {
      return []
    }

    return ids.compactMap { id in
      guard inputChannelCount(id) > 0,
            let uid = string(kAudioDevicePropertyDeviceUID, of: id),
            let name = string(kAudioObjectPropertyName, of: id) else {
        return nil
      }

      return InputDevice(id: id, uid: uid, name: name)
    }
  }

  static func device(uid: String?) -> InputDevice? {
    guard let uid = uid.nonEmpty else { return nil }
    return all().first { $0.uid == uid }
  }

  static var defaultName: String? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var id = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)

    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr else {
      return nil
    }

    return string(kAudioObjectPropertyName, of: id)
  }

  private static func inputChannelCount(_ id: AudioDeviceID) -> Int {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreamConfiguration,
      mScope: kAudioDevicePropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0

    guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else {
      return 0
    }

    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { raw.deallocate() }

    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else {
      return 0
    }

    let buffers = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
    return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
  }

  private static func string(_ selector: AudioObjectPropertySelector, of id: AudioObjectID) -> String? {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else {
      return nil
    }

    return value.takeRetainedValue() as String
  }
}
