import AVFoundation
import AppKit
import AudioToolbox
import MMNEngine

extension Notification.Name {
    static let playerTick = Notification.Name("mm8.playerTick")
    static let playerState = Notification.Name("mm8.playerState")
}

/// Registro de diagnóstico: ~/Library/Logs/MixMeister 8.log
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/MixMeister 8.log")
    private static let q = DispatchQueue(label: "mm8.log")
    static func write(_ s: String) {
        let line = "\(Date()) \(s)\n"
        q.async {
            if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
            else { try? line.write(to: url, atomically: true, encoding: .utf8) }
        }
    }
}

/// La mezcla como grafo de audio: por pista, reproductor → [cambio de tempo sin cambio de tono] →
/// [ecualizador de 3 bandas] → ganancia sin escalones → efectos → mezclador → efectos del master →
/// limitador → salida. Lo usan igual la reproducción en directo y la exportación (fichero o CD), así
/// que lo que se exporta es exactamente lo que se oye.
///
/// Calidad: una pista que suena a su tempo y en su tono no pasa por el cambio de tempo, y sin
/// marcadores de EQ no pasa por el ecualizador; a 0 dB la ganancia no la toca y el limitador solo
/// actúa por encima de −0,3 dBFS: la pista llega a la salida idéntica bit a bit.
final class MixGraph {
    struct Chain {
        let index: Int
        let player = AVAudioPlayerNode()
        var pitch: AVAudioUnitTimePitch?          // solo si la pista cambia de tempo o de tono
        var eq: AVAudioUnitEQ?                     // solo si tiene marcadores de EQ
        var gain: AVAudioUnitEffect?               // volumen sin escalones (DSP del motor)
        var gainParam: AUParameter?
        let file: AVAudioFile
        let item: MixLayout.Item
        let volume: [(t: Double, db: Double)]      // por posición en el audio (s)
        let bass: [(t: Double, db: Double)], mid: [(t: Double, db: Double)], treble: [(t: Double, db: Double)]
        var fx: [FxSlot] = []
        let sync = Sync()
    }
    /// Sincronía del cambio de tempo. AUNewTimePitch avanza por saltos de entrada enteros de
    /// 4096/overlap muestras, así que la velocidad real es round(H·v)/H y una pista con el tempo
    /// cambiado se iba desplazando (medido: 0,98 → +0,047 %, 1,0417 → −0,063 %, 1,10 → −0,036 %;
    /// hasta 150 ms en 5 minutos). Se lleva la cuenta del audio que consume de verdad (con ese
    /// modelo) frente a donde debe ir, y en cada bloque se pide la velocidad que lo corrige: alterna
    /// entre los dos saltos vecinos y el desfase queda por debajo de un salto (~3 ms).
    final class Sync { var from = 0.0, idle = 0.0, accNow = 0.0, idleRate = 1.0, consumed = 0.0, lastMix = Double.nan, lastRate = 1.0, hop = 256.0 }
    static var servo = !CommandLine.arguments.contains("--noservo")
    private func expected(_ c: Chain, at t: Double) -> Double {
        let s = c.sync, item = c.item
        if t >= item.mixStart { return s.idle + (item.toSource(t) - s.accNow) }
        return max(0, s.idle - (item.mixStart - t) * s.idleRate)
    }
    /// Velocidad real de AUNewTimePitch para una velocidad pedida.
    static func effectiveRate(_ r: Double, hop: Double) -> Double { (r * hop).rounded() / hop }
    /// Un efecto conectado: su nodo y su automatización (marcadores 0x08000000 de la pista).
    final class FxSlot {
        let slot: UInt32
        let node: AVAudioUnitEffect
        let type: FxType
        var resolved: FxCatalog.Resolved
        var auto: [(param: Int, env: [(t: Double, db: Double)])] = []
        init(slot: UInt32, node: AVAudioUnitEffect, type: FxType, resolved: FxCatalog.Resolved) {
            self.slot = slot; self.node = node; self.type = type; self.resolved = resolved
        }
    }
    let engine: AVAudioEngine
    private(set) var chains: [Chain] = []
    /// Limitador del master (DSP del motor, con anticipación de 1,5 ms): por debajo de −0,3 dBFS no
    /// toca el audio; evita que los solapes saturen.
    private let limiter = AVAudioUnitEffect(audioComponentDescription: FxCatalog.dspDescription(MMN_FX_LIMITER))
    /// Salida final (tras el limitador): lo que se graba con Record Mix.
    var outputTapNode: AVAudioNode { limiter }
    /// Retardo del limitador en muestras (la exportación lo descuenta).
    var latencyFrames: Int { master ? 66 : 0 }
    /// Solo una pista (exportación en paralelo: una pista por motor) y sin la sección del master.
    let only: Int?
    let master: Bool
    let layout: MixLayout
    private(set) var doc: PLDocument
    private var masterFx: [FxSlot] = []
    /// De dónde salen los nodos de efecto: en directo, del FxPool (persisten entre reproducciones
    /// y el panel de control actúa sobre ellos); al exportar, nodos nuevos.
    let fxNode: (PLEffect, FxType) -> AVAudioUnitEffect?

    init(engine: AVAudioEngine, layout: MixLayout, doc: PLDocument, only: Int? = nil, master: Bool = true,
         fxNode: @escaping (PLEffect, FxType) -> AVAudioUnitEffect? = { _, t in FxHost.makeNode(t) }) {
        self.engine = engine; self.layout = layout; self.doc = doc; self.fxNode = fxNode
        self.only = only; self.master = master
    }

    private func makeSlots(_ effects: [PLEffect]) -> [FxSlot] {
        effects.compactMap { e in
            let r = FxCatalog.resolve(e)
            guard let t = r.type, let n = fxNode(e, t) else { return nil }
            FxHost.apply(e, r, to: n)
            return FxSlot(slot: e.slot, node: n, type: t, resolved: r)
        }
    }
    private static func automation(_ t: PLTrack, _ slots: [FxSlot]) {
        for s in slots {
            var byParam: [Int: [(t: Double, db: Double)]] = [:]
            for m in t.markers where m.type == MarkerKind.effectParam && m.flag >> 12 == s.slot {
                byParam[Int(m.flag & 0xFFF), default: []].append((Double(m.pos_us) * 1e-6, m.value))
            }
            s.auto = byParam.map { ($0.key, $0.value.sorted { $0.t < $1.t }) }
        }
    }

    /// Crea las cadenas de las pistas que aún suenan después de `from`. Devuelve cuántas.
    @discardableResult
    func build(from: Double, audioPath: @escaping (Int) -> String?, horizon: Double? = nil) -> Int {
        pendingPath = audioPath
        for item in layout.items where item.mixEnd > from && !item.segments.isEmpty && (only == nil || only == item.index) {
            // En directo solo se montan las pistas que entran pronto; las demás, al acercarse (extend).
            if let h = horizon, item.mixStart > from + h { pending.append(item); continue }
            if let c = makeChain(item, audioPath: audioPath) { chains.append(c) }
        }
        return finishBuild()
    }

    // MARK: Montaje por pistas (en directo, solo las cercanas al cursor)

    private var pending: [MixLayout.Item] = []
    private var pendingPath: ((Int) -> String?)?
    /// Pistas montadas ahora mismo (diagnóstico).
    var chainCount: Int { chains.count }
    var hasAudio: Bool { !chains.isEmpty || !pending.isEmpty }

    /// Monta las pistas que entran en los próximos `lead` s y desmonta las que acabaron hace más de
    /// 8 s (para que suenen las colas de los efectos). `startAt` da el instante de la mezcla y el
    /// tiempo de reloj en que puede arrancar un reproductor nuevo.
    func extend(at mix: Double, lead: Double = 20, startAt: () -> (mix: Double, when: AVAudioTime)) {
        let ready = pending.filter { $0.mixStart < mix + lead }
        if !ready.isEmpty, let path = pendingPath {
            pending.removeAll { p in ready.contains { $0.index == p.index } }
            for item in ready {
                guard let c = makeChain(item, audioPath: path) else { continue }
                let s = startAt()
                scheduleChain(c, from: s.mix)
                c.player.play(at: s.when)
                chains.append(c)
                Log.write(String(format: "montada pista %d (entra en %.1f s; %d montadas)", item.index + 1, item.mixStart, chains.count))
            }
        }
        let done = chains.filter { mix > $0.item.mixEnd + 8 }
        for c in done { unmount(c) }
        if !done.isEmpty { chains.removeAll { c in done.contains { $0.index == c.index } } }
    }
    private func unmount(_ c: Chain) {
        c.player.stop()
        for n in [c.player, c.pitch, c.eq, c.gain].compactMap({ $0 as AVAudioNode? }) + c.fx.map(\.node) {
            engine.disconnectNodeOutput(n); engine.detach(n)
        }
        for f in c.fx { f.node.reset() }
    }

    private func makeChain(_ item: MixLayout.Item, audioPath: (Int) -> String?) -> Chain? {
            guard item.index < doc.tracks.count, let path = audioPath(item.index),
                  let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) else { return nil }
            let t = doc.tracks[item.index]
            func env(_ kinds: [UInt32]) -> [(t: Double, db: Double)] {
                t.markers.filter { kinds.contains($0.type) }.map { (Double($0.pos_us) * 1e-6, $0.value) }.sorted { $0.t < $1.t }
            }
            var c = Chain(index: item.index, file: file, item: item,
                          volume: env([MarkerKind.volume, MarkerKind.autoVolume, MarkerKind.autoVolumeIn]),
                          bass: env([MarkerKind.bass]), mid: env([MarkerKind.mid]), treble: env([MarkerKind.treble]))
            c.fx = makeSlots(t.effects)
            Self.automation(t, c.fx)
            // ¿Suena siempre a su tempo y en su tono? Entonces no hace falta el cambio de tempo.
            let constantRate = !item.overlay && t.markers(MarkerKind.tempo).isEmpty
                && abs(MixLayout.ownTempo(t) - MixLayout.audioTempo(t)) < 1e-6 && t.key_semitones == 0
            if !constantRate || Self.forceTimePitch {
                let p = AVAudioUnitTimePitch()
                p.pitch = Float(t.key_semitones * 100)      // Track Settings › Key Adjustment (cents)
                p.overlap = Self.timePitchOverlap
                c.pitch = p
            }
            if !(c.bass.isEmpty && c.mid.isEmpty && c.treble.isEmpty) {
                let e = AVAudioUnitEQ(numberOfBands: 3)
                let b = e.bands
                b[0].filterType = .lowShelf; b[0].frequency = 120; b[0].bypass = false
                b[1].filterType = .parametric; b[1].frequency = 1000; b[1].bandwidth = 1.5; b[1].bypass = false
                b[2].filterType = .highShelf; b[2].frequency = 6000; b[2].bypass = false
                for k in 0..<3 { b[k].gain = 0 }
                c.eq = e
            }
            let g = AVAudioUnitEffect(audioComponentDescription: FxCatalog.dspDescription(MMN_FX_GAIN))
            c.gain = g
            c.gainParam = g.auAudioUnit.parameterTree?.parameter(withAddress: 0)
            let fmt = file.processingFormat
            // reproductor → [tempo] → [EQ] → ganancia → efectos (de izquierda a derecha) → mezclador
            var last: AVAudioNode = c.player
            engine.attach(c.player)
            for n in [c.pitch, c.eq, c.gain].compactMap({ $0 as AVAudioNode? }) + c.fx.map(\.node) {
                engine.attach(n)
                engine.connect(last, to: n, format: fmt)
                last = n
            }
            engine.connect(last, to: engine.mainMixerNode, format: fmt)
            return c
    }

    /// Exportación normalizada: ganancia antes del limitador y su techo (dBFS).
    static var exportPreGainDB = 0.0
    static var exportCeilingDB: Double? = nil

    private func finishBuild() -> Int {
        guard master else { return chains.count }
        engine.mainMixerNode.outputVolume = Float(pow(10, (doc.master_gain_db + Self.exportPreGainDB) / 20))
        if let c = Self.exportCeilingDB { limiter.auAudioUnit.parameterTree?.parameter(withAddress: 0)?.value = AUValue(max(0, min(1, (c + 12) / 12))) }
        // mezclador → efectos del master → limitador → salida
        let fmt = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.attach(limiter)
        engine.disconnectNodeOutput(engine.mainMixerNode)
        masterFx = makeSlots(doc.master_effects)
        var last: AVAudioNode = engine.mainMixerNode
        for f in masterFx {
            engine.attach(f.node)
            engine.connect(last, to: f.node, format: fmt)
            last = f.node
        }
        engine.connect(last, to: limiter, format: fmt)
        engine.connect(limiter, to: engine.outputNode, format: fmt)
        return chains.count + pending.count
    }

    /// Programa los segmentos. El tiempo de cada reproductor cuenta segundos de audio consumido:
    /// antes de que entre la pista, corre a la velocidad de su entrada (se mantiene fija hasta
    /// entonces); después, los segmentos van seguidos.
    func schedule(from: Double) { for c in chains { scheduleChain(c, from: from) } }

    private func scheduleChain(_ c: Chain, from: Double) {
        do {
            let sr = c.file.processingFormat.sampleRate
            let item = c.item
            let segs = item.segments.sorted { $0.mixStart < $1.mixStart }
            guard let first = segs.first else { return }
            let started = from >= item.mixStart
            let accNow = started ? item.toSource(from) : first.acc
            let idle = started ? 0 : (item.mixStart - from) * (c.pitch == nil ? 1 : item.rate(at: item.mixStart))
            c.pitch?.rate = Float(max(1.0 / 32, min(32, item.rate(at: max(from, item.mixStart)))))
            c.sync.from = from; c.sync.idle = idle; c.sync.accNow = accNow
            c.sync.idleRate = c.pitch == nil ? 1 : item.rate(at: item.mixStart)
            c.sync.consumed = 0; c.sync.lastMix = .nan
            c.sync.lastRate = Double(c.pitch?.rate ?? 1)
            c.sync.hop = 4096 / Double(max(1, c.pitch?.overlap ?? 16))
            for seg in segs where seg.mixEnd > from {
                var startSrc = seg.srcStart
                var playerTime = idle + (seg.acc - accNow)
                if started, from > seg.mixStart {           // el segmento ya va por la mitad
                    startSrc = seg.srcStart + (accNow - seg.acc)
                    playerTime = 0
                }
                let a = AVAudioFramePosition(max(0, startSrc) * sr)
                let e = min(c.file.length, AVAudioFramePosition(seg.srcEnd * sr))
                guard e > a else { continue }
                let when = AVAudioTime(sampleTime: AVAudioFramePosition(max(0, playerTime) * sr), atRate: sr)
                c.player.scheduleSegment(c.file, startingFrame: a, frameCount: AVAudioFrameCount(e - a), at: when)
            }
        }
    }

    func start(at time: AVAudioTime?) { for c in chains { c.player.play(at: time) } }

    func teardown() {
        pending.removeAll()
        for c in chains {
            c.player.stop()
            for n in [c.player, c.pitch, c.eq, c.gain].compactMap({ $0 as AVAudioNode? }) { engine.disconnectNodeOutput(n); engine.detach(n) }
            for f in c.fx { engine.disconnectNodeOutput(f.node); engine.detach(f.node); f.node.reset() }
        }
        chains.removeAll()
        for f in masterFx { engine.disconnectNodeOutput(f.node); engine.detach(f.node); f.node.reset() }
        masterFx.removeAll()
        if limiter.engine != nil {
            let fmt = engine.mainMixerNode.outputFormat(forBus: 0)
            engine.disconnectNodeOutput(limiter)
            engine.disconnectNodeOutput(engine.mainMixerNode)
            engine.detach(limiter)
            engine.connect(engine.mainMixerNode, to: engine.outputNode, format: fmt)
        }
    }

    /// Calidad del cambio de tempo (AUNewTimePitch, 3…32): más solape = menos artefactos.
    static var timePitchOverlap: Float = {
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "--overlap"), i + 1 < a.count, let v = Float(a[i + 1]) { return v }
        return Float(UserDefaults.standard.object(forKey: "MM8 TimePitch Overlap") as? Double ?? 16)
    }()
    /// Para pruebas: pasar todas las pistas por el cambio de tempo (como hasta ahora).
    static var forceTimePitch = CommandLine.arguments.contains("--forcepitch")

    private static func value(_ env: [(t: Double, db: Double)], at t: Double) -> Double? {
        guard let first = env.first else { return nil }
        if t <= first.t { return first.db }
        for i in 1..<env.count where t < env[i].t {
            let a = env[i - 1], b = env[i]
            return a.db + (b.db - a.db) * (t - a.t) / max(1e-9, b.t - a.t)
        }
        return env.last!.db
    }

    /// Volumen, ecualización y tempo en el instante `mix` de la mezcla.
    func update(at mix: Double) {
        for c in chains {
            let item = c.item
            if let p = c.pitch, mix <= item.mixEnd + 0.5 {
                let ideal = mix >= item.mixStart ? item.rate(at: mix) : c.sync.idleRate
                var r = ideal
                if Self.servo {
                    let s = c.sync
                    // Lo que ha consumido desde el bloque anterior (con la velocidad real de entonces).
                    if !s.lastMix.isNaN, mix > s.lastMix { s.consumed += Self.effectiveRate(s.lastRate, hop: s.hop) * (mix - s.lastMix) }
                    s.lastMix = mix
                    let err = expected(c, at: mix) - s.consumed           // > 0: va por detrás
                    let want = ideal + max(-0.02, min(0.02, err / 0.2)) * ideal
                    // Se pide un salto entero exacto (así el modelo coincide con lo que hace el AU), y
                    // nunca exactamente 1,0: ahí AUNewTimePitch cambia de modo y su retardo salta
                    // (medido: con 1,00013 la deriva pasaba de 41 a 88 ms en 5 minutos).
                    var q = (want * s.hop).rounded()
                    if q == s.hop { q = err >= 0 ? s.hop + 1 : s.hop - 1 }
                    r = q / s.hop
                    s.lastRate = r
                }
                let fr = Float(max(1.0 / 32, min(32, r)))
                if p.rate != fr { p.rate = fr }          // cambiarlo cuesta: solo si cambia
            }
            // Antes de entrar y después de acabar la pista no hay nada más que ajustar.
            if mix < item.mixStart - 0.5 || mix > item.mixEnd + 0.5 { continue }
            let seg = item.segments.first { mix >= $0.mixStart && mix < $0.mixEnd } ?? item.segments[0]
            let src = seg.source(item, at: mix)
            let db = Self.value(c.volume, at: src) ?? 0
            let lin = db <= -49.5 ? 0 : pow(10, db / 20)
            let gv = AUValue(min(1, lin / 4))
            if let gp = c.gainParam, gp.value != gv { gp.value = gv }
            if let eq = c.eq {
                eq.bands[0].gain = Float(max(-60, min(24, Self.value(c.bass, at: src) ?? 0)))
                eq.bands[1].gain = Float(max(-60, min(24, Self.value(c.mid, at: src) ?? 0)))
                eq.bands[2].gain = Float(max(-60, min(24, Self.value(c.treble, at: src) ?? 0)))
            }
            // Automatización de los efectos (Effects Parameter Markers)
            for f in c.fx where !f.auto.isEmpty {
                for a in f.auto {
                    guard let v = Self.value(a.env, at: src) else { continue }
                    if a.param == 0xFFF { f.node.bypass = v < 0.5; continue }
                    guard f.resolved.native, a.param < f.type.params.count else { continue }
                    FxHost.set(f.type, f.type.params[a.param], v, on: f.node)
                }
            }
        }
    }

    /// Cambios en los efectos sin volver a montar el grafo (al mover un knob mientras suena).
    func applyEffects(_ d: PLDocument) {
        doc = d
        for c in chains where c.index < d.tracks.count {
            let t = d.tracks[c.index]
            for f in c.fx { if let e = t.effects.first(where: { $0.slot == f.slot }) { FxHost.apply(e, f.resolved, to: f.node) } }
            Self.automation(t, c.fx)
        }
        for f in masterFx { if let e = d.master_effects.first(where: { $0.slot == f.slot }) { FxHost.apply(e, f.resolved, to: f.node) } }
    }
    /// ¿Tiene el grafo los mismos efectos (instancias y orden) que la lista?
    func sameEffects(as d: PLDocument) -> Bool {
        guard masterFx.map(\.slot) == d.master_effects.map(\.slot) else { return false }
        for c in chains where c.index < d.tracks.count {
            if c.fx.map(\.slot) != d.tracks[c.index].effects.map(\.slot) { return false }
        }
        return true
    }
}

/// Reproducción en directo.
final class Player {
    static let shared = Player()

    private let engine = AVAudioEngine()
    private var graph: MixGraph?
    private var startHost: UInt64 = 0
    private var startMix: Double = 0
    private var timer: Timer?
    private(set) var isPlaying = false
    private var pausedAt: Double = 0
    var peakL: Float = 0, peakR: Float = 0
    private var preview: AVAudioPlayer?

    /// Posición actual en la mezcla (s).
    var position: Double {
        guard isPlaying else { return pausedAt }
        let now = mach_absolute_time()
        guard now > startHost else { return startMix }      // arranca unos ms en el futuro
        return startMix + Double(now - startHost) * Self.ticksToSeconds
    }
    private static let ticksToSeconds: Double = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return Double(tb.numer) / Double(tb.denom) / 1e9
    }()

    init() {
        let mixer = engine.mainMixerNode
        mixer.installTap(onBus: 0, bufferSize: 1024, format: mixer.outputFormat(forBus: 0)) { [weak self] buf, _ in
            guard let self, let ch = buf.floatChannelData else { return }
            let n = Int(buf.frameLength)
            var l: Float = 0, r: Float = 0
            for i in 0..<n { l = max(l, abs(ch[0][i])) }
            if buf.format.channelCount > 1 { for i in 0..<n { r = max(r, abs(ch[1][i])) } } else { r = l }
            self.peakL = max(l, self.peakL * 0.85)
            self.peakR = max(r, self.peakR * 0.85)
            // Sonoridad en directo (EBU R128, a corto plazo) para el medidor LUFS.
            self.loudLock.lock()
            if self.loud == nil { self.loud = mmn_loud_new(buf.format.sampleRate, Int32(buf.format.channelCount)) }
            mmn_loud_add(self.loud, ch[0], buf.format.channelCount > 1 ? ch[1] : nil, Int32(n))
            self.loudLock.unlock()
        }
        setDevice()
        // Estabilidad: si cambia el dispositivo de salida (se desenchufa, cambia la frecuencia de
        // muestreo…), AVAudioEngine se para; se vuelve a montar y sigue sonando desde donde iba.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self else { return }
            Log.write("cambio de configuración de audio (salida \(self.outputName))")
            if self.isPlaying { let at = self.position; self.play(from: at) }
        }
    }

    // MARK: Salida (Tools › Audio Output Configuration)

    func applyOutputDevice() {
        let wasPlaying = isPlaying, at = position
        if wasPlaying { stopNodes() }
        engine.stop()
        setDevice()
        if wasPlaying { play(from: at) }
    }
    private func setDevice() {
        guard let dev = OutputConfig.main(), let au = engine.outputNode.audioUnit else { return }
        var id = dev.id
        AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
    }
    var outputName: String { OutputConfig.main()?.name ?? "—" }

    // MARK: Transporte

    func toggle(from t: Double? = nil) { isPlaying ? pause() : play(from: t ?? pausedAt) }

    /// En directo, montar solo las pistas cercanas al cursor (--nolazy: todas, como antes).
    static var lazy = !CommandLine.arguments.contains("--nolazy")
    var chainCount: Int { graph?.chainCount ?? 0 }

    // MARK: Medidor de sonoridad

    private let loudLock = NSLock()
    private var loud: OpaquePointer?
    /// Sonoridad a corto plazo (3 s) de lo que suena, en LUFS (−inf si no suena nada).
    var shortTermLUFS: Double {
        loudLock.lock(); defer { loudLock.unlock() }
        return loud.map { mmn_loud_shortterm($0) } ?? -.infinity
    }
    private func resetLoudness() {
        loudLock.lock(); if let l = loud { mmn_loud_free(l) }; loud = nil; loudLock.unlock()
    }

    // MARK: Grabar la sesión (Playback › Record Mix…)

    /// Graba lo que sale por la salida principal (tras el limitador) mientras suena, aunque se
    /// pare, se mueva el cursor o se cambie la lista: todo va seguido al mismo fichero.
    private(set) var recordURL: URL?
    private var recordFile: AVAudioFile?
    private let recordLock = NSLock()
    private(set) var recordedFrames: AVAudioFramePosition = 0
    private var tapped: AVAudioNode?
    var isRecording: Bool { recordURL != nil }
    private var recordRate = 44100.0
    var recordedSeconds: Double { Double(recordedFrames) / recordRate }

    func startRecording(to url: URL) {
        recordURL = url
        recordedFrames = 0
        recordFile = nil
        if let g = graph { installRecordTap(g) }
        Log.write("grabación: \(url.path)")
        NotificationCenter.default.post(name: .playerState, object: nil)
    }
    func stopRecording() {
        removeRecordTap()
        recordLock.lock(); recordFile = nil; recordLock.unlock()
        Log.write(String(format: "grabación terminada: %.1f s", recordedSeconds))
        recordURL = nil
        NotificationCenter.default.post(name: .playerState, object: nil)
    }
    private func installRecordTap(_ g: MixGraph) {
        guard let url = recordURL else { return }
        let node = g.outputTapNode
        let fmt = node.outputFormat(forBus: 0)
        recordRate = fmt.sampleRate
        recordLock.lock()
        if recordFile == nil {
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: fmt.sampleRate, AVNumberOfChannelsKey: fmt.channelCount,
                                           AVLinearPCMBitDepthKey: 24, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsFloatKey: false]
            recordFile = try? AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        }
        recordLock.unlock()
        node.installTap(onBus: 0, bufferSize: 4096, format: fmt) { [weak self] buf, _ in
            guard let self else { return }
            self.recordLock.lock(); defer { self.recordLock.unlock() }
            guard let f = self.recordFile, f.processingFormat.sampleRate == buf.format.sampleRate else { return }
            try? f.write(from: buf)
            self.recordedFrames += AVAudioFramePosition(buf.frameLength)
        }
        tapped = node
    }
    private func removeRecordTap() { tapped?.removeTap(onBus: 0); tapped = nil }

    func play(from t: Double) {
        stopNodes()
        let s = Session.shared
        let from = max(0, min(t, max(0, s.layout.total - 0.05)))
        let g = MixGraph(engine: engine, layout: s.layout, doc: s.doc) { e, t in FxPool.shared.node(for: e, type: t) }
        let n = g.build(from: from, audioPath: { s.audioPath($0) }, horizon: Self.lazy ? 30 : nil)
        Log.write("play desde \(String(format: "%.2f", from)) s: \(n) pistas con audio de \(s.layout.items.count)")
        guard n > 0 else { pausedAt = from; return }
        setDevice()
        engine.prepare()
        do { try engine.start() } catch { Log.write("ERROR al arrancar el audio: \(error)"); g.teardown(); return }
        g.schedule(from: from)
        g.update(at: from)
        let host = mach_absolute_time() + UInt64(0.08 / Self.ticksToSeconds)
        g.start(at: AVAudioTime(hostTime: host))
        resetLoudness()
        if isRecording { installRecordTap(g) }
        graph = g
        startHost = host
        startMix = from
        isPlaying = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        Log.write("sonando · salida \(outputName)")
        NotificationCenter.default.post(name: .playerState, object: nil)
    }

    func pause() {
        Log.write("pausa en \(String(format: "%.2f", position))")
        pausedAt = position
        stopNodes()
        NotificationCenter.default.post(name: .playerState, object: nil)
        NotificationCenter.default.post(name: .playerTick, object: nil)
    }

    func stop() {
        Log.write("stop")
        stopNodes()
        pausedAt = 0
        NotificationCenter.default.post(name: .playerState, object: nil)
        NotificationCenter.default.post(name: .playerTick, object: nil)
    }

    func seek(_ t: Double) {
        if isPlaying { play(from: t) } else { pausedAt = max(0, t); NotificationCenter.default.post(name: .playerTick, object: nil) }
    }

    private func stopNodes() {
        removeRecordTap()
        timer?.invalidate(); timer = nil
        // El motor se para siempre (y antes de desmontar el grafo): con el motor en marcha no se
        // puede desconectar el limitador, y los reproductores recién conectados no arrancan.
        engine.stop()
        graph?.teardown(); graph = nil
        engine.reset()
        isPlaying = false
        peakL = 0; peakR = 0
    }

    /// Efectos cambiados: se aplican al momento; si cambió qué efectos hay, se vuelve a montar.
    func effectsChanged() {
        guard isPlaying, let g = graph else { return }
        if g.sameEffects(as: Session.shared.doc) { g.applyEffects(Session.shared.doc) } else { play(from: position) }
    }

    private func tick() {
        let p = position
        if p >= Session.shared.layout.total + 0.5 { Log.write("fin de la mezcla"); stop(); return }
        graph?.update(at: p)
        if Self.lazy {
            graph?.extend(at: p) {
                let host = mach_absolute_time() + UInt64(0.05 / Self.ticksToSeconds)
                return (self.startMix + Double(host - self.startHost) * Self.ticksToSeconds, AVAudioTime(hostTime: host))
            }
        }
        NotificationCenter.default.post(name: .playerTick, object: nil)
    }

    // MARK: Preescucha de la biblioteca

    func previewPlay(path: String) {
        preview?.stop()
        preview = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
        preview?.play()
    }
    func previewStop() { preview?.stop(); preview = nil }
    var isPreviewing: Bool { preview?.isPlaying ?? false }
}
