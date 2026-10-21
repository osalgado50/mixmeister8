import AVFoundation
import AppKit
import UniformTypeIdentifiers
import MMNEngine

/// Exportar la mezcla (File › Export Playlist to File…, Export Playlist to iTunes…, Burn CD… y
/// los dos botones de arriba a la derecha de la lista, como en el original).
///
/// Se renderiza con el mismo MixGraph que suena en directo, en modo sin conexión (más rápido que
/// tiempo real), por bloques de 1024 muestras: en cada bloque se aplican volumen, EQ y tempo.
enum Exporter {
    enum Kind: Int, CaseIterable {
        case aiff, wav, aac, aiff24, wav24, flac
        var title: String { ["AIFF (16 bits)", "WAV (16 bits)", "AAC (M4A)", "AIFF (24 bits)", "WAV (24 bits)", "FLAC (24 bits, sin pérdida)"][rawValue] }
        var ext: String { ["aif", "wav", "m4a", "aif", "wav", "flac"][rawValue] }
        /// 16 bits: se escribe con dither TPDF (sin él, el redondeo distorsiona los pasajes suaves).
        var is16: Bool { self == .aiff || self == .wav }
        var settings: [String: Any] {
            let sr = Exporter.sampleRate
            switch self {
            case .aiff, .aiff24: return [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sr, AVNumberOfChannelsKey: 2,
                                AVLinearPCMBitDepthKey: self == .aiff ? 16 : 24, AVLinearPCMIsBigEndianKey: true, AVLinearPCMIsFloatKey: false]
            case .wav, .wav24: return [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sr, AVNumberOfChannelsKey: 2,
                               AVLinearPCMBitDepthKey: self == .wav ? 16 : 24, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsFloatKey: false]
            case .aac: return [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sr, AVNumberOfChannelsKey: 2,
                               AVEncoderBitRateKey: 256_000]
            case .flac: return [AVFormatIDKey: kAudioFormatFLAC, AVSampleRateKey: sr, AVNumberOfChannelsKey: 2,
                                AVEncoderBitDepthHintKey: 24]
            }
        }
        /// Espacio aproximado por minuto (como «Estimated Disk Space Required» del original).
        var bytesPerMinute: Double { (self == .aac ? 1.9e6 : self == .flac ? 9.5e6 : (is16 ? 10.6e6 : 15.9e6)) * Exporter.sampleRate / 44100 }
    }
    enum Split: Int { case none, songs, labels }

    /// Frecuencia del render (44,1 o 48 kHz; el CD siempre 44,1). Se fija al empezar cada exportación.
    static var sampleRate = 44100.0

    /// Opciones de exportación nuevas en MixMeister 8.
    struct Options {
        var sampleRate = 44100.0
        /// Normalizar la sonoridad a este valor (LUFS integrados, EBU R128), sin pasar de −1 dBTP.
        var normalize: Double? = nil
    }
    static var lastReport = ""
    /// Aviso para el usuario tras exportar (p. ej. si la normalización ha tenido que limitar mucho).
    static var lastWarning: String?

    /// Mide la sonoridad integrada y el pico real de la mezcla (una pasada de render).
    static func measure(layout: MixLayout, doc: PLDocument, audioPath: @escaping (Int) -> String?,
                        progress: (Double) -> Bool) throws -> (lufs: Double, truePeak: Double) {
        let m = mmn_loud_new(sampleRate, 2)
        defer { mmn_loud_free(m) }
        try render(layout: layout, doc: doc, audioPath: audioPath, progress: progress) { buf, _ in
            guard let ch = buf.floatChannelData else { return }
            mmn_loud_add(m, ch[0], buf.format.channelCount > 1 ? ch[1] : nil, Int32(buf.frameLength))
        }
        return (mmn_loud_integrated(m), mmn_loud_truepeak_db(m))
    }
    /// Ganancia para llegar a `target` LUFS sin pasar de −1 dBTP.
    static func normalizationGain(target: Double, measured: (lufs: Double, truePeak: Double)) -> Double {
        guard measured.lufs.isFinite else { return 1 }
        var g = target - measured.lufs
        if measured.truePeak.isFinite, measured.truePeak + g > -1 { g = -1 - measured.truePeak }
        lastReport = String(format: "medida %.2f LUFS, pico real %.2f dBTP → ganancia %+.2f dB (objetivo %.1f LUFS)", measured.lufs, measured.truePeak, g, target)
        Log.write("normalización: " + lastReport)
        return pow(10, g / 20)
    }
    static func applyGain(_ b: AVAudioPCMBuffer, _ g: Float) {
        guard g != 1, let ch = b.floatChannelData else { return }
        for c in 0..<Int(b.format.channelCount) { for i in 0..<Int(b.frameLength) { ch[c][i] *= g } }
    }

    /// Instantes de corte (s de la mezcla): inicio de cada canción o cada etiqueta.
    static func cuts(_ split: Split, layout: MixLayout, doc: PLDocument) -> [Double] {
        switch split {
        case .none: return [0]
        case .songs:
            return [0] + layout.items.filter { !$0.overlay }.map(\.mixStart).filter { $0 > 0.5 }.sorted()
        case .labels:
            var c: [Double] = [0]
            for it in layout.items where !it.overlay && it.index < doc.tracks.count {
                for m in doc.tracks[it.index].markers(MarkerKind.label) { c.append(it.toMix(Double(m.pos_us) * 1e-6)) }
            }
            return Array(Set(c.map { ($0 * 100).rounded() / 100 })).filter { $0 >= 0 }.sorted()
        }
    }

    /// Renderiza la mezcla. `sink` recibe cada bloque (estéreo, float) y el instante de la mezcla.
    ///
    /// Velocidad: el render sin conexión de AVAudioEngine usa un solo núcleo. En paralelo, cada
    /// pista se renderiza entera en su propio motor (reproductor → tempo → EQ → volumen → efectos de
    /// la pista, exactamente como en el render seguido, sin cortarla nunca) y una pasada final las
    /// suma y aplica los efectos del master y el limitador. `parallel: false` = como antes.
    static var parallelDefault = !CommandLine.arguments.contains("--serial")
    static func render(layout: MixLayout, doc: PLDocument, audioPath: @escaping (Int) -> String?, parallel: Bool = parallelDefault,
                       progress: (Double) -> Bool, sink: (AVAudioPCMBuffer, Double) throws -> Void) throws {
        let total = AVAudioFramePosition((layout.total + 0.5) * sampleRate)
        let items = layout.items.filter { !$0.segments.isEmpty && $0.index < doc.tracks.count && audioPath($0.index) != nil }
        if !parallel || items.count < 2 {
            try renderRange(layout: layout, doc: doc, audioPath: audioPath, from: 0, to: total, preroll: 0,
                            progress: { progress(Double($0) / Double(total)) }, sink: sink)
            return
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mm8-render-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let lock = NSLock()
        // Cada pista: desde justo antes de que entre hasta 6 s después de acabar (colas de efectos).
        struct Stem { let item: MixLayout.Item; let from: AVAudioFramePosition; let to: AVAudioFramePosition; let url: URL }
        let stems = items.map { it -> Stem in
            let a = max(0, AVAudioFramePosition((it.mixStart - 0.05) * sampleRate))
            let b = min(total, AVAudioFramePosition((it.mixEnd + 6) * sampleRate))
            return Stem(item: it, from: a, to: max(a + 1, b), url: tmp.appendingPathComponent("\(it.index).caf"))
        }
        let work = Double(stems.reduce(0) { $0 + $1.to - $1.from })
        var done = [AVAudioFramePosition](repeating: 0, count: stems.count)
        var errors: [Error] = []
        var cancelled = false
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            // Las más largas primero, para que no quede una sola al final.
            let order = stems.indices.sorted { stems[$0].to - stems[$0].from > stems[$1].to - stems[$1].from }
            DispatchQueue.concurrentPerform(iterations: order.count) { k in
                let i = order[k], st = stems[i]
                do {
                    let f = try AVAudioFile(forWriting: st.url, settings: fmt.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
                    try renderRange(layout: layout, doc: doc, audioPath: audioPath, from: st.from, to: st.to, preroll: 0,
                                    only: st.item.index, master: false, progress: { n in
                        lock.lock(); defer { lock.unlock() }
                        done[i] = n
                        return !cancelled
                    }) { buf, _ in try f.write(from: buf) }
                } catch { lock.lock(); errors.append(error); cancelled = true; lock.unlock() }
            }
            group.leave()
        }
        while group.wait(timeout: .now() + 0.2) == .timedOut {
            lock.lock(); let frac = Double(done.reduce(0, +)) / work; lock.unlock()
            if !progress(0.8 * frac) { lock.lock(); cancelled = true; lock.unlock() }
        }
        if cancelled && errors.isEmpty { throw EngineError.message("Cancelado") }
        if let e = errors.first { throw e }

        // Pasada final: las pistas renderizadas, cada una en su muestra de inicio → mezclador →
        // efectos del master → limitador.
        let engine = AVAudioEngine()
        try engine.enableManualRenderingMode(.offline, format: fmt, maximumFrameCount: 1024)
        let g = MixGraph(engine: engine, layout: layout, doc: doc, only: -1, master: true)
        var players: [(AVAudioPlayerNode, AVAudioFile, AVAudioFramePosition)] = []
        for st in stems {
            let f = try AVAudioFile(forReading: st.url, commonFormat: .pcmFormatFloat32, interleaved: false)
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: f.processingFormat)
            players.append((p, f, st.from))
        }
        g.build(from: 0, audioPath: audioPath)
        for (p, f, at) in players { p.scheduleFile(f, at: AVAudioTime(sampleTime: at, atRate: sampleRate)) }
        try engine.start()
        for (p, _, _) in players { p.play(at: nil) }
        defer {
            engine.stop()
            for (p, _, _) in players { engine.disconnectNodeOutput(p); engine.detach(p) }
            g.teardown()
        }
        let buf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 1024)!
        let lat = AVAudioFramePosition(g.latencyFrames), end = total + lat
        var k: AVAudioFramePosition = 0
        while k < end {
            let st = try engine.renderOffline(AVAudioFrameCount(min(1024, end - k)), to: buf)
            guard st == .success else { if st == .error { throw EngineError.message("error al renderizar") }; continue }
            let got = AVAudioFramePosition(buf.frameLength)
            if k + got > lat {
                let skip = AVAudioFrameCount(max(0, lat - k))
                try sink(skip > 0 ? slice(buf, skip, buf.frameLength - skip) : buf, Double(max(0, k - lat)) / sampleRate)
            }
            k += got
            if k % (1024 * 200) < 1024, !progress(0.8 + 0.2 * Double(k) / Double(end)) { throw EngineError.message("Cancelado") }
        }
    }

    /// Renderiza las muestras [from, to) de la mezcla con un motor propio. Empieza `preroll` antes
    /// (y descuenta el retardo del limitador) para que lo entregado sea igual que en un render seguido.
    private static func renderRange(layout: MixLayout, doc: PLDocument, audioPath: @escaping (Int) -> String?,
                                    from: AVAudioFramePosition, to: AVAudioFramePosition, preroll: AVAudioFramePosition,
                                    only: Int? = nil, master: Bool = true,
                                    progress: (AVAudioFramePosition) -> Bool, sink: (AVAudioPCMBuffer, Double) throws -> Void) throws {
        let engine = AVAudioEngine()
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        try engine.enableManualRenderingMode(.offline, format: fmt, maximumFrameCount: 1024)
        let start = max(0, from - preroll)
        let t0 = Double(start) / sampleRate
        let g = MixGraph(engine: engine, layout: layout, doc: doc, only: only, master: master)
        guard g.build(from: t0, audioPath: audioPath) > 0 || from > 0 || only != nil else { throw EngineError.message("No se encuentra el audio de ninguna pista.") }
        g.schedule(from: t0)
        g.update(at: t0)
        try engine.start()
        g.start(at: nil)
        defer { engine.stop(); g.teardown() }   // primero parar: con el motor en marcha no se puede desmontar
        let buf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 1024)!
        // Muestra k del render = instante start + (k − lat) de la mezcla.
        let lat = AVAudioFramePosition(g.latencyFrames)
        let skipTo = (from - start) + lat, end = (to - start) + lat
        var k: AVAudioFramePosition = 0
        while k < end {
            g.update(at: t0 + Double(k) / sampleRate)
            let want = AVAudioFrameCount(min(1024, end - k))
            let st = try engine.renderOffline(want, to: buf)
            guard st == .success else { if st == .error { throw EngineError.message("error al renderizar") }; continue }
            let got = AVAudioFramePosition(buf.frameLength)
            if k + got > skipTo {
                let skip = AVAudioFrameCount(max(0, skipTo - k))
                try sink(skip > 0 ? slice(buf, skip, buf.frameLength - skip) : buf, Double(from + max(0, k - skipTo)) / sampleRate)
            }
            k += got
            if !progress(max(0, k - skipTo)) { throw EngineError.message("Cancelado") }
        }
    }

    /// Exporta a uno o varios ficheros. Devuelve los ficheros escritos.
    static func toFiles(base: URL, kind: Kind, split: Split, options: Options = Options(), progress: (Double) -> Bool) throws -> [URL] {
        let s = Session.shared
        let layout = s.layout, doc = s.doc
        sampleRate = options.sampleRate
        lastReport = ""
        lastWarning = nil
        var gain: Float = 1
        var prog = progress
        defer { MixGraph.exportPreGainDB = 0; MixGraph.exportCeilingDB = nil }
        if let target = options.normalize {
            let path: (Int) -> String? = { s.audioPath($0) }
            let m = try measure(layout: layout, doc: doc, audioPath: path) { progress(0.3 * $0) }
            let g = target - m.lufs
            if g <= 0 || m.truePeak + g <= -1 {
                // Basta con una ganancia limpia después del render.
                gain = Float(normalizationGain(target: target, measured: m))
                prog = { progress(0.3 + 0.7 * $0) }
            } else {
                // Hay que subir más de lo que deja el pico: la ganancia va antes del limitador (techo
                // −1,5 dBFS, para que el pico real no pase de −1 dBTP). El limitador comprime: la sonoridad crece menos que la ganancia, así que se busca la
                // ganancia por la secante (hasta 3 medidas, para al quedar a ±0,2 LU).
                MixGraph.exportCeilingDB = -1.5
                // (la medida inicial se hizo con el limitador normal, así que no entra en la secante: el
                // primer paso usa pendiente 1 y los siguientes, las dos últimas medidas con techo −1,5)
                var prev: (g: Double, l: Double)? = nil
                var g1 = g, l1 = m.lufs
                for k in 0..<3 {
                    MixGraph.exportPreGainDB = g1
                    l1 = try measure(layout: layout, doc: doc, audioPath: path) { progress(0.3 + 0.15 * (Double(k) + $0)) }.lufs
                    Log.write(String(format: "normalización: +%.2f dB antes del limitador → %.2f LUFS", g1, l1))
                    if abs(target - l1) <= 0.2 || !l1.isFinite { break }
                    var slope = 1.0
                    if let p = prev, abs(g1 - p.g) > 0.01 { slope = min(1.5, max(0.05, (l1 - p.l) / (g1 - p.g))) }
                    prev = (g1, l1)
                    let g2 = min(24, max(0, g1 + (target - l1) / slope))
                    g1 = g2
                    MixGraph.exportPreGainDB = g1
                }
                lastReport = String(format: "medida %.2f LUFS (pico real %.2f dBTP); ganancia antes del limitador %+.2f dB (techo −1,5 dBFS) para %.1f LUFS",
                                    m.lufs, m.truePeak, MixGraph.exportPreGainDB, target)
                Log.write("normalización: " + lastReport)
                // Cuánto recorta el limitador (ganancia puesta − sonoridad ganada, ≈ objetivo − medida).
                let squash = MixGraph.exportPreGainDB - (target - m.lufs)
                if squash > 6 {
                    lastWarning = String(format: "Para llegar a %.0f LUFS el limitador ha tenido que recortar unos %.0f dB los picos, porque los de la mezcla ya estaban casi al máximo (%.1f LUFS con pico real %.1f dBTP). Puede sonar aplastada; con un objetivo más bajo conservará la pegada.", target, squash, m.lufs, m.truePeak)
                    Log.write("normalización: aviso, limitación de \(String(format: "%.1f", squash)) dB")
                }
                prog = { progress(0.75 + 0.25 * $0) }
            }
        }
        let cuts = Self.cuts(split, layout: layout, doc: doc)
        let stem = base.deletingPathExtension().lastPathComponent
        let dir = base.deletingLastPathComponent()
        var urls: [URL] = []
        var file: AVAudioFile?
        var next = 1
        func open(_ i: Int) throws {
            let name = cuts.count > 1 ? String(format: "%@ %02d.%@", stem, i, kind.ext) : "\(stem).\(kind.ext)"
            let u = dir.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: u)
            file = try AVAudioFile(forWriting: u, settings: kind.settings, commonFormat: kind.is16 ? .pcmFormatInt16 : .pcmFormatFloat32, interleaved: false)
            urls.append(u)
        }
        try open(1)
        var dither = Dither()
        try render(layout: layout, doc: doc, audioPath: { s.audioPath($0) }, progress: prog) { fbuf, t in
            applyGain(fbuf, gain)
            let buf = kind.is16 ? dither.toInt16(fbuf) : fbuf
            // ¿Hay un corte dentro de este bloque?
            let len = Double(buf.frameLength) / sampleRate
            if next < cuts.count, cuts[next] < t + len {
                let k = AVAudioFrameCount(max(0, min(Double(buf.frameLength), (cuts[next] - t) * sampleRate)))
                if k > 0 { try file?.write(from: slice(buf, 0, k)) }
                next += 1
                try open(next)
                if k < buf.frameLength { try file?.write(from: slice(buf, k, buf.frameLength - k)) }
            } else {
                try file?.write(from: buf)
            }
        }
        file = nil
        return urls
    }

    static func slice(_ b: AVAudioPCMBuffer, _ from: AVAudioFrameCount, _ count: AVAudioFrameCount) -> AVAudioPCMBuffer {
        let out = AVAudioPCMBuffer(pcmFormat: b.format, frameCapacity: count)!
        out.frameLength = count
        for c in 0..<Int(b.format.channelCount) {
            if let f = b.floatChannelData, let o = out.floatChannelData {
                memcpy(o[c], f[c] + Int(from), Int(count) * MemoryLayout<Float>.size)
            } else if let f = b.int16ChannelData, let o = out.int16ChannelData {
                memcpy(o[c], f[c] + Int(from), Int(count) * MemoryLayout<Int16>.size)
            }
        }
        return out
    }

    /// Imagen de CD de audio sin pausas: un BIN (PCM 16 bits, 44,1 kHz) y su CUE con una pista en
    /// cada corte, alineada a sectores de CD (588 muestras = 1/75 s).
    static func cdImage(dir: URL, split: Split, progress: (Double) -> Bool) throws -> URL {
        let s = Session.shared
        let layout = s.layout, doc = s.doc
        sampleRate = 44100
        if layout.total > 80 * 60 { throw EngineError.message(String(format: "La mezcla dura %d:%02d y no cabe en un CD (máximo 80 minutos).", Int(layout.total) / 60, Int(layout.total) % 60)) }
        let bin = dir.appendingPathComponent("mezcla.bin"), cue = dir.appendingPathComponent("mezcla.cue")
        FileManager.default.createFile(atPath: bin.path, contents: nil)
        let h = try FileHandle(forWritingTo: bin)
        defer { try? h.close() }
        var pcm = [Int16]()
        var dither = Dither()
        try render(layout: layout, doc: doc, audioPath: { s.audioPath($0) }, progress: progress) { buf, _ in
            let n = Int(buf.frameLength)
            pcm.removeAll(keepingCapacity: true)
            let l = buf.floatChannelData![0], r = buf.floatChannelData![1]
            for i in 0..<n {
                pcm.append(dither.sample(l[i]).littleEndian)
                pcm.append(dither.sample(r[i]).littleEndian)
            }
            pcm.withUnsafeBytes { h.write(Data($0)) }
        }
        // Rellenar hasta sector completo (2352 bytes).
        let size = (try? FileManager.default.attributesOfItem(atPath: bin.path)[.size] as? Int) ?? 0
        if size % 2352 != 0 { h.write(Data(count: 2352 - size % 2352)) }
        var text = "FILE \"mezcla.bin\" BINARY\n"
        let names = layout.items.filter { !$0.overlay }.sorted { $0.mixStart < $1.mixStart }.map { doc.tracks[$0.index].title }
        for (i, c) in cuts(split, layout: layout, doc: doc).prefix(99).enumerated() {
            let frames = Int((c * 75).rounded())
            text += String(format: "  TRACK %02d AUDIO\n", i + 1)
            if split == .songs, i < names.count { text += "    TITLE \"\(names[i].replacingOccurrences(of: "\"", with: "'"))\"\n" }
            text += String(format: "    INDEX 01 %02d:%02d:%02d\n", frames / 75 / 60, (frames / 75) % 60, frames % 75)
        }
        try text.write(to: cue, atomically: true, encoding: .utf8)
        return cue
    }

    /// ¿Hay grabadora? (drutil list)
    static func burner() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/drutil")
        p.arguments = ["list"]
        let pipe = Pipe()
        p.standardOutput = pipe
        try? p.run()
        p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let lines = out.split(separator: "\n").dropFirst()
        return lines.first.map { $0.split(separator: " ").filter { !$0.isEmpty }.prefix(3).joined(separator: " ") }
    }
}

// MARK: - Diálogos (los del original: FileOrDeviceDlg, SavePlaylistAudio, CdBurnerDlg, ProgressStatus)

final class ExportUI: NSObject {
    static let shared = ExportUI()
    private var progressWindow: NSPanel?
    private var bar: NSProgressIndicator?
    private var cancelled = false

    /// Botón «Export playlist to a file or iTunes»: FileOrDeviceDlg.
    func chooseFileOrDevice() {
        let a = NSAlert()
        a.messageText = "What would you like to do?"
        let m = NSMatrixLike(["Export my playlist to one or more files", "Export my playlist to iTunes"])
        a.accessoryView = m.view
        a.addButton(withTitle: "Continue")
        a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        m.selected == 0 ? exportToFile() : exportToMusic()
    }

    /// File › Export Playlist to File…: guardar con tipo, formato y separación (SavePlaylistAudio).
    func exportToFile() {
        guard ready() else { return }
        let p = NSSavePanel()
        p.nameFieldStringValue = (Session.shared.title as NSString).deletingPathExtension
        let acc = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 156))
        let typeL = NSTextField(labelWithString: "Save as type:"); typeL.frame = NSRect(x: 10, y: 126, width: 120, height: 18)
        let type = NSPopUpButton(frame: NSRect(x: 135, y: 122, width: 230, height: 26)); type.addItems(withTitles: Exporter.Kind.allCases.map(\.title))
        let d = UserDefaults.standard
        type.selectItem(at: d.integer(forKey: "MM8 Export Kind"))
        // Nuevo en MixMeister 8: frecuencia y normalización de sonoridad.
        let srL = NSTextField(labelWithString: "Sample rate:"); srL.frame = NSRect(x: 10, y: 96, width: 120, height: 18)
        let sr = NSPopUpButton(frame: NSRect(x: 135, y: 92, width: 230, height: 26)); sr.addItems(withTitles: ["44,1 kHz (CD)", "48 kHz (vídeo)"])
        sr.selectItem(at: d.double(forKey: "MM8 Export Rate") == 48000 ? 1 : 0)
        let nL = NSTextField(labelWithString: "Normalize:"); nL.frame = NSRect(x: 10, y: 66, width: 120, height: 18)
        let norm = NSPopUpButton(frame: NSRect(x: 135, y: 62, width: 230, height: 26))
        norm.addItems(withTitles: Self.normTargets.map(\.0))
        norm.selectItem(at: d.integer(forKey: "MM8 Export Normalize"))
        sr.target = self; sr.action = #selector(typeChanged); ratePop = sr
        let splitB = NSButton(checkboxWithTitle: "Create separate files for:", target: nil, action: nil); splitB.frame = NSRect(x: 10, y: 36, width: 200, height: 20)
        let which = NSMatrixLike(["Each song", "Each track using label markers"]); which.view.frame.origin = NSPoint(x: 210, y: 6)
        let size = NSTextField(labelWithString: ""); size.frame = NSRect(x: 10, y: 6, width: 200, height: 18); size.textColor = .secondaryLabelColor
        typePop = type; sizeLabel = size; panel = p
        type.target = self; type.action = #selector(typeChanged)
        [typeL, type, srL, sr, nL, norm, splitB, which.view, size].forEach { acc.addSubview($0) }
        p.accessoryView = acc
        p.allowsOtherFileTypes = true
        typeChanged()
        guard p.runModal() == .OK, let url = p.url else { return }
        let kind = Exporter.Kind(rawValue: type.indexOfSelectedItem) ?? .aiff
        let split: Exporter.Split = splitB.state == .on ? (which.selected == 0 ? .songs : .labels) : .none
        var opt = Exporter.Options()
        opt.sampleRate = sr.indexOfSelectedItem == 1 ? 48000 : 44100
        opt.normalize = Self.normTargets[max(0, norm.indexOfSelectedItem)].1
        d.set(type.indexOfSelectedItem, forKey: "MM8 Export Kind")
        d.set(opt.sampleRate, forKey: "MM8 Export Rate")
        d.set(norm.indexOfSelectedItem, forKey: "MM8 Export Normalize")
        run(opt.normalize == nil ? "Exportando la mezcla…" : "Midiendo la sonoridad y exportando…",
            work: { prog in try Exporter.toFiles(base: url, kind: kind, split: split, options: opt, progress: prog) }) { urls in
            NSWorkspace.shared.activateFileViewerSelecting(urls)
            if let w = Exporter.lastWarning {
                let a = NSAlert()
                a.messageText = "Exportación terminada, con aviso de sonoridad"
                a.informativeText = w
                a.runModal()
            }
        }
    }
    private weak var typePop: NSPopUpButton?
    private weak var ratePop: NSPopUpButton?
    static let normTargets: [(String, Double?)] = [("No", nil), ("−14 LUFS (streaming)", -14), ("−11 LUFS", -11), ("−9 LUFS (club)", -9), ("−16 LUFS (podcast)", -16)]
    private weak var sizeLabel: NSTextField?
    private weak var panel: NSSavePanel?
    @objc private func typeChanged() {
        let k = Exporter.Kind(rawValue: typePop?.indexOfSelectedItem ?? 0) ?? .aiff
        Exporter.sampleRate = ratePop?.indexOfSelectedItem == 1 ? 48000 : 44100
        panel?.allowedContentTypes = [UTType(filenameExtension: k.ext) ?? .audio]
        sizeLabel?.stringValue = String(format: "Estimated Disk Space Required: %.0f MB", Session.shared.layout.total / 60 * k.bytesPerMinute / 1e6)
    }

    /// File › Export Playlist to iTunes…: SaveToDevice (artista y título) y se añade a Música.
    func exportToMusic() {
        guard ready() else { return }
        let a = NSAlert()
        a.messageText = "Name your mix for iTunes:"
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 56))
        let artist = NSTextField(frame: NSRect(x: 60, y: 30, width: 260, height: 22)); artist.stringValue = "MixMeister 8"
        let title = NSTextField(frame: NSRect(x: 60, y: 2, width: 260, height: 22)); title.stringValue = (Session.shared.title as NSString).deletingPathExtension
        let l1 = NSTextField(labelWithString: "Artist:"); l1.frame = NSRect(x: 0, y: 32, width: 58, height: 18)
        let l2 = NSTextField(labelWithString: "Title:"); l2.frame = NSRect(x: 0, y: 4, width: 58, height: 18)
        [artist, title, l1, l2].forEach { v.addSubview($0) }
        a.accessoryView = v
        a.addButton(withTitle: "Save"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MixMeister8-export-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let base = dir.appendingPathComponent("\(artist.stringValue) - \(title.stringValue).m4a")
        run("Preparando la mezcla para Música…", work: { prog in try Exporter.toFiles(base: base, kind: .aac, split: .none, progress: prog) }) { urls in
            for u in urls {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                p.arguments = ["-a", "Music", u.path]
                try? p.run()
            }
        }
    }

    /// File › Burn CD… y el botón «Burn Playlist onto an Audio CD» (CdBurnerDlg).
    func burnCD() {
        guard ready() else { return }
        let L = Session.shared.layout
        let a = NSAlert()
        a.messageText = "Burn Playlist onto an Audio CD"
        a.informativeText = String(format: "Duración de la mezcla: %d:%02d (cabe en un CD de 80 min si no pasa de 80:00).\nInserta un CD-R en blanco.", Int(L.total) / 60, Int(L.total) % 60)
        let m = NSMatrixLike(["Automatically split into tracks", "Split into tracks at Label Markers"])
        let l = NSTextField(labelWithString: "Layout Options:"); l.frame = NSRect(x: 0, y: 50, width: 200, height: 18)
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 70)); v.addSubview(l); v.addSubview(m.view)
        a.accessoryView = v
        a.addButton(withTitle: "Continue"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let split: Exporter.Split = m.selected == 0 ? .songs : .labels
        guard let drive = Exporter.burner() else {
            let e = NSAlert()
            e.messageText = "No hay ninguna grabadora de CD conectada"
            e.informativeText = "Conecta una grabadora de CD/DVD (por ejemplo, una externa USB) y vuelve a intentarlo. Si quieres, puedo dejarte la imagen del CD (CUE/BIN) para grabarla después."
            e.addButton(withTitle: "Guardar imagen CUE/BIN…"); e.addButton(withTitle: "Cancel")
            if e.runModal() == .alertFirstButtonReturn {
                let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true; p.prompt = "Guardar aquí"
                guard p.runModal() == .OK, let dir = p.url else { return }
                run("Creando la imagen del CD…", work: { prog in [try Exporter.cdImage(dir: dir, split: split, progress: prog)] }) { urls in
                    NSWorkspace.shared.activateFileViewerSelecting(urls)
                }
            }
            return
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MixMeister8-cd-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        run("Preparando el CD (\(drive))…", work: { prog in [try Exporter.cdImage(dir: dir, split: split, progress: prog)] }) { urls in
            guard let cue = urls.first else { return }
            self.run("Grabando el CD…", work: { _ in
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/drutil")
                p.arguments = ["burn", "-noverify", "-eject", cue.path]
                let err = Pipe(); p.standardError = err; p.standardOutput = err
                try p.run(); p.waitUntilExit()
                try? FileManager.default.removeItem(at: dir)          // como el original: borra los temporales
                if p.terminationStatus != 0 { throw EngineError.message(String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)) }
                return [cue]
            }) { _ in
                let ok = NSAlert(); ok.messageText = "CD grabado"; ok.runModal()
            }
        }
    }

    private func ready() -> Bool {
        if Session.shared.doc.tracks.isEmpty {
            let a = NSAlert(); a.messageText = "La lista está vacía"; a.runModal(); return false
        }
        Player.shared.pause()
        return true
    }

    /// Ventana de progreso con Cancel (ProgressStatus del original); el trabajo va en segundo plano.
    private func run(_ text: String, work: @escaping ((Double) -> Bool) throws -> [URL], done: @escaping ([URL]) -> Void) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 110), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Status"
        let l = NSTextField(labelWithString: text); l.frame = NSRect(x: 20, y: 70, width: 340, height: 18)
        let b = NSProgressIndicator(frame: NSRect(x: 20, y: 44, width: 340, height: 20)); b.isIndeterminate = false; b.maxValue = 1
        let c = NSButton(title: "Cancel", target: self, action: #selector(cancel)); c.frame = NSRect(x: 280, y: 8, width: 80, height: 28)
        [l, b, c].forEach { panel.contentView?.addSubview($0) }
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        progressWindow = panel; bar = b; cancelled = false
        DispatchQueue.global(qos: .userInitiated).async {
            let t0 = Date()
            do {
                let urls = try work { f in
                    DispatchQueue.main.async { self.bar?.doubleValue = f }
                    return !self.cancelled
                }
                Log.write("\(text) hecho en \(String(format: "%.1f", Date().timeIntervalSince(t0))) s → \(urls.map(\.lastPathComponent))")
                DispatchQueue.main.async { panel.orderOut(nil); done(urls) }
            } catch {
                Log.write("\(text) ERROR: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    panel.orderOut(nil)
                    if !self.cancelled { let a = NSAlert(); a.messageText = "No se pudo terminar"; a.informativeText = error.localizedDescription; a.runModal() }
                }
            }
        }
    }
    @objc private func cancel() { cancelled = true }
}

/// Grupo de botones de opción (los NSMatrix de radio del original).
final class NSMatrixLike: NSObject {
    let view: NSView
    private var buttons: [NSButton] = []
    var selected: Int { buttons.firstIndex { $0.state == .on } ?? 0 }
    init(_ titles: [String]) {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: CGFloat(titles.count) * 22 + 4))
        super.init()
        for (i, t) in titles.enumerated() {
            let b = NSButton(radioButtonWithTitle: t, target: self, action: #selector(pick(_:)))
            b.frame = NSRect(x: 0, y: CGFloat(titles.count - 1 - i) * 22 + 2, width: 320, height: 20)
            b.state = i == 0 ? .on : .off
            view.addSubview(b)
            buttons.append(b)
        }
    }
    @objc private func pick(_ s: NSButton) { for b in buttons { b.state = b === s ? .on : .off } }
}

/// Paso a 16 bits con dither TPDF (±1 LSB, ruido triangular) y redondeo: el error de cuantización
/// queda como ruido blanco a −96 dB en lugar de distorsión ligada a la señal.
struct Dither {
    private var state: UInt64 = 0x9E37_79B9_7F4A_7C15
    private mutating func rand() -> Float {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Float(state >> 40) / Float(1 << 24)       // 0..1
    }
    mutating func sample(_ x: Float) -> Int16 {
        let v = max(-1, min(1, x)) * 32767 + (rand() - rand())
        return Int16(max(-32768, min(32767, v.rounded())))
    }
    mutating func toInt16(_ b: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        let fmt = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: b.format.sampleRate, channels: b.format.channelCount, interleaved: false)!
        let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: b.frameLength)!
        out.frameLength = b.frameLength
        guard let src = b.floatChannelData, let dst = out.int16ChannelData else { return out }
        for c in 0..<Int(b.format.channelCount) { for i in 0..<Int(b.frameLength) { dst[c][i] = sample(src[c][i]) } }
        return out
    }
}
