import AVFoundation
import AudioToolbox
import CoreAudioKit
import MMNEngine

/// Efectos de MixMeister 8.
///
/// El original trae 7 efectos AIR con licencia (Delay, Distortion, Filter Gate, Flanger, Fuzz-Wah,
/// Non-Lin Reverb, Phaser) y usaba también efectos NewBlue e iZotope; no se pueden incluir. En su
/// lugar MixMeister 8 trae efectos propios con los mismos nombres de función (con los Audio Units
/// de macOS o con el DSP del motor) y, como el original con los VST, admite cualquier Audio Unit
/// de efectos instalado en el Mac.
///
/// En la lista (EFXT): `plugin_id` = código de 4 letras del efecto; `slot` = número de instancia
/// (único en la lista, lo usan los marcadores de automatización); `flags` bit 0 = desactivado
/// (Enable/Bypass); `params` = valores normalizados 0..1. Marcadores de automatización
/// (TRKM 0x08000000): flag = slot << 12 | parámetro (0xFFF = Enable/Bypass), valor 0..1.
/// Los efectos del original se conservan intactos en la lista y suenan con su equivalente propio.

func fourCC(_ s: String) -> UInt32 { s.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) } }
func fourCCString(_ v: UInt32) -> String {
    String((0..<4).map { Character(UnicodeScalar(UInt8(truncatingIfNeeded: v >> (24 - 8 * $0)))) })
}

struct FxParam {
    let name: String
    let address: AUParameterAddress
    let min: Double, max: Double, def: Double
    var unit = ""
    var log = false
    var decimals = 1
    var steps: [String]? = nil          // parámetros por pasos (p. ej. tipo de filtro)

    func value(_ n: Double) -> Double {
        let x = Swift.min(1, Swift.max(0, n))
        return log && min > 0 ? min * pow(max / min, x) : min + (max - min) * x
    }
    func normalized(_ v: Double) -> Double {
        guard max != min else { return 0 }
        let x = log && min > 0 && v > 0 ? Foundation.log(v / min) / Foundation.log(max / min) : (v - min) / (max - min)
        return Swift.min(1, Swift.max(0, x))
    }
    var defNorm: Double { normalized(def) }
    func text(_ n: Double) -> String {
        if let steps { return steps[Swift.min(steps.count - 1, Int(n * Double(steps.count)))] }
        let v = value(n)
        if unit == "Hz", v >= 1000 { return String(format: "%.2f kHz", v / 1000) }
        if unit == "s", v < 1 { return String(format: "%.0f ms", v * 1000) }
        return String(format: "%.\(decimals)f", v) + (unit.isEmpty ? "" : " \(unit)")
    }
}

final class FxType {
    enum Host { case apple(AudioComponentDescription, fixed: [(AudioUnitParameterID, Float)]), dsp(Int32), installed(AVAudioUnitComponent) }
    let name: String
    let vendor: String
    let code: UInt32
    let host: Host
    var params: [FxParam]
    init(_ name: String, vendor: String = "MixMeister 8", code: String, host: Host, params: [FxParam]) {
        self.name = name; self.vendor = vendor; self.code = fourCC(code); self.host = host; self.params = params
    }
    init(component c: AVAudioUnitComponent) {
        name = c.name; vendor = c.manufacturerName; code = c.audioComponentDescription.componentSubType
        host = .installed(c); params = []
    }
    var listName: String { "\(name) - \(vendor)" }
    var description: AudioComponentDescription {
        switch host {
        case let .apple(d, _): return d
        case let .dsp(k): return FxCatalog.dspDescription(k)
        case let .installed(c): return c.audioComponentDescription
        }
    }
    var isInstalled: Bool { if case .installed = host { return true }; return false }
}

enum FxCatalog {
    static let manufacturer = fourCC("MM8x")
    static let dspCodes: [Int32: String] = [MMN_FX_FLANGER: "m8fl", MMN_FX_PHASER: "m8ph", MMN_FX_FUZZWAH: "m8fw", MMN_FX_FILTERGATE: "m8fg", MMN_FX_STEREOIZER: "m8st",
                                           MMN_FX_GAIN: "m8gn", MMN_FX_LIMITER: "m8lt"]

    static func dspDescription(_ kind: Int32) -> AudioComponentDescription {
        AudioComponentDescription(componentType: kAudioUnitType_Effect, componentSubType: fourCC(dspCodes[kind] ?? "m8fl"),
                                  componentManufacturer: manufacturer, componentFlags: 0, componentFlagsMask: 0)
    }
    static func apple(_ sub: OSType) -> AudioComponentDescription {
        AudioComponentDescription(componentType: kAudioUnitType_Effect, componentSubType: sub,
                                  componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
    }
    private static func pct(_ name: String, _ a: AUParameterAddress, _ def: Double, min: Double = 0) -> FxParam {
        FxParam(name: name, address: a, min: min, max: 100, def: def, unit: "%", decimals: 0)
    }
    private static func norm(_ name: String, _ i: Int, unit: String = "%", lo: Double = 0, hi: Double = 100, log: Bool = false, decimals: Int = 0, steps: [String]? = nil) -> FxParam {
        // Parámetro del DSP propio: llega normalizado; min/max solo sirven para mostrarlo.
        FxParam(name: name, address: AUParameterAddress(i), min: lo, max: hi, def: lo, unit: unit, log: log, decimals: decimals, steps: steps)
    }

    /// Efectos propios. Los siete primeros, en el orden de la lista del original.
    static let builtIn: [FxType] = {
        var list: [FxType] = [
            FxType("MM8 Distortion", code: "M8ds", host: .apple(apple(kAudioUnitSubType_Distortion), fixed: [(0, 0.1), (2, 0), (13, 0), (6, 1)]), params: [
                FxParam(name: "Drive", address: 14, min: -20, max: 20, def: 6, unit: "dB"),
                FxParam(name: "Squared", address: 7, min: 0, max: 20, def: 8, decimals: 1),
                FxParam(name: "Cubic", address: 8, min: 0, max: 20, def: 8, decimals: 1),
                pct("Shape Mix", 9, 50),
                pct("Bit Crush", 3, 0), pct("Crush Mix", 5, 0),
                pct("Mix", 15, 50),
            ]),
            FxType("MM8 Non-Lin Reverb", code: "M8nr", host: .apple(apple(kAudioUnitSubType_Reverb2), fixed: [(6, 1)]), params: [
                FxParam(name: "Decay", address: 4, min: 0.1, max: 6, def: 0.6, unit: "s", log: true, decimals: 2),
                FxParam(name: "Damping", address: 5, min: 0.05, max: 6, def: 0.25, unit: "s", log: true, decimals: 2),
                FxParam(name: "Pre-Delay", address: 2, min: 0.001, max: 0.25, def: 0.02, unit: "s", log: true),
                FxParam(name: "Size", address: 3, min: 0.01, max: 1, def: 0.1, unit: "s", log: true, decimals: 2),
                FxParam(name: "Gain", address: 1, min: -20, max: 20, def: 0, unit: "dB"),
                pct("Mix", 0, 30),
            ]),
            FxType("MM8 Delay", code: "M8dl", host: .apple(apple(kAudioUnitSubType_Delay), fixed: []), params: [
                FxParam(name: "Time", address: 1, min: 0.01, max: 2, def: 0.375, unit: "s", log: true, decimals: 2),
                FxParam(name: "Feedback", address: 2, min: -100, max: 100, def: 40, unit: "%", decimals: 0),
                FxParam(name: "Fdbk Damp", address: 3, min: 200, max: 20000, def: 20000, unit: "Hz", log: true, decimals: 0),
                pct("Mix", 0, 50),
            ]),
            FxType("MM8 Fuzz-Wah", code: "M8fw", host: .dsp(MMN_FX_FUZZWAH), params: [
                norm("Drive", 0, unit: "dB", lo: 0, hi: 36), norm("Wah", 1, unit: "Hz", lo: 350, hi: 2600, log: true),
                norm("Resonance", 2, unit: "", lo: 0.7, hi: 12, decimals: 1), norm("LFO Rate", 3, unit: "Hz", lo: 0.1, hi: 8, log: true, decimals: 2),
                norm("LFO Depth", 4), norm("Mix", 5),
            ]),
            FxType("MM8 Flanger", code: "M8fl", host: .dsp(MMN_FX_FLANGER), params: [
                norm("Rate", 0, unit: "Hz", lo: 0.03, hi: 6, log: true, decimals: 2), norm("Depth", 1),
                norm("Feedback", 2, lo: -95, hi: 95), norm("Mix", 3),
            ]),
            FxType("MM8 Filter Gate", code: "M8fg", host: .dsp(MMN_FX_FILTERGATE), params: [
                norm("Cutoff", 0, unit: "Hz", lo: 30, hi: 18000, log: true), norm("Resonance", 1, unit: "", lo: 0.6, hi: 14, decimals: 1),
                norm("Type", 2, steps: ["Low Pass", "Band Pass", "High Pass"]), norm("Gate Rate", 3, unit: "Hz", lo: 0.25, hi: 16, log: true, decimals: 2),
                norm("Gate Depth", 4), norm("Mix", 5),
            ]),
            FxType("MM8 Phaser", code: "M8ph", host: .dsp(MMN_FX_PHASER), params: [
                norm("Rate", 0, unit: "Hz", lo: 0.03, hi: 6, log: true, decimals: 2), norm("Depth", 1), norm("Feedback", 2, lo: 0, hi: 92),
                norm("Stages", 3, steps: ["2", "4", "6", "8", "10", "12"]), norm("Mix", 4),
            ]),
        ]
        list += [
            FxType("MM8 Reverb", code: "M8rv", host: .apple(apple(kAudioUnitSubType_Reverb2), fixed: [(6, 1)]), params: [
                FxParam(name: "Decay", address: 4, min: 0.2, max: 12, def: 2.2, unit: "s", log: true, decimals: 2),
                FxParam(name: "Damping", address: 5, min: 0.1, max: 12, def: 1.0, unit: "s", log: true, decimals: 2),
                FxParam(name: "Pre-Delay", address: 2, min: 0.001, max: 0.25, def: 0.02, unit: "s", log: true),
                FxParam(name: "Gain", address: 1, min: -20, max: 20, def: 0, unit: "dB"),
                pct("Mix", 0, 25),
            ]),
            FxType("MM8 Parametric EQ", code: "M8eq", host: .apple(apple(kAudioUnitSubType_ParametricEQ), fixed: []), params: [
                FxParam(name: "Frequency", address: 0, min: 20, max: 20000, def: 1000, unit: "Hz", log: true, decimals: 0),
                FxParam(name: "Q", address: 1, min: 0.1, max: 20, def: 1, log: true, decimals: 2),
                FxParam(name: "Gain", address: 2, min: -20, max: 20, def: 0, unit: "dB"),
            ]),
            FxType("MM8 Stereoizer", code: "M8st", host: .dsp(MMN_FX_STEREOIZER), params: [
                norm("Width", 0, lo: 0, hi: 200), norm("Haas", 1, unit: "ms", lo: 0, hi: 20, decimals: 1), norm("Mix", 2),
            ]),
            FxType("MM8 MultiLimit", code: "M8ml", host: .apple(apple(kAudioUnitSubType_MultiBandCompressor), fixed: []), params: [
                FxParam(name: "Input", address: 0, min: -40, max: 40, def: 0, unit: "dB"),
                FxParam(name: "Output", address: 1, min: -40, max: 40, def: 0, unit: "dB"),
                FxParam(name: "Low", address: 5, min: -100, max: 0, def: -22, unit: "dB"),
                FxParam(name: "Low Mid", address: 6, min: -100, max: 0, def: -32, unit: "dB"),
                FxParam(name: "High Mid", address: 7, min: -100, max: 0, def: -33, unit: "dB"),
                FxParam(name: "High", address: 8, min: -100, max: 0, def: -36, unit: "dB"),
                FxParam(name: "Attack", address: 13, min: 0.001, max: 0.2, def: 0.08, unit: "s", log: true),
                FxParam(name: "Release", address: 14, min: 0.01, max: 3, def: 0.12, unit: "s", log: true),
            ]),
            FxType("MM8 Limiter", code: "M8lm", host: .apple(apple(kAudioUnitSubType_PeakLimiter), fixed: []), params: [
                FxParam(name: "Attack", address: 0, min: 0.001, max: 0.03, def: 0.012, unit: "s", log: true),
                FxParam(name: "Release", address: 1, min: 0.001, max: 0.06, def: 0.024, unit: "s", log: true),
                FxParam(name: "Gain", address: 2, min: -40, max: 40, def: 0, unit: "dB"),
            ]),
            FxType("MM8 Compressor", code: "M8cp", host: .apple(apple(kAudioUnitSubType_DynamicsProcessor), fixed: []), params: [
                FxParam(name: "Threshold", address: 0, min: -40, max: 20, def: -20, unit: "dB"),
                FxParam(name: "Headroom", address: 1, min: 0.1, max: 40, def: 5, unit: "dB"),
                FxParam(name: "Attack", address: 4, min: 0.0001, max: 0.2, def: 0.001, unit: "s", log: true),
                FxParam(name: "Release", address: 5, min: 0.01, max: 3, def: 0.05, unit: "s", log: true),
                FxParam(name: "Gain", address: 6, min: -40, max: 40, def: 0, unit: "dB"),
            ]),
            FxType("MM8 Low-Pass", code: "M8lp", host: .apple(apple(kAudioUnitSubType_LowPassFilter), fixed: []), params: [
                FxParam(name: "Cutoff", address: 0, min: 20, max: 20000, def: 20000, unit: "Hz", log: true, decimals: 0),
                FxParam(name: "Resonance", address: 1, min: -20, max: 40, def: 0, unit: "dB"),
            ]),
            FxType("MM8 High-Pass", code: "M8hp", host: .apple(apple(kAudioUnitSubType_HighPassFilter), fixed: []), params: [
                FxParam(name: "Cutoff", address: 0, min: 10, max: 20000, def: 10, unit: "Hz", log: true, decimals: 0),
                FxParam(name: "Resonance", address: 1, min: -20, max: 40, def: 0, unit: "dB"),
            ]),
        ]
        // Valores por defecto del DSP propio (los define el motor).
        for t in list {
            guard case let .dsp(k) = t.host else { continue }
            t.params = t.params.enumerated().map { i, p in
                FxParam(name: p.name, address: p.address, min: p.min, max: p.max, def: p.value(Double(mmn_fx_param_default(k, Int32(i)))),
                        unit: p.unit, log: p.log, decimals: p.decimals, steps: p.steps)
            }
        }
        return list
    }()

    /// Audio Units de efectos instalados (como los VST de otros fabricantes en el original).
    static let installed: [FxType] = {
        let any = AudioComponentDescription(componentType: kAudioUnitType_Effect, componentSubType: 0, componentManufacturer: 0, componentFlags: 0, componentFlagsMask: 0)
        return AVAudioUnitComponentManager.shared().components(matching: any)
            .filter { $0.audioComponentDescription.componentManufacturer != kAudioUnitManufacturer_Apple && $0.audioComponentDescription.componentManufacturer != manufacturer }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map(FxType.init(component:))
    }()

    static var all: [FxType] { builtIn + installed }

    /// Equivalente propio de un efecto del original (por nombre).
    static let substitutes: [(String, String)] = [
        ("Non-Lin", "MM8 Non-Lin Reverb"), ("Distortion", "MM8 Distortion"), ("Delay", "MM8 Delay"), ("Echo", "MM8 Delay"),
        ("Fuzz", "MM8 Fuzz-Wah"), ("Wah", "MM8 Fuzz-Wah"), ("Flanger", "MM8 Flanger"), ("Chorus", "MM8 Flanger"),
        ("Filter Gate", "MM8 Filter Gate"), ("Gate", "MM8 Filter Gate"), ("Phaser", "MM8 Phaser"), ("Reverb", "MM8 Reverb"),
        ("Parametric", "MM8 Parametric EQ"), ("EQ", "MM8 Parametric EQ"), ("Stereo", "MM8 Stereoizer"), ("Width", "MM8 Stereoizer"),
        ("MultiLimit", "MM8 Limiter"), ("Multiband", "MM8 MultiLimit"), ("Limit", "MM8 Limiter"), ("Compress", "MM8 Compressor"),
        ("Low Pass", "MM8 Low-Pass"), ("High Pass", "MM8 High-Pass"),
    ]

    struct Resolved {
        let type: FxType?           // con qué suena
        let native: Bool            // el efecto ES ese tipo (sus parámetros son los del tipo)
    }
    static func resolve(_ e: PLEffect) -> Resolved {
        if let t = builtIn.first(where: { $0.code == e.plugin_id }) { return Resolved(type: t, native: true) }
        if let t = installed.first(where: { $0.code == e.plugin_id && e.name.hasPrefix($0.name) }) ?? installed.first(where: { $0.code == e.plugin_id }) {
            return Resolved(type: t, native: true)
        }
        for (k, v) in substitutes where e.name.range(of: k, options: .caseInsensitive) != nil {
            return Resolved(type: builtIn.first { $0.name == v }, native: false)
        }
        return Resolved(type: nil, native: false)
    }

    static func registerDSP() {
        for (k, _) in dspCodes {
            let name = builtIn.first { if case let .dsp(x) = $0.host { return x == k }; return false }?.name ?? "MM8"
            AUAudioUnit.registerSubclass(MM8FxUnit.self, as: dspDescription(k), name: "MixMeister 8: \(name)", version: 1)
        }
    }

    /// Un efecto nuevo (como al soltarlo en una pista): instancia siguiente a las que hay en la lista.
    static func newEffect(_ t: FxType, doc: PLDocument) -> PLEffect {
        let used = doc.master_effects.map(\.slot) + doc.tracks.flatMap { $0.effects.map(\.slot) }
        if t.isInstalled, t.params.isEmpty, let n = FxHost.makeNode(t) { FxHost.loadParams(t, from: n) }
        return PLEffect(plugin_id: t.code, code: fourCCString(t.code), slot: (used.max() ?? 0) + 1, flags: 0,
                        params: t.params.map(\.defNorm), name: t.isInstalled ? t.name : t.name)
    }
}

/// Crea y ajusta los nodos de efecto.
enum FxHost {
    static func makeNode(_ t: FxType) -> AVAudioUnitEffect? {
        var d = t.description
        guard AudioComponentFindNext(nil, &d) != nil else { Log.write("efecto \(t.name): no está instalado"); return nil }
        let n = AVAudioUnitEffect(audioComponentDescription: t.description)
        if t.isInstalled, t.params.isEmpty { loadParams(t, from: n) }
        if case let .apple(_, fixed) = t.host {
            for (id, v) in fixed { AudioUnitSetParameter(n.audioUnit, id, kAudioUnitScope_Global, 0, v, 0) }
        }
        return n
    }

    /// Parámetros de un Audio Unit instalado (los 64 primeros que se pueden escribir).
    static func loadParams(_ t: FxType, from n: AVAudioUnitEffect) {
        guard let tree = n.auAudioUnit.parameterTree else { return }
        t.params = tree.allParameters.filter { $0.flags.contains(.flag_IsWritable) }.prefix(64).map { p in
            FxParam(name: p.displayName, address: p.address, min: Double(p.minValue), max: Double(p.maxValue),
                    def: Double(p.value), unit: p.unitName ?? "", decimals: 2, steps: p.valueStrings)
        }
    }

    /// Pone en el nodo los valores (normalizados) de la lista.
    static func apply(_ e: PLEffect, _ r: FxCatalog.Resolved, to n: AVAudioUnitEffect) {
        n.bypass = e.flags & 1 != 0
        // Un AIR del original: sus parámetros principales, llevados a los del equivalente propio.
        if !r.native, let t = r.type, let m = AirEffects.map(e) {
            for (air, (k, conv)) in m where k < t.params.count { set(t, t.params[k], conv(AirEffects.value(e, air)), on: n) }
            return
        }
        guard let t = r.type, r.native else { return }
        for (i, p) in t.params.enumerated() { set(t, p, i < e.params.count ? e.params[i] : p.defNorm, on: n) }
    }

    static func set(_ t: FxType, _ p: FxParam, _ norm: Double, on n: AVAudioUnitEffect) {
        switch t.host {
        case .apple:
            AudioUnitSetParameter(n.audioUnit, AudioUnitParameterID(p.address), kAudioUnitScope_Global, 0, Float(p.value(norm)), 0)
        case .dsp:
            n.auAudioUnit.parameterTree?.parameter(withAddress: p.address)?.value = AUValue(norm)
        case .installed:
            n.auAudioUnit.parameterTree?.parameter(withAddress: p.address)?.value = AUValue(p.value(norm))
        }
    }

    static func read(_ t: FxType, _ p: FxParam, from n: AVAudioUnitEffect) -> Double? {
        switch t.host {
        case .apple:
            var v: AudioUnitParameterValue = 0
            guard AudioUnitGetParameter(n.audioUnit, AudioUnitParameterID(p.address), kAudioUnitScope_Global, 0, &v) == noErr else { return nil }
            return p.normalized(Double(v))
        case .dsp: return (n.auAudioUnit.parameterTree?.parameter(withAddress: p.address)?.value).map { Double($0) }
        case .installed: return (n.auAudioUnit.parameterTree?.parameter(withAddress: p.address)?.value).map { p.normalized(Double($0)) }
        }
    }
}

/// Audio Unit propio (en el proceso) que ejecuta los efectos del motor (mmn_fx_*).
final class MM8FxUnit: AUAudioUnit {
    final class RenderState {
        var fx: OpaquePointer?; var scratch: AVAudioPCMBuffer?
        /// Bypass (Enable/Bypass del rack y sus marcadores): se pasa el audio seco, con un fundido de
        /// ~10 ms entre seco y procesado para que encender o apagar el efecto no haga clic.
        var bypass = false
        var mix: Float = 1                 // 0 = seco, 1 = procesado (lo que suena ahora)
        var dry: AVAudioPCMBuffer?
    }
    override var shouldBypassEffect: Bool {
        get { state.bypass }
        set { state.bypass = newValue }
    }
    private let kind: Int32
    private var inBus: AUAudioUnitBus!, outBus: AUAudioUnitBus!
    private var ins: AUAudioUnitBusArray!, outs: AUAudioUnitBusArray!
    private let state = RenderState()
    private var values = [AUValue](repeating: 0, count: 8)

    override init(componentDescription d: AudioComponentDescription, options: AudioComponentInstantiationOptions = []) throws {
        kind = FxCatalog.dspCodes.first { fourCC($0.value) == d.componentSubType }?.key ?? MMN_FX_FLANGER
        try super.init(componentDescription: d, options: options)
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        inBus = try AUAudioUnitBus(format: fmt)
        outBus = try AUAudioUnitBus(format: fmt)
        inBus.maximumChannelCount = 2
        outBus.maximumChannelCount = 2
        ins = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inBus])
        outs = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outBus])
        let n = Int(mmn_fx_param_count(kind))
        var ps: [AUParameter] = []
        for i in 0..<n {
            values[i] = mmn_fx_param_default(kind, Int32(i))
            ps.append(AUParameterTree.createParameter(withIdentifier: "p\(i)", name: "P\(i + 1)", address: AUParameterAddress(i),
                                                      min: 0, max: 1, unit: .generic, unitName: nil,
                                                      flags: [.flag_IsReadable, .flag_IsWritable], valueStrings: nil, dependentParameters: nil))
        }
        let tree = AUParameterTree.createTree(withChildren: ps)
        let st = state
        tree.implementorValueObserver = { [weak self] p, v in
            let i = Int(p.address)
            if i < 8 { self?.values[i] = v }
            if let fx = st.fx { mmn_fx_set(fx, Int32(i), v) }
        }
        tree.implementorValueProvider = { [weak self] p in
            let i = Int(p.address)
            return i < 8 ? (self?.values[i] ?? 0) : 0
        }
        parameterTree = tree
        maximumFramesToRender = 4096
    }

    override var inputBusses: AUAudioUnitBusArray { ins }
    override var outputBusses: AUAudioUnitBusArray { outs }
    override var canProcessInPlace: Bool { true }

    override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        let f = outBus.format
        if let fx = state.fx { mmn_fx_free(fx) }
        let fx = mmn_fx_new(kind, f.sampleRate, Int32(f.channelCount))
        for i in 0..<8 { mmn_fx_set(fx, Int32(i), values[i]) }
        state.scratch = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: f.sampleRate, channels: max(1, f.channelCount))!,
                                         frameCapacity: maximumFramesToRender)
        state.dry = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: f.sampleRate, channels: 2)!, frameCapacity: maximumFramesToRender)
        state.mix = state.bypass ? 0 : 1
        state.fx = fx
    }

    override func deallocateRenderResources() {
        super.deallocateRenderResources()
        let fx = state.fx
        state.fx = nil
        if let fx { mmn_fx_free(fx) }
    }

    override var internalRenderBlock: AUInternalRenderBlock {
        let st = state
        return { _, timestamp, frames, _, out, _, pull in
            guard let pull else { return kAudioUnitErr_NoConnection }
            let abl = UnsafeMutableAudioBufferListPointer(out)
            if let sc = st.scratch, let ch = sc.floatChannelData {
                for i in 0..<abl.count where abl[i].mData == nil && i < Int(sc.format.channelCount) {
                    abl[i].mData = UnsafeMutableRawPointer(ch[i])
                    abl[i].mDataByteSize = frames * 4
                }
            }
            var pf = AudioUnitRenderActionFlags()
            let err = pull(&pf, timestamp, frames, 0, out)
            if err != noErr { return err }
            guard let fx = st.fx, abl.count > 0, let l = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let r = abl.count > 1 ? abl[1].mData?.assumingMemoryBound(to: Float.self) : nil
            let target: Float = st.bypass ? 0 : 1
            if target == 0 && st.mix == 0 { return noErr }                 // apagado: seco, sin gastar CPU
            if target == 1 && st.mix == 1 { mmn_fx_process(fx, l, r, Int32(frames)); return noErr }
            // Transición: se guarda el seco, se procesa y se funde (10 ms).
            guard let dry = st.dry?.floatChannelData, Int(frames) <= Int(st.dry!.frameCapacity) else {
                st.mix = target; if target == 1 { mmn_fx_process(fx, l, r, Int32(frames)) }; return noErr
            }
            let n = Int(frames)
            if st.mix == 0 { mmn_fx_reset(fx) }                              // entra limpio, sin restos de antes
            dry[0].update(from: l, count: n)
            if let r { dry[1].update(from: r, count: n) }
            mmn_fx_process(fx, l, r, Int32(frames))
            let step: Float = 1 / Float(max(1, 0.01 * 44100))
            var g = st.mix
            for i in 0..<n {
                g = target > g ? min(target, g + step) : max(target, g - step)
                l[i] = dry[0][i] + (l[i] - dry[0][i]) * g
                if let r { r[i] = dry[1][i] + (r[i] - dry[1][i]) * g }
            }
            st.mix = g
            return noErr
        }
    }
}

/// Nodos de efecto en directo, uno por instancia de la lista (se reutilizan entre reproducciones,
/// y el panel de control actúa sobre ellos).
final class FxPool {
    static let shared = FxPool()
    private var nodes: [UInt32: (code: UInt32, node: AVAudioUnitEffect)] = [:]
    func node(for e: PLEffect, type: FxType) -> AVAudioUnitEffect? {
        if let n = nodes[e.slot], n.code == type.code, n.node.engine == nil { return n.node }
        if let n = nodes[e.slot], n.code == type.code, n.node.engine != nil { return nil }
        guard let n = FxHost.makeNode(type) else { return nil }
        nodes[e.slot] = (type.code, n)
        return n
    }
    func existing(_ slot: UInt32) -> AVAudioUnitEffect? { nodes[slot]?.node }
    func reset() { nodes.removeAll() }
}

/// Efectos AIR del original (AIR Music Technology; con licencia: MixMeister 8 no los incluye y suenan
/// con su equivalente propio). Guardan sus parámetros en un bloque «ACVS»: nombre en +8, +72 u32 = 1,
/// +76 u32 = número de parámetros y, desde +80, los parámetros normalizados (f32 0..1) en el orden del
/// rack del original (por columnas) y de su desplegable de parámetros. Comprobado el 29-10-2026: AIR
/// Phaser Rate 1,00 → 3,39 Hz cambia el primer valor 0,500 → 0,765 (escala 0,1–10 Hz logarítmica).
enum AirEffects {
    /// Floats de cabecera antes del primer parámetro (80 bytes).
    static let offset = 20
    static let names: [String: [String]] = [
        "AIR Distortion": ["Mode", "Pre-Shape", "Drive", "Threshold", "Edge", "High Cut", "Output", "Stereo", "Mix"],
        "AIR Non-Lin Reverb": ["Dry Delay", "Pre-Delay", "Time", "Diffusion", "Low Cut", "High Cut", "Width", "Shape", "Mix"],
        "AIR Delay": ["Time", "Sync", "L/R Ratio", "Feedback", "Fdbk Damp", "Fdbk Reso", "Fdbk Reso Freq", "HPF", "Width", "Mix"],
        "AIR Fuzz-Wah": ["Mix", "Order", "Fuzz", "Fuzz Mix", "Drive", "Tone", "Output", "Wah", "Wah Mix", "Pedal",
                         "Min Freq", "Max Freq", "Min Reso", "Max Reso", "Filter Mode", "Mod Mode", "Rate", "Depth"],
        "AIR Flanger": ["Rate", "Depth", "Feedback", "Headroom", "Mix"],
        "AIR Filter Gate": ["Pattern", "Rate", "Swing", "Attack", "Hold", "Release", "Filter Mode", "Cutoff", "Resonance",
                            "Env Mod", "LFO Mod", "LFO Wave", "Mix"],
        "AIR Phaser": ["Rate", "Depth", "Feedback", "Offset", "Offset Type", "Model", "Mix"],
    ]
    /// Nombres de los parámetros si `e` es un AIR con su bloque completo.
    static func paramNames(_ e: PLEffect) -> [String]? {
        guard let n = names[e.name] ?? names.first(where: { e.name.hasPrefix($0.key) })?.value,
              e.params.count >= offset + n.count else { return nil }
        // +76: número de parámetros (comprobación; si no cuadra, no se interpreta el bloque).
        if Float(e.params[offset - 1]).bitPattern != UInt32(n.count) { return nil }
        return n
    }
    static func value(_ e: PLEffect, _ i: Int) -> Double { offset + i < e.params.count ? e.params[offset + i] : 0.5 }
    /// Cómo se lee el valor en el rack: en unidades donde la escala está medida; si no, en %.
    static func text(_ e: PLEffect, _ i: Int) -> (Double) -> String {
        if e.name.hasPrefix("AIR Phaser"), i == 0 { return { String(format: "%.2f Hz", logHz($0, 0.1, 10)) } }
        return { String(format: "%.0f %%", $0 * 100) }
    }

    private static func logHz(_ v: Double, _ lo: Double, _ hi: Double) -> Double { lo * pow(hi / lo, v) }
    private static func toLogNorm(_ hz: Double, _ lo: Double, _ hi: Double) -> Double { max(0, min(1, log(hz / lo) / log(hi / lo))) }
    private static let same: (Double) -> Double = { $0 }
    private static let bipolar: (Double) -> Double = { 0.5 + 0.5 * $0 }     // 0..100 % → −x..+x (0 en medio)
    /// Parámetro del AIR → parámetro de su equivalente propio (índices en FxType.params, valor normalizado).
    /// Phaser Rate convierte la escala medida; el resto es aproximado (misma posición del mando).
    static let toSubstitute: [String: [Int: (Int, (Double) -> Double)]] = [
        "AIR Flanger": [0: (0, same), 1: (1, same), 2: (2, bipolar), 4: (3, same)],
        "AIR Phaser": [0: (0, { toLogNorm(logHz($0, 0.1, 10), 0.03, 6) }), 1: (1, same), 2: (2, same), 6: (4, same)],
        "AIR Fuzz-Wah": [0: (5, same), 4: (0, same), 9: (1, same), 13: (2, same), 16: (3, same), 17: (4, same)],
        "AIR Filter Gate": [1: (3, same), 6: (2, same), 7: (0, same), 8: (1, same), 12: (5, same)],
        "AIR Distortion": [2: (0, same), 8: (6, same)],
        "AIR Non-Lin Reverb": [1: (2, same), 2: (0, same), 8: (5, same)],
        "AIR Delay": [0: (0, same), 3: (1, bipolar), 4: (2, same), 9: (3, same)],
    ]
    static func map(_ e: PLEffect) -> [Int: (Int, (Double) -> Double)]? {
        guard paramNames(e) != nil else { return nil }
        return toSubstitute[e.name] ?? toSubstitute.first(where: { e.name.hasPrefix($0.key) })?.value
    }
}
