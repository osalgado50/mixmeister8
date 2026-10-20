import AVFoundation
import AppKit
import UniformTypeIdentifiers

/// Exportar la mezcla (File › Export Playlist to File…, Export Playlist to iTunes…, Burn CD… y
/// los dos botones de arriba a la derecha de la lista, como en el original).
///
/// Se renderiza con el mismo MixGraph que suena en directo, en modo sin conexión (más rápido que
/// tiempo real), por bloques de 1024 muestras: en cada bloque se aplican volumen, EQ y tempo.
enum Exporter {
    enum Kind: Int, CaseIterable {
        case aiff, wav, aac
        var title: String { ["AIFF", "WAV", "AAC (M4A)"][rawValue] }
        var ext: String { ["aif", "wav", "m4a"][rawValue] }
        var settings: [String: Any] {
            switch self {
            case .aiff: return [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2,
                                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsBigEndianKey: true, AVLinearPCMIsFloatKey: false]
            case .wav: return [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2,
                               AVLinearPCMBitDepthKey: 16, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsFloatKey: false]
            case .aac: return [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2,
                               AVEncoderBitRateKey: 256_000]
            }
        }
        /// Espacio aproximado por minuto (como «Estimated Disk Space Required» del original).
        var bytesPerMinute: Double { self == .aac ? 1.9e6 : 10.6e6 }
    }
    enum Split: Int { case none, songs, labels }

    static let sampleRate = 44100.0

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
    static func render(layout: MixLayout, doc: PLDocument, audioPath: (Int) -> String?,
                       progress: (Double) -> Bool, sink: (AVAudioPCMBuffer, Double) throws -> Void) throws {
        let engine = AVAudioEngine()
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        try engine.enableManualRenderingMode(.offline, format: fmt, maximumFrameCount: 1024)
        let g = MixGraph(engine: engine, layout: layout, doc: doc)
        guard g.build(from: 0, audioPath: audioPath) > 0 else { throw EngineError.message("No se encuentra el audio de ninguna pista.") }
        g.schedule(from: 0)
        g.update(at: 0)
        try engine.start()
        g.start(at: nil)
        defer { engine.stop(); g.teardown() }   // primero parar: con el motor en marcha no se puede desmontar
        let buf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 1024)!
        let totalFrames = AVAudioFramePosition((layout.total + 0.5) * sampleRate)
        var done: AVAudioFramePosition = 0
        while done < totalFrames {
            let t = Double(done) / sampleRate
            g.update(at: t)
            let n = AVAudioFrameCount(min(1024, totalFrames - done))
            let st = try engine.renderOffline(n, to: buf)
            guard st == .success else { if st == .error { throw EngineError.message("error al renderizar") }; continue }
            try sink(buf, t)
            done += AVAudioFramePosition(buf.frameLength)
            if !progress(Double(done) / Double(totalFrames)) { throw EngineError.message("Cancelado") }
        }
    }

    /// Exporta a uno o varios ficheros. Devuelve los ficheros escritos.
    static func toFiles(base: URL, kind: Kind, split: Split, progress: (Double) -> Bool) throws -> [URL] {
        let s = Session.shared
        let layout = s.layout, doc = s.doc
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
            file = try AVAudioFile(forWriting: u, settings: kind.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            urls.append(u)
        }
        try open(1)
        try render(layout: layout, doc: doc, audioPath: { s.audioPath($0) }, progress: progress) { buf, t in
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
            memcpy(out.floatChannelData![c], b.floatChannelData![c] + Int(from), Int(count) * MemoryLayout<Float>.size)
        }
        return out
    }

    /// Imagen de CD de audio sin pausas: un BIN (PCM 16 bits, 44,1 kHz) y su CUE con una pista en
    /// cada corte, alineada a sectores de CD (588 muestras = 1/75 s).
    static func cdImage(dir: URL, split: Split, progress: (Double) -> Bool) throws -> URL {
        let s = Session.shared
        let layout = s.layout, doc = s.doc
        if layout.total > 80 * 60 { throw EngineError.message(String(format: "La mezcla dura %d:%02d y no cabe en un CD (máximo 80 minutos).", Int(layout.total) / 60, Int(layout.total) % 60)) }
        let bin = dir.appendingPathComponent("mezcla.bin"), cue = dir.appendingPathComponent("mezcla.cue")
        FileManager.default.createFile(atPath: bin.path, contents: nil)
        let h = try FileHandle(forWritingTo: bin)
        defer { try? h.close() }
        var pcm = [Int16]()
        try render(layout: layout, doc: doc, audioPath: { s.audioPath($0) }, progress: progress) { buf, _ in
            let n = Int(buf.frameLength)
            pcm.removeAll(keepingCapacity: true)
            let l = buf.floatChannelData![0], r = buf.floatChannelData![1]
            for i in 0..<n {
                pcm.append(Int16(max(-1, min(1, l[i])) * 32767).littleEndian)
                pcm.append(Int16(max(-1, min(1, r[i])) * 32767).littleEndian)
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
        let acc = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 96))
        let typeL = NSTextField(labelWithString: "Save as type:"); typeL.frame = NSRect(x: 10, y: 66, width: 120, height: 18)
        let type = NSPopUpButton(frame: NSRect(x: 135, y: 62, width: 180, height: 26)); type.addItems(withTitles: Exporter.Kind.allCases.map(\.title))
        let splitB = NSButton(checkboxWithTitle: "Create separate files for:", target: nil, action: nil); splitB.frame = NSRect(x: 10, y: 36, width: 200, height: 20)
        let which = NSMatrixLike(["Each song", "Each track using label markers"]); which.view.frame.origin = NSPoint(x: 210, y: 6)
        let size = NSTextField(labelWithString: ""); size.frame = NSRect(x: 10, y: 6, width: 200, height: 18); size.textColor = .secondaryLabelColor
        typePop = type; sizeLabel = size; panel = p
        type.target = self; type.action = #selector(typeChanged)
        [typeL, type, splitB, which.view, size].forEach { acc.addSubview($0) }
        p.accessoryView = acc
        p.allowsOtherFileTypes = true
        typeChanged()
        guard p.runModal() == .OK, let url = p.url else { return }
        let kind = Exporter.Kind(rawValue: type.indexOfSelectedItem) ?? .aiff
        let split: Exporter.Split = splitB.state == .on ? (which.selected == 0 ? .songs : .labels) : .none
        run("Exportando la mezcla…", work: { prog in try Exporter.toFiles(base: url, kind: kind, split: split, progress: prog) }) { urls in
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }
    private weak var typePop: NSPopUpButton?
    private weak var sizeLabel: NSTextField?
    private weak var panel: NSSavePanel?
    @objc private func typeChanged() {
        let k = Exporter.Kind(rawValue: typePop?.indexOfSelectedItem ?? 0) ?? .aiff
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
