import AVFoundation
import AppKit
import AudioToolbox

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

/// La mezcla como grafo de audio: por pista, reproductor → cambio de tempo sin cambio de tono →
/// ecualizador de 3 bandas → mezclador. Lo usan igual la reproducción en directo y la exportación
/// (fichero o CD), así que lo que se exporta es exactamente lo que se oye.
final class MixGraph {
    struct Chain {
        let index: Int
        let player = AVAudioPlayerNode()
        let pitch = AVAudioUnitTimePitch()
        let eq = AVAudioUnitEQ(numberOfBands: 3)
        let file: AVAudioFile
        let item: MixLayout.Item
        let volume: [(t: Double, db: Double)]      // por posición en el audio (s)
        let bass: [(t: Double, db: Double)], mid: [(t: Double, db: Double)], treble: [(t: Double, db: Double)]
        var fx: [FxSlot] = []
    }
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
    /// Limitador del master (Apple Peak Limiter, −1 dB): evita que los solapes saturen.
    private let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
    let layout: MixLayout
    private(set) var doc: PLDocument
    private var masterFx: [FxSlot] = []
    /// De dónde salen los nodos de efecto: en directo, del FxPool (persisten entre reproducciones
    /// y el panel de control actúa sobre ellos); al exportar, nodos nuevos.
    let fxNode: (PLEffect, FxType) -> AVAudioUnitEffect?

    init(engine: AVAudioEngine, layout: MixLayout, doc: PLDocument,
         fxNode: @escaping (PLEffect, FxType) -> AVAudioUnitEffect? = { _, t in FxHost.makeNode(t) }) {
        self.engine = engine; self.layout = layout; self.doc = doc; self.fxNode = fxNode
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
    func build(from: Double, audioPath: (Int) -> String?) -> Int {
        for item in layout.items where item.mixEnd > from && !item.segments.isEmpty {
            guard item.index < doc.tracks.count, let path = audioPath(item.index),
                  let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) else { continue }
            let t = doc.tracks[item.index]
            func env(_ kinds: [UInt32]) -> [(t: Double, db: Double)] {
                t.markers.filter { kinds.contains($0.type) }.map { (Double($0.pos_us) * 1e-6, $0.value) }.sorted { $0.t < $1.t }
            }
            var c = Chain(index: item.index, file: file, item: item,
                          volume: env([MarkerKind.volume, MarkerKind.autoVolume, MarkerKind.autoVolumeIn]),
                          bass: env([MarkerKind.bass]), mid: env([MarkerKind.mid]), treble: env([MarkerKind.treble]))
            c.fx = makeSlots(t.effects)
            Self.automation(t, c.fx)
            engine.attach(c.player); engine.attach(c.pitch); engine.attach(c.eq)
            let fmt = file.processingFormat
            engine.connect(c.player, to: c.pitch, format: fmt)
            engine.connect(c.pitch, to: c.eq, format: fmt)
            // pista → efectos de la pista (en orden, de izquierda a derecha en el rack) → mezclador
            var last: AVAudioNode = c.eq
            for f in c.fx {
                engine.attach(f.node)
                engine.connect(last, to: f.node, format: fmt)
                last = f.node
            }
            engine.connect(last, to: engine.mainMixerNode, format: fmt)
            c.pitch.pitch = Float(t.key_semitones * 100)      // Track Settings › Key Adjustment (cents)
            c.pitch.overlap = 8
            let b = c.eq.bands
            b[0].filterType = .lowShelf; b[0].frequency = 120; b[0].bypass = false
            b[1].filterType = .parametric; b[1].frequency = 1000; b[1].bandwidth = 1.5; b[1].bypass = false
            b[2].filterType = .highShelf; b[2].frequency = 6000; b[2].bypass = false
            for k in 0..<3 { b[k].gain = 0 }
            chains.append(c)
        }
        engine.mainMixerNode.outputVolume = Float(pow(10, doc.master_gain_db / 20))
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
        AudioUnitSetParameter(limiter.audioUnit, kLimiterParam_PreGain, kAudioUnitScope_Global, 0, -1.0, 0)
        return chains.count
    }

    /// Programa los segmentos. El tiempo de cada reproductor cuenta segundos de audio consumido:
    /// antes de que entre la pista, corre a la velocidad de su entrada (se mantiene fija hasta
    /// entonces); después, los segmentos van seguidos.
    func schedule(from: Double) {
        for c in chains {
            let sr = c.file.processingFormat.sampleRate
            let item = c.item
            let segs = item.segments.sorted { $0.mixStart < $1.mixStart }
            guard let first = segs.first else { continue }
            let started = from >= item.mixStart
            let accNow = started ? item.toSource(from) : first.acc
            let idle = started ? 0 : (item.mixStart - from) * item.rate(at: item.mixStart)
            c.pitch.rate = Float(max(1.0 / 32, min(32, item.rate(at: max(from, item.mixStart)))))
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
        for c in chains {
            c.player.stop()
            engine.disconnectNodeOutput(c.player); engine.disconnectNodeOutput(c.pitch); engine.disconnectNodeOutput(c.eq)
            engine.detach(c.player); engine.detach(c.pitch); engine.detach(c.eq)
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
            let seg = item.segments.first { mix >= $0.mixStart && mix < $0.mixEnd } ?? item.segments[0]
            let src = seg.source(item, at: mix)
            let db = Self.value(c.volume, at: src) ?? 0
            c.player.volume = db <= -49.5 ? 0 : Float(pow(10, db / 20))
            c.eq.bands[0].gain = Float(max(-60, min(24, Self.value(c.bass, at: src) ?? 0)))
            c.eq.bands[1].gain = Float(max(-60, min(24, Self.value(c.mid, at: src) ?? 0)))
            c.eq.bands[2].gain = Float(max(-60, min(24, Self.value(c.treble, at: src) ?? 0)))
            if mix >= item.mixStart { c.pitch.rate = Float(max(1.0 / 32, min(32, item.rate(at: mix)))) }
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
        }
        setDevice()
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

    func play(from t: Double) {
        stopNodes()
        let s = Session.shared
        let from = max(0, min(t, max(0, s.layout.total - 0.05)))
        let g = MixGraph(engine: engine, layout: s.layout, doc: s.doc) { e, t in FxPool.shared.node(for: e, type: t) }
        let n = g.build(from: from) { s.audioPath($0) }
        Log.write("play desde \(String(format: "%.2f", from)) s: \(n) pistas con audio de \(s.layout.items.count)")
        guard n > 0 else { pausedAt = from; return }
        setDevice()
        engine.prepare()
        do { try engine.start() } catch { Log.write("ERROR al arrancar el audio: \(error)"); g.teardown(); return }
        g.schedule(from: from)
        g.update(at: from)
        let host = mach_absolute_time() + UInt64(0.08 / Self.ticksToSeconds)
        g.start(at: AVAudioTime(hostTime: host))
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
