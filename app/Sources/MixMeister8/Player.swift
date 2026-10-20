import AVFoundation
import AppKit
import AudioToolbox

extension Notification.Name {
    static let playerTick = Notification.Name("mm8.playerTick")
    static let playerState = Notification.Name("mm8.playerState")
}

/// Reproducción de la mezcla en tiempo real.
///
/// Cada pista es una cadena reproductor → cambio de tempo sin cambio de tono → ecualizador de 3
/// bandas → mezclador. Los segmentos se programan en el instante de la mezcla que les da
/// MixLayout; la envolvente de volumen (marcadores automáticos y manuales) y los marcadores de
/// graves/medios/agudos se aplican 60 veces por segundo según la posición de cada pista.
final class Player {
    static let shared = Player()

    private let engine = AVAudioEngine()
    private struct Chain {
        let index: Int
        let player = AVAudioPlayerNode()
        let pitch = AVAudioUnitTimePitch()
        let eq = AVAudioUnitEQ(numberOfBands: 3)
        let file: AVAudioFile
        let item: MixLayout.Item
        let volume: [(t: Double, db: Double)]      // por posición en el audio (s)
        let bass: [(t: Double, db: Double)], mid: [(t: Double, db: Double)], treble: [(t: Double, db: Double)]
    }
    private var chains: [Chain] = []
    private var startHost: UInt64 = 0
    private var startMix: Double = 0
    private var timer: Timer?
    private(set) var isPlaying = false
    private var pausedAt: Double = 0
    var peakL: Float = 0, peakR: Float = 0

    // Preescucha de la biblioteca (Preview Song / Stop Previewing)
    private var preview: AVAudioPlayer?

    /// Posición actual en la mezcla (s).
    var position: Double {
        guard isPlaying else { return pausedAt }
        let now = mach_absolute_time()
        return startMix + Double(now &- startHost) * Self.ticksToSeconds
    }
    private static let ticksToSeconds: Double = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return Double(tb.numer) / Double(tb.denom) / 1e9
    }()

    init() {
        let mixer = engine.mainMixerNode
        defer { applyOutputDevice() }
        mixer.installTap(onBus: 0, bufferSize: 1024, format: mixer.outputFormat(forBus: 0)) { [weak self] buf, _ in
            guard let self, let ch = buf.floatChannelData else { return }
            let n = Int(buf.frameLength)
            var l: Float = 0, r: Float = 0
            for i in 0..<n { l = max(l, abs(ch[0][i])) }
            if buf.format.channelCount > 1 { for i in 0..<n { r = max(r, abs(ch[1][i])) } } else { r = l }
            self.peakL = max(l, self.peakL * 0.85)
            self.peakR = max(r, self.peakR * 0.85)
        }
    }

    // MARK: Salida

    /// Envía el audio a la salida elegida en Audio Output Configuration (o la del sistema).
    func applyOutputDevice() {
        let wasPlaying = isPlaying, at = position
        if wasPlaying { stopNodes() }
        engine.stop()
        if let dev = OutputConfig.main(), let au = engine.outputNode.audioUnit {
            var id = dev.id
            let rc = AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
            NSLog("MixMeister 8: salida «\(dev.name)» (\(rc == noErr ? "ok" : "error \(rc)"))")
        }
        if wasPlaying { play(from: at) }
    }
    var outputName: String { OutputConfig.main()?.name ?? "—" }

    // MARK: Transporte

    func toggle(from t: Double? = nil) { isPlaying ? pause() : play(from: t ?? pausedAt) }

    func play(from t: Double) {
        stopNodes()
        let s = Session.shared
        let L = s.layout
        let from = max(0, min(t, max(0, L.total - 0.05)))
        engine.mainMixerNode.outputVolume = Float(pow(10, s.doc.master_gain_db / 20))
        // Cadenas solo para las pistas que aún tienen algo que sonar.
        for item in L.items where item.mixEnd > from {
            guard item.index < s.doc.tracks.count, let path = s.audioPath(item.index),
                  let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) else { continue }
            let t = s.doc.tracks[item.index]
            func env(_ kinds: [UInt32]) -> [(t: Double, db: Double)] {
                t.markers.filter { kinds.contains($0.type) }.map { (Double($0.pos_us) * 1e-6, $0.value) }.sorted { $0.t < $1.t }
            }
            let c = Chain(index: item.index, file: file, item: item,
                          volume: env([MarkerKind.volume, MarkerKind.autoVolume, MarkerKind.autoVolumeIn]),
                          bass: env([MarkerKind.bass]), mid: env([MarkerKind.mid]), treble: env([MarkerKind.treble]))
            engine.attach(c.player); engine.attach(c.pitch); engine.attach(c.eq)
            let fmt = file.processingFormat
            engine.connect(c.player, to: c.pitch, format: fmt)
            engine.connect(c.pitch, to: c.eq, format: fmt)
            engine.connect(c.eq, to: engine.mainMixerNode, format: fmt)
            c.pitch.rate = Float(max(1.0 / 32, min(32, item.rate)))
            c.pitch.pitch = Float(t.key_semitones * 100)   // Key Adjustment, en cents
            let b = c.eq.bands
            b[0].filterType = .lowShelf; b[0].frequency = 120; b[0].bypass = false
            b[1].filterType = .parametric; b[1].frequency = 1000; b[1].bandwidth = 1.5; b[1].bypass = false
            b[2].filterType = .highShelf; b[2].frequency = 6000; b[2].bypass = false
            for k in 0..<3 { b[k].gain = 0 }
            chains.append(c)
        }
        guard !chains.isEmpty else { pausedAt = from; return }
        do { if !engine.isRunning { try engine.start() } } catch { NSLog("MixMeister 8: audio: \(error)"); return }

        // Programación: el tiempo del reproductor corre a `rate` veces el tiempo real.
        for c in chains {
            let sr = c.file.processingFormat.sampleRate
            for seg in c.item.segments where seg.mixEnd > from {
                let wallStart = max(0, seg.mixStart - from)                 // s desde ahora
                let srcFrom = seg.srcStart + max(0, from - seg.mixStart) * c.item.rate
                let startFrame = AVAudioFramePosition(max(0, srcFrom) * sr)
                let endFrame = min(c.file.length, AVAudioFramePosition(seg.srcEnd * sr))
                guard endFrame > startFrame else { continue }
                let when = AVAudioTime(sampleTime: AVAudioFramePosition(wallStart * c.item.rate * sr), atRate: sr)
                c.player.scheduleSegment(c.file, startingFrame: startFrame, frameCount: AVAudioFrameCount(endFrame - startFrame), at: when)
            }
        }
        let lead = 0.08
        let host = mach_absolute_time() + UInt64(lead / Self.ticksToSeconds)
        let at = AVAudioTime(hostTime: host)
        applyEnvelopes(at: from)
        for c in chains { c.player.play(at: at) }
        startHost = host
        startMix = from
        isPlaying = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        NotificationCenter.default.post(name: .playerState, object: nil)
    }

    func pause() {
        pausedAt = position
        stopNodes()
        NotificationCenter.default.post(name: .playerState, object: nil)
        NotificationCenter.default.post(name: .playerTick, object: nil)
    }

    func stop() {
        stopNodes()
        pausedAt = 0
        NotificationCenter.default.post(name: .playerState, object: nil)
        NotificationCenter.default.post(name: .playerTick, object: nil)
    }

    /// Mover el cursor: si está sonando, sigue sonando desde ahí.
    func seek(_ t: Double) {
        if isPlaying { play(from: t) } else { pausedAt = max(0, t); NotificationCenter.default.post(name: .playerTick, object: nil) }
    }

    private func stopNodes() {
        timer?.invalidate(); timer = nil
        for c in chains {
            c.player.stop()
            engine.disconnectNodeOutput(c.player); engine.disconnectNodeOutput(c.pitch); engine.disconnectNodeOutput(c.eq)
            engine.detach(c.player); engine.detach(c.pitch); engine.detach(c.eq)
        }
        chains.removeAll()
        isPlaying = false
        peakL = 0; peakR = 0
    }

    private func tick() {
        let p = position
        if p >= Session.shared.layout.total + 0.5 { stop(); return }
        applyEnvelopes(at: p)
        NotificationCenter.default.post(name: .playerTick, object: nil)
    }

    // MARK: Envolventes

    private static func value(_ env: [(t: Double, db: Double)], at t: Double) -> Double? {
        guard let first = env.first else { return nil }
        if t <= first.t { return first.db }
        for i in 1..<env.count where t < env[i].t {
            let a = env[i - 1], b = env[i]
            let u = (t - a.t) / max(1e-9, b.t - a.t)
            return a.db + (b.db - a.db) * u
        }
        return env.last!.db
    }

    private func applyEnvelopes(at mix: Double) {
        for c in chains {
            let src = c.item.toSource(mix)
            let db = Self.value(c.volume, at: src) ?? 0
            c.player.volume = db <= -49.5 ? 0 : Float(pow(10, db / 20))
            c.eq.bands[0].gain = Float(max(-60, min(24, Self.value(c.bass, at: src) ?? 0)))
            c.eq.bands[1].gain = Float(max(-60, min(24, Self.value(c.mid, at: src) ?? 0)))
            c.eq.bands[2].gain = Float(max(-60, min(24, Self.value(c.treble, at: src) ?? 0)))
        }
    }

    // MARK: Preescucha

    func previewPlay(path: String) {
        preview?.stop()
        preview = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
        preview?.play()
    }
    func previewStop() { preview?.stop(); preview = nil }
    var isPreviewing: Bool { preview?.isPlaying ?? false }
}
