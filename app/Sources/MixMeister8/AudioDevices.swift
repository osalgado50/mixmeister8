import AppKit
import AudioToolbox
import CoreAudio

/// Salidas de audio del sistema (Core Audio), para Tools › Audio Output Configuration.
struct AudioDevice: Hashable {
    let id: AudioDeviceID
    let name: String
    let uid: String

    static func outputs() -> [AudioDevice] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
        return ids.compactMap { id in
            guard outputChannels(id) > 0 else { return nil }
            return AudioDevice(id: id, name: string(id, kAudioObjectPropertyName) ?? "Salida \(id)", uid: string(id, kAudioDevicePropertyDeviceUID) ?? "")
        }
    }

    static func systemDefault() -> AudioDevice? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return outputs().first { $0.id == id }
    }

    private static func outputChannels(_ id: AudioDeviceID) -> Int {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func string(_ id: AudioDeviceID, _ sel: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let v = value else { return nil }
        return v.takeRetainedValue() as String
    }
}

/// Configuración de salida guardada (equivale a «Output Configuration» de MixMeister).
enum OutputConfig {
    static let mainKey = "MM8 Main Output UID", previewKey = "MM8 Preview Output UID"
    static var mainUID: String? {
        get { UserDefaults.standard.string(forKey: mainKey) }
        set { UserDefaults.standard.set(newValue, forKey: mainKey) }
    }
    static var previewUID: String? {
        get { UserDefaults.standard.string(forKey: previewKey) }
        set { UserDefaults.standard.set(newValue, forKey: previewKey) }
    }
    static func main() -> AudioDevice? {
        let all = AudioDevice.outputs()
        return all.first { $0.uid == mainUID } ?? AudioDevice.systemDefault()
    }

    /// Tools › Audio Output Configuration… (mismos campos que el diálogo del original: salida
    /// principal y, para directo, salida de preescucha).
    static func runDialog() {
        let all = AudioDevice.outputs()
        let a = NSAlert()
        a.messageText = "Audio Output Configuration"
        a.informativeText = "Elige por dónde suena MixMeister 8. La preescucha (auriculares) se usa al pinchar en directo."
        let mainPop = NSPopUpButton(frame: NSRect(x: 150, y: 34, width: 260, height: 26))
        let prevPop = NSPopUpButton(frame: NSRect(x: 150, y: 2, width: 260, height: 26))
        for d in all { mainPop.addItem(withTitle: d.name); prevPop.addItem(withTitle: d.name) }
        prevPop.insertItem(withTitle: "(la misma)", at: 0)
        if let m = main(), let i = all.firstIndex(of: m) { mainPop.selectItem(at: i) }
        if let p = previewUID, let i = all.firstIndex(where: { $0.uid == p }) { prevPop.selectItem(at: i + 1) } else { prevPop.selectItem(at: 0) }
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 64))
        let l1 = NSTextField(labelWithString: "Main output (speakers):"); l1.frame = NSRect(x: 0, y: 39, width: 148, height: 17)
        let l2 = NSTextField(labelWithString: "Preview (headphones):"); l2.frame = NSRect(x: 0, y: 7, width: 148, height: 17)
        [l1, l2, mainPop, prevPop].forEach { v.addSubview($0) }
        a.accessoryView = v
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let m = all[max(0, mainPop.indexOfSelectedItem)]
        mainUID = m.uid
        previewUID = prevPop.indexOfSelectedItem > 0 ? all[prevPop.indexOfSelectedItem - 1].uid : nil
        Player.shared.applyOutputDevice()
    }
}
