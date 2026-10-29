import AppKit
import UniformTypeIdentifiers
import AVFoundation
import MMNEngine

/// Arranque, ventana principal y las acciones de los menús. Los selectores son los mismos que los
/// del original (openPlayList:, view4Strips:, snapToBeat:…), así los menús generados del nib
/// encuentran su acción sin traducción.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation, NSMenuDelegate {
    var window: NSWindow!
    let library = LibraryPane()
    let playlist = PlaylistPane()
    let timelinePane = TimelinePane()
    let bottom = BottomPane()
    private let topSplit = NSSplitView()
    private let mainSplit = NSSplitView()
    private var snapOn = UserDefaults.standard.object(forKey: "Snap To Beat") as? Bool ?? true
    private var snapType = UserDefaults.standard.object(forKey: "Snap Position Type") as? Int ?? 1
    var session: Session { .shared }
    static let mmpType = UTType(filenameExtension: "mmp") ?? .data

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.appearance = NSAppearance(named: Theme.skin.dark ? .darkAqua : .aqua)
        FxCatalog.registerDSP()
        buildMenus()
        buildWindow()
        playlist.stopButton.target = self
        playlist.table.target = self
        playlist.table.doubleAction = #selector(playFromPlaylistRow(_:))
        session.loadLibrary()
        session.newPlaylist()
        var recovered = false
        if !testMode, FileManager.default.fileExists(atPath: Session.recoveryURL.path) {
            let a = NSAlert()
            let src = UserDefaults.standard.string(forKey: Session.recoverySourceKey) ?? ""
            a.messageText = "MixMeister 8 se cerró sin guardar los cambios"
            a.informativeText = "Hay una copia de recuperación de «\(src.isEmpty ? "untitled" : (src as NSString).lastPathComponent)». ¿Quieres recuperarla?"
            a.addButton(withTitle: "Recuperar")
            a.addButton(withTitle: "Descartar")
            if a.runModal() == .alertFirstButtonReturn, (try? session.openRecovery()) != nil { recovered = true }
            else { session.clearRecovery() }
        }
        if !recovered, let last = RecentFiles.list.first, FileManager.default.fileExists(atPath: last), CommandLine.arguments.count < 2 {
            try? session.open(last)
        }
        if !testMode { session.startAutosave() }
        let argv = CommandLine.arguments
        for (k, a) in argv.enumerated().dropFirst() where a.lowercased().hasSuffix(".mmp") && !argv[k - 1].hasPrefix("--")
            && FileManager.default.fileExists(atPath: a) { openFile(a) }
        updateTitle()
        NotificationCenter.default.addObserver(forName: .playlistChanged, object: nil, queue: .main) { [weak self] _ in self?.updateTitle() }
        // Verificación sin pantalla: MixMeister8 --snapshot salida.png [lista.mmp] [--select N] [--zoom Z]
        let args = CommandLine.arguments
        // Prueba de audio: MixMeister8 lista.mmp --playtest INSTANTE  (suena 4 s y anota niveles)
        if let i = args.firstIndex(of: "--playtest"), i + 1 < args.count, let t0 = Double(args[i + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if let j = args.firstIndex(of: "--record"), j + 1 < args.count { Player.shared.startRecording(to: URL(fileURLWithPath: args[j + 1])) }
                Player.shared.play(from: t0)
                var n = 0
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { tm in
                    let p = Player.shared
                    print(String(format: "PLAYTEST pos=%.2f playing=%d L=%.3f R=%.3f pistas_montadas=%d LUFS=%.1f", p.position, p.isPlaying ? 1 : 0, p.peakL, p.peakR, p.chainCount, p.shortTermLUFS))
                    fflush(stdout)
                    n += 1
                    let total = args.firstIndex(of: "--playsecs").flatMap { $0 + 1 < args.count ? Int(args[$0 + 1]) : nil } ?? 4
                    if n >= total * 2 {
                        tm.invalidate()
                        if p.isRecording { p.stopRecording(); print(String(format: "RECORD %.2f s grabados", p.recordedSeconds)) }
                        p.stop(); NSApp.terminate(nil)
                    }
                }
            }
        }
        // Prueba de exportación: MixMeister8 lista.mmp --exporttest salida.wav [songs|labels]
        if let i = args.firstIndex(of: "--exporttest"), i + 1 < args.count {
            let out = URL(fileURLWithPath: args[i + 1])
            let split: Exporter.Split = args.contains("--songs") ? .songs : (args.contains("--labels") ? .labels : .none)
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
                let t0 = Date()
                do {
                    var opt = Exporter.Options()
                    if let j = args.firstIndex(of: "--normalize"), j + 1 < args.count { opt.normalize = Double(args[j + 1]) }
                    if let j = args.firstIndex(of: "--rate"), j + 1 < args.count, let r = Double(args[j + 1]) { opt.sampleRate = r }
                    let kind: Exporter.Kind = args.contains("--flac") ? .flac : (args.contains("--wav24") ? .wav24 : .wav)
                    let urls = try Exporter.toFiles(base: out, kind: kind, split: split, options: opt) { _ in true }
                    print("EXPORTTEST ok \(urls.count) ficheros en \(String(format: "%.1f", Date().timeIntervalSince(t0))) s: \(urls.map(\.lastPathComponent).joined(separator: ", ")) \(Exporter.lastReport)" + (Exporter.lastWarning.map { " AVISO: " + $0 } ?? ""))
                } catch { print("EXPORTTEST error \(error.localizedDescription)") }
                if args.contains("--cd") {
                    do { let c = try Exporter.cdImage(dir: out.deletingLastPathComponent(), split: .songs) { _ in true }; print("CDTEST ok \(c.path)") }
                    catch { print("CDTEST error \(error.localizedDescription)") }
                }
                fflush(stdout)
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        }
        // Efectos: --fxtest lista todos y comprueba que cargan; --addfx "Nombre - Fabricante" [--fxtrack N]
        // añade uno (a la pista N o al master) antes de --snapshot / --exporttest.
        if args.contains("--fxtest") {
            print("FXTEST \(FxCatalog.builtIn.count) propios, \(FxCatalog.installed.count) Audio Units instalados")
            for t in args.contains("--fxall") ? FxCatalog.all : FxCatalog.builtIn {
                let n = FxHost.makeNode(t)
                print("FXTEST \(n == nil ? "FALLA" : "ok   ") \(t.listName) · \(t.params.count) parámetros · código \(fourCCString(t.code))")
                fflush(stdout)
            }
            fflush(stdout)
            if !args.contains("--snapshot") && !args.contains("--exporttest") { NSApp.terminate(nil) }
        }
        if let i = args.firstIndex(of: "--addfx"), i + 1 < args.count {
            let tr = args.firstIndex(of: "--fxtrack").flatMap { $0 + 1 < args.count ? Int(args[$0 + 1]) : nil }
            print("ADDFX \(EffectsActions.add(named: args[i + 1], toTrack: tr) ? "ok" : "no encontrado") \(args[i + 1]) → \(tr.map { "pista \($0 + 1)" } ?? "master")")
            if let j = args.firstIndex(of: "--fxvalue"), j + 1 < args.count, let v = Double(args[j + 1]) {
                session.mutateLight("test") { d in
                    func set(_ e: inout PLEffect) { for k in e.params.indices { e.params[k] = v } }
                    if let tr { if !d.tracks[tr].effects.isEmpty { set(&d.tracks[tr].effects[d.tracks[tr].effects.count - 1]) } }
                    else if !d.master_effects.isEmpty { set(&d.master_effects[d.master_effects.count - 1]) }
                }
            }
            fflush(stdout)
        }
        if let i = args.firstIndex(of: "--slicer"), i + 1 < args.count, let n = Int(args[i + 1]) {
            session.selectedTrack = n
            viewSongSlicer(nil)
            if let j = args.firstIndex(of: "--slicerbpm"), j + 1 < args.count, let v = Double(args[j + 1]) { bottom.slicer.canvas.setBPM(v) }
            let t = session.doc.tracks[n]
            print("SLICER pista \(n + 1): bar_us=\(t.bar_us) bpm=\(t.bpm) marcadores=\(t.beat_markers_us.count) \(t.beat_markers_us.map { String(format: "%.2f", Double($0) * 1e-6) }.joined(separator: " "))")
            fflush(stdout)
        }
        if args.contains("--effectslist") { viewEffects(nil) }
        // --similar N: las 6 más compatibles con la pista N; --orderflow: reordenar y decir cuánto mejora.
        if let i = args.firstIndex(of: "--similar"), i + 1 < args.count, let n = Int(args[i + 1]), n <= session.doc.tracks.count,
           let ref = session.libraryItem(for: session.doc.tracks[n - 1]) {
            session.selectedTrack = n - 1
            findSimilarTracks(nil)
            let top = session.catalog.items.filter { $0.path != ref.path && Similarity.bpmScore($0.bpm, ref.bpm) >= 0.25 }.map { ($0, Similarity.score($0, ref)) }.sorted { $0.1 > $1.1 }.prefix(6)
            print("SIMILAR a «\(ref.title)» (\(ref.keyText), \(ref.bpm) BPM): " + top.map { String(format: "%@ [%@ %.1f] %.2f", $0.0.title, $0.0.keyText, $0.0.bpm, $0.1) }.joined(separator: " · "))
            fflush(stdout)
            if !args.contains("--snapshot") { NSApp.terminate(nil) }
        }
        if args.contains("--orderflow") {
            let items = session.doc.tracks.map { session.libraryItem(for: $0) }
            let order = Similarity.flowOrder(items)
            print(String(format: "ORDERFLOW compatibilidad media entre pistas seguidas: %.3f → %.3f; orden: %@", Similarity.totalFlow(items) / Double(max(1, items.count - 1)),
                         Similarity.totalFlow(order.map { items[$0] }) / Double(max(1, items.count - 1)), order.map { "\($0 + 1)" }.joined(separator: " ")))
            fflush(stdout)
            if !args.contains("--snapshot") { NSApp.terminate(nil) }
        }
        // Prueba de calidad: --nulltest audio.mp3 salida.wav — una sola pista a su tempo, sin
        // marcadores, exportada a 24 bits (debe salir idéntica al audio decodificado).
        if let i = args.firstIndex(of: "--nulltest"), i + 2 < args.count {
            let src = args[i + 1], out = URL(fileURLWithPath: args[i + 2])
            let f = try? AVAudioFile(forReading: URL(fileURLWithPath: src))
            let len = Int64(Double(f?.length ?? 0) / (f?.processingFormat.sampleRate ?? 44100) * 1e6)
            let tr = PLTrack(path: src, transition_in: nil, transition_out: nil, file_id: "", bpm: 120, original_bpm: 120, bar_us: 2_000_000,
                             length_us: len, overlay: false, key_semitones: 0, beat_markers_us: [], effects: [],
                             layer: [.segment(PLSegment(reversed: false, class: 1, src_start_us: 0, src_end_us: len, anchor_us: 0,
                                                        overlay_measure: 0, overlay_fraction: 0, overlay_rate: 1))])
            session.mutate("test") { d in d.tracks = [tr] }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                let t0 = Date()
                do { let u = try Exporter.toFiles(base: out, kind: .wav24, split: .none) { _ in true }; print("NULLTEST ok \(u[0].path) \(String(format: "%.1f", Date().timeIntervalSince(t0))) s") }
                catch { print("NULLTEST error \(error)") }
                fflush(stdout)
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        }
        // Sincronía: --synctest audio.mp3 salida.wav — 10 s de silencio y después la pista (a su
        // tempo). La pista debe empezar exactamente en 10,000 s (con --forcepitch pasa por el
        // cambio de tempo; con --serial, render seguido como en directo).
        if let i = args.firstIndex(of: "--synctest"), i + 2 < args.count {
            let src = args[i + 1], out = URL(fileURLWithPath: args[i + 2])
            let sil = URL(fileURLWithPath: NSTemporaryDirectory() + "mm8-silencio.wav")
            let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
            if let f = try? AVAudioFile(forWriting: sil, settings: fmt.settings), let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 441000) {
                b.frameLength = 441000
                try? f.write(from: b)
            }
            let fa = try? AVAudioFile(forReading: URL(fileURLWithPath: src))
            let len = Int64(Double(fa?.length ?? 0) / (fa?.processingFormat.sampleRate ?? 44100) * 1e6)
            func track(_ p: String, _ l: Int64, intro: Int64, outro: Int64) -> PLTrack {
                PLTrack(path: p, transition_in: nil, transition_out: nil, file_id: "", bpm: 120, original_bpm: 120, bar_us: 2_000_000,
                        length_us: l, overlay: false, key_semitones: 0, beat_markers_us: [], effects: [],
                        layer: [.marker(PLMarker(type: MarkerKind.introAnchor, pos_us: intro)), .marker(PLMarker(type: MarkerKind.outroAnchor, pos_us: outro)),
                                .segment(PLSegment(reversed: false, class: 1, src_start_us: 0, src_end_us: l, anchor_us: 0,
                                                   overlay_measure: 0, overlay_fraction: 0, overlay_rate: 1))])
            }
            let t1 = track(sil.path, 10_000_000, intro: 0, outro: 10_000_000)
            var t2 = track(src, len, intro: 0, outro: len)
            if let j = args.firstIndex(of: "--synctempo"), j + 1 < args.count, let v = Double(args[j + 1]) {
                t2.layer.append(.marker(PLMarker(type: MarkerKind.originalTempo, pos_us: 0, value: v)))   // suena a v (audio a 120)
            }
            session.mutate("test") { d in d.tracks = [t1, t2] }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                do { let u = try Exporter.toFiles(base: out, kind: .wav24, split: .none) { _ in true }; print("SYNCTEST ok \(u[0].path) inicio pista 2 = \(String(format: "%.4f", self.session.layout.items[1].mixStart)) s") }
                catch { print("SYNCTEST error \(error)") }
                fflush(stdout)
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        }
        // --lufs fichero: sonoridad integrada y pico real de cualquier fichero de audio.
        if let i = args.firstIndex(of: "--lufs"), i + 1 < args.count {
            if let f = try? AVAudioFile(forReading: URL(fileURLWithPath: args[i + 1])),
               let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: 65536) {
                let m = mmn_loud_new(f.processingFormat.sampleRate, Int32(f.processingFormat.channelCount))
                while (try? f.read(into: buf)) != nil, buf.frameLength > 0, let ch = buf.floatChannelData {
                    mmn_loud_add(m, ch[0], f.processingFormat.channelCount > 1 ? ch[1] : nil, Int32(buf.frameLength))
                }
                print(String(format: "LUFS %.2f TP %.2f", mmn_loud_integrated(m), mmn_loud_truepeak_db(m)))
                mmn_loud_free(m)
            } else { print("LUFS error") }
            fflush(stdout)
            NSApp.terminate(nil)
        }
        // --roundtrip carpeta: abre cada .mmp, lo pasa por la app (JSON) y lo guarda; debe salir idéntico.
        if let i = args.firstIndex(of: "--roundtrip"), i + 1 < args.count {
            let dir = args[i + 1]
            var ok = 0, bad: [String] = [], total = 0
            let en = FileManager.default.enumerator(atPath: dir)
            while let f = en?.nextObject() as? String {
                guard f.lowercased().hasSuffix(".mmp") else { continue }
                total += 1
                let p = (dir as NSString).appendingPathComponent(f)
                let tmp = NSTemporaryDirectory() + "mm8-rt.mmp"
                do {
                    let e = try EngineDocument(path: p)
                    try e.write(try e.read())
                    try e.save(to: tmp)
                    if FileManager.default.contentsEqual(atPath: p, andPath: tmp) { ok += 1 } else { bad.append(f) }
                } catch { bad.append(f + " (\(error.localizedDescription))") }
            }
            print("ROUNDTRIP \(ok) de \(total) idénticas" + (bad.isEmpty ? "" : "; distintas: " + bad.prefix(5).joined(separator: ", ")))
            fflush(stdout)
            NSApp.terminate(nil)
        }
        // Velocidad: --wavetime espera a tener todas las formas de onda y dice cuánto tardó.
        if args.contains("--wavetime") {
            let t0 = Date()
            Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { tm in
                let n = self.session.doc.tracks.indices.filter { self.session.audioPath($0).flatMap { Waveforms.shared.get($0) } != nil }.count
                if n == self.session.doc.tracks.count && n > 0 || Date().timeIntervalSince(t0) > 120 {
                    tm.invalidate()
                    print(String(format: "WAVETIME %d formas de onda en %.2f s", n, Date().timeIntervalSince(t0)))
                    fflush(stdout)
                    NSApp.terminate(nil)
                }
            }
        }
        // Estabilidad: --crashtest cambia la lista, guarda la copia de recuperación y se cierra de golpe.
        if args.contains("--crashtest") {
            session.mutateLight("crash test") { d in if !d.tracks.isEmpty { d.tracks[0].key_semitones = 1 } }
            session.autosave()
            print("CRASHTEST copia: \(FileManager.default.fileExists(atPath: Session.recoveryURL.path))")
            fflush(stdout)
            exit(3)
        }
        if let i = args.firstIndex(of: "--saveas"), i + 1 < args.count {
            do { try session.save(to: args[i + 1]); print("SAVEAS ok \(args[i + 1])") } catch { print("SAVEAS error \(error)") }
            fflush(stdout)
        }
        // --where N t: qué audio de la pista N debe sonar en el instante t de la mezcla y a qué velocidad.
        if let i = args.firstIndex(of: "--where"), i + 2 < args.count, let n = Int(args[i + 1]), let t = Double(args[i + 2]),
           let it = session.layout.items.first(where: { $0.index == n - 1 }) {
            let seg = it.segments.first { t >= $0.mixStart && t < $0.mixEnd } ?? it.segments[0]
            print(String(format: "WHERE pista %d en %.3f s: audio %.4f s, velocidad %.5f · %@", n, t, seg.source(it, at: t), it.rate(at: t), session.audioPath(n - 1) ?? "-"))
            fflush(stdout)
            if args.contains("--quit") { NSApp.terminate(nil) }
        }
        // Diagnóstico del tempo por fila: MixMeister8 lista.mmp --dumpbpm
        if args.contains("--dumpbpm") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let L = self.session.layout
                for it in L.items {
                    var sum = 0.0, n = 0
                    var t = it.mixStart
                    while t < it.mixEnd { sum += it.tempo(at: t); n += 1; t += 0.25 }
                    let mid = it.tempo(at: (it.mixStart + it.mixEnd) / 2)
                    print(String(format: "BPM %2d entrada=%.1f inicio=%.1f medio=%.1f mitad=%.1f fin=%.1f", it.index + 1, it.tempo, it.tempo(at: it.mixStart), sum / Double(max(1, n)), mid, it.tempo(at: it.mixEnd - 0.1)))
                    let tr = self.session.doc.tracks[it.index]
                    print(String(format: "   pista %2d: %.1f–%.1f s, %d segmentos (%d invertidos), %d marcadores de tempo, overlay %d, tempo propio %.2f / audio %.2f",
                                 it.index + 1, it.mixStart, it.mixEnd, tr.segments.count, tr.segments.filter(\.reversed).count,
                                 tr.markers(MarkerKind.tempo).count, it.overlay ? 1 : 0, MixLayout.ownTempo(tr), MixLayout.audioTempo(tr)))
                }
                let tot = L.total
                print(String(format: "TOTAL %d:%02d (%.1f s)", Int(tot) / 60, Int(tot) % 60, tot))
                fflush(stdout)
                NSApp.terminate(nil)
            }
        }
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            if let j = args.firstIndex(of: "--select"), j + 1 < args.count, let n = Int(args[j + 1]) { session.selectedTrack = n }
            if let j = args.firstIndex(of: "--zoom"), j + 1 < args.count, let z = Double(args[j + 1]) { timelinePane.zoom(by: z) }
            if let j = args.firstIndex(of: "--strips"), j + 1 < args.count, let n = Int(args[j + 1]) { session.strips = n }
            let out = args[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { self.snapshot(to: out); NSApp.terminate(nil) }
        }
    }

    func snapshot(to path: String) {
        guard let v = window.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        // AppKit pasa como «fichero» cualquier argumento que no empiece por «-» (p. ej. el nombre
        // de un efecto en --addfx): solo se abren las rutas que existen.
        guard filename.lowercased().hasSuffix(".mmp"), FileManager.default.fileExists(atPath: filename) else { return false }
        openFile(filename); return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
    /// Arrancada para una prueba (--snapshot, --exporttest…): al acabar se cierra sin preguntar.
    private let testMode = CommandLine.arguments.contains { ["--snapshot", "--exporttest", "--serial", "--playtest", "--dumpbpm", "--fxtest", "--saveas", "--nulltest", "--synctest", "--quit", "--lufs", "--roundtrip", "--wavetime", "--crashtest", "--similar", "--orderflow"].contains($0) }
    func applicationShouldTerminate(_ s: NSApplication) -> NSApplication.TerminateReply {
        testMode || confirmDiscard() ? .terminateNow : .terminateCancel
    }
    /// Salida normal (guardado o descartado a propósito): la copia de recuperación sobra.
    func applicationWillTerminate(_ n: Notification) { if !testMode { session.clearRecovery() } }
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { session.undo }

    // MARK: Menús

    private func buildMenus() {
        let main = MenuSpecs.main.build()
        NSApp.mainMenu = main
        if let app = main.items.first?.submenu, let services = app.items.first(where: { $0.title == "Services" })?.submenu {
            NSApp.servicesMenu = services
        }
        NSApp.windowsMenu = main.items.first { $0.title == "Window" }?.submenu
        NSApp.helpMenu = main.items.first { $0.title == "Help" }?.submenu
        // Library › Columns va a la biblioteca aunque el foco esté en otra parte.
        if let cols = main.items.first(where: { $0.title == "Library" })?.submenu?.items.first(where: { $0.title == "Columns" })?.submenu {
            for it in cols.items { it.target = library }
        }
        // «stop:» existe en NSApplication (detiene la app): Playback › Stop va directo al reproductor.
        func retarget(_ m: NSMenu) {
            for it in m.items {
                if it.action == NSSelectorFromString("stop:") { it.target = self }
                if let sub = it.submenu { retarget(sub) }
            }
        }
        retarget(main)
        // Nuevo en MixMeister 8: Playback › Record Mix…, Library › Find Similar / Tools › Order
        // Playlist for Harmonic Flow, View › Color Waveforms.
        if let pb = main.items.first(where: { $0.title == "Playback" })?.submenu {
            pb.addItem(.separator())
            let it = NSMenuItem(title: "Record Mix…", action: #selector(recordMix(_:)), keyEquivalent: "r")
            it.keyEquivalentModifierMask = [.command, .option]
            it.target = self
            pb.addItem(it)
        }
        if let tools = main.items.first(where: { $0.title == "Tools" })?.submenu {
            tools.addItem(.separator())
            let it = NSMenuItem(title: "Order Playlist for Harmonic Flow", action: #selector(orderForFlow(_:)), keyEquivalent: "")
            it.target = self
            tools.addItem(it)
        }
        if let view = main.items.first(where: { $0.title == "View" })?.submenu {
            let it = NSMenuItem(title: "Color Waveforms", action: #selector(toggleColorWaveforms(_:)), keyEquivalent: "")
            it.target = self
            view.addItem(.separator())
            view.addItem(it)
        }
        // View › Skin: los seis aspectos.
        if let view = main.items.first(where: { $0.title == "View" })?.submenu {
            view.addItem(.separator())
            let item = NSMenuItem(title: "Skin", action: nil, keyEquivalent: "")
            let sub = NSMenu(title: "Skin")
            for (i, sk) in Skin.all.enumerated() {
                let it = NSMenuItem(title: sk.name, action: #selector(chooseSkin(_:)), keyEquivalent: "")
                it.tag = i
                it.target = self
                it.state = sk.name == Theme.skin.name ? .on : .off
                sub.addItem(it)
            }
            item.submenu = sub
            view.addItem(item)
        }
        // Open Recent Playlist y Tools › Transitions se rellenan al abrirse.
        recentMenu?.delegate = self
        transitionsMenu?.delegate = self
    }

    private var recentMenu: NSMenu? { NSApp.mainMenu?.items.first { $0.title == "File" }?.submenu?.items.first { $0.title == "Open Recent Playlist" }?.submenu }
    private var transitionsMenu: NSMenu? { NSApp.mainMenu?.items.first { $0.title == "Tools" }?.submenu?.items.first { $0.title == "Transitions" }?.submenu }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === recentMenu {
            menu.removeAllItems()
            for p in RecentFiles.list {
                let it = NSMenuItem(title: (p as NSString).lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
                it.representedObject = p
                it.toolTip = p
                it.target = self
                menu.addItem(it)
            }
            if !RecentFiles.list.isEmpty { menu.addItem(.separator()) }
            menu.addItem(NSMenuItem(title: "Clear Menu", action: NSSelectorFromString("clearRecentFiles:"), keyEquivalent: ""))
        } else if menu === transitionsMenu {
            menu.removeAllItems()
            let cur = session.selectedTrack.flatMap { $0 < session.doc.tracks.count ? session.doc.tracks[$0].transition_out : nil }
            for name in Transitions.names {
                let it = NSMenuItem(title: name, action: #selector(chooseTransition(_:)), keyEquivalent: "")
                it.target = self
                it.state = name == cur ? .on : .off
                menu.addItem(it)
            }
        }
    }

    // MARK: Ventana (misma distribución que MixMeister: biblioteca | lista, línea de tiempo, rack)

    private func buildWindow() {
        let frame = NSRect(x: 0, y: 0, width: 1500, height: 940)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Theme.background
        window.minSize = NSSize(width: 1000, height: 640)
        window.delegate = self
        window.setFrameAutosaveName("MixMeister8MainWindow")
        if !window.setFrameUsingName("MixMeister8MainWindow") { window.center() }

        topSplit.isVertical = true
        topSplit.dividerStyle = .thin
        topSplit.addArrangedSubview(library)
        topSplit.addArrangedSubview(playlist)
        topSplit.autosaveName = "MixMeister8.topSection"
        mainSplit.isVertical = false
        mainSplit.dividerStyle = .thin
        mainSplit.addArrangedSubview(topSplit)
        mainSplit.addArrangedSubview(timelinePane)
        mainSplit.addArrangedSubview(bottom)
        mainSplit.autosaveName = "MixMeister8.mainVert"
        mainSplit.setHoldingPriority(.defaultLow - 1, forSubviewAt: 1)
        let content = FillView(Theme.background)
        mainSplit.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(mainSplit)
        NSLayoutConstraint.activate([
            mainSplit.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            mainSplit.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            mainSplit.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            mainSplit.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        // Proporciones de partida (las de MixMeister: arriba 42 %, línea de tiempo 42 %, rack 16 %),
        // también si lo guardado quedó con algún panel plegado.
        content.layoutSubtreeIfNeeded()
        applyDefaultProportions(force: false)
        DispatchQueue.main.async { self.applyDefaultProportions(force: false) }
    }

    private func applyDefaultProportions(force: Bool) {
        let h = mainSplit.bounds.height, w = topSplit.bounds.width
        guard h > 100, w > 100 else { return }
        let heights = mainSplit.arrangedSubviews.map(\.frame.height)
        if force || heights.count < 3 || heights[0] < 150 || heights[1] < 150 || heights[2] < 60 {
            mainSplit.setPosition(h * 0.42, ofDividerAt: 0)
            mainSplit.setPosition(h * 0.84, ofDividerAt: 1)
        }
        let widths = topSplit.arrangedSubviews.map(\.frame.width)
        if force || widths.count < 2 || widths[0] < 200 || widths[1] < 200 {
            topSplit.setPosition(w * 0.37, ofDividerAt: 0)
        }
    }

    func updateTitle() {
        window?.title = "MixMeister 8 - \(session.title)"
        window?.isDocumentEdited = session.dirty
        window?.representedURL = session.path.map { URL(fileURLWithPath: $0) }
    }

    // MARK: Validación de menús

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let a = item.action else { return true }
        let sel = NSStringFromSelector(a)
        switch sel {
        case "view2Strips:", "view4Strips:", "view6Strips:", "view8Strips:":
            item.state = session.strips == Int(sel.dropFirst(4).prefix(1))! ? .on : .off
        case "timelineRulerTime:": item.state = timelinePane.timeline.rulerMeasures ? .off : .on
        case "timelineRulerMeasuresAndBeats:": item.state = timelinePane.timeline.rulerMeasures ? .on : .off
        case "snapToBeat:": item.state = snapOn ? .on : .off
        case let s where s.hasPrefix("snapTo"):
            item.state = snapCodes[s] == snapType ? .on : .off
        case "viewLibrary:": item.state = !library.isHidden && !library.showingEffects ? .on : .off
        case "recordMix:": item.title = player.isRecording ? "Stop Recording" : "Record Mix…"
        case "toggleColorWaveforms:": item.state = TimelineView.colorWaveforms ? .on : .off
        case "orderForFlow:": return session.doc.tracks.count > 2
        case "viewEffects:": item.state = !library.isHidden && library.showingEffects ? .on : .off
        case "addEffectsParameterMarker:":
            return session.trackedParam != nil && session.trackedParam?.track == session.selectedTrack
        case "deleteEffectsMarkers:":
            guard let i = session.selectedTrack, i < session.doc.tracks.count else { return false }
            return session.doc.tracks[i].markers.contains { $0.type == MarkerKind.effectParam }
        case "viewSongSlicer:": item.state = bottom.tabs.selectedSegment == 0 ? .on : .off
        case "viewEffectsRack:": item.state = bottom.tabs.selectedSegment == 1 ? .on : .off
        case "savePlayList:", "savePlayListAs:": return !session.doc.tracks.isEmpty || session.path != nil
        case "delete:", "del:", "tweaks:", "adjustTrackSettings:", "editTag:":
            return session.selectedTrack != nil && (sel == "delete:" || sel == "del:")
        case "editRulerMarkerItem:", "deleteRulerMarkerItem:": return lane.point != nil
        case "burnCD:", "exportPlaylistToFile:", "exportPlaylistToDevice:", "exportPlaylistAsMobileMix:", "exportChooser:":
            return !session.doc.tracks.isEmpty
        case "addToEndOfPlaylist:", "catPreviewPlay:": return !library.selectedItems.isEmpty
        case "catPreviewStop:": return player.isPreviewing
        case "playPause:", "jogForward:", "jogBackward:", "previousTrack:", "nextTrack:", "mixNow:":
            return !session.doc.tracks.isEmpty
        case "stop:": return player.isPlaying || player.position > 0
        case "undo:": return session.undo.canUndo
        case "redo:": return session.undo.canRedo
        case "clearRecentFiles:": return !RecentFiles.list.isEmpty
        default: break
        }
        return responds(to: a)
    }

    // MARK: File

    private func confirmDiscard() -> Bool {
        guard session.dirty else { return true }
        let a = NSAlert()
        a.messageText = "¿Guardar los cambios de «\(session.title)»?"
        a.informativeText = "Si no los guardas, se perderán."
        a.addButton(withTitle: "Guardar")
        a.addButton(withTitle: "Cancelar")
        a.addButton(withTitle: "No guardar")
        switch a.runModal() {
        case .alertFirstButtonReturn: savePlayList(nil); return !session.dirty
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    @objc func newPlayList(_ s: Any?) { guard confirmDiscard() else { return }; session.newPlaylist(); updateTitle() }

    @objc func openPlayList(_ s: Any?) {
        guard confirmDiscard() else { return }
        let p = NSOpenPanel()
        p.allowedContentTypes = [Self.mmpType]
        p.allowsOtherFileTypes = true
        p.message = "Abrir una lista de MixMeister (.mmp)"
        if p.runModal() == .OK, let u = p.url { openFile(u.path) }
    }

    @objc func openRecent(_ item: NSMenuItem) {
        guard confirmDiscard(), let p = item.representedObject as? String else { return }
        openFile(p)
    }

    func openFile(_ p: String) {
        do { try session.open(p); updateTitle() } catch { show(error, "No se puede abrir «\((p as NSString).lastPathComponent)»") }
    }

    @objc func appendPlayList(_ s: Any?) {
        let p = NSOpenPanel()
        p.allowedContentTypes = [Self.mmpType]
        p.allowsOtherFileTypes = true
        guard p.runModal() == .OK, let u = p.url else { return }
        do {
            let other = try EngineDocument(path: u.path).read()
            session.mutate("Append Playlist") { d in
                d.tracks += other.tracks.map { var t = $0; t._src = nil; return t }
            }
        } catch { show(error, "No se puede añadir la lista") }
    }

    @objc func clearRecentFiles(_ s: Any?) { RecentFiles.clear(); NSDocumentController.shared.clearRecentDocuments(nil) }

    @objc func savePlayList(_ s: Any?) {
        guard let p = session.path else { savePlayListAs(s); return }
        do { try session.save(to: p); updateTitle() } catch { show(error, "No se puede guardar") }
    }

    @objc func savePlayListAs(_ s: Any?) {
        let p = NSSavePanel()
        p.allowedContentTypes = [Self.mmpType]
        p.nameFieldStringValue = session.title.hasSuffix(".mmp") ? session.title : session.title + ".mmp"
        p.message = "Se guarda en el formato de MixMeister: también la abre MixMeister 7."
        guard p.runModal() == .OK, let u = p.url else { return }
        do { try session.save(to: u.path); updateTitle() } catch { show(error, "No se puede guardar") }
    }

    // MARK: Edit / lista

    @objc func delete(_ s: Any?) {
        guard let i = session.selectedTrack else { return }
        session.mutate("Delete") { d in
            d.tracks.remove(at: i)
            Self.linkTransitions(&d)
        }
        session.selectedTrack = nil
    }
    @objc func del(_ s: Any?) { delete(s) }
    @objc func undo(_ s: Any?) { session.undo.undo() }
    @objc func redo(_ s: Any?) { session.undo.redo() }

    /// TRSO de una pista y TRSI de la siguiente van juntas (así las guarda MixMeister).
    static func linkTransitions(_ d: inout PLDocument) {
        let n = d.tracks.count
        for i in 0..<n {
            if i < n - 1 {
                let name = d.tracks[i].transition_out ?? d.tracks[i + 1].transition_in ?? Transitions.default
                d.tracks[i].transition_out = name
                d.tracks[i + 1].transition_in = name
            } else { d.tracks[i].transition_out = nil }
            if i == 0 { d.tracks[i].transition_in = nil }
        }
    }

    func setTransition(row: Int, name: String) {
        session.mutate("Transition") { d in
            guard row < d.tracks.count - 1 else { return }
            d.tracks[row].transition_out = name
            d.tracks[row + 1].transition_in = name
        }
    }

    @objc func chooseTransition(_ item: NSMenuItem) {
        guard let i = session.selectedTrack else { return }
        setTransition(row: i, name: item.title)
    }

    /// Library › Add to End of Playlist (⌃Q): la pista entra con la mezcla por defecto de
    /// MixMeister — anclas en las ventanas de 32 tiempos y la transición Beatmix 8.
    @objc func addToEndOfPlaylist(_ s: Any?) {
        let items = library.selectedItems
        guard !items.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let tracks = items.map { DefaultMix.track(for: $0) }
            DispatchQueue.main.async {
                self.session.mutate("Add to End of Playlist") { d in
                    d.tracks += tracks
                    Self.linkTransitions(&d)
                }
            }
        }
    }

    // MARK: Playback

    var player: Player { .shared }
    @objc func playPause(_ s: Any?) {
        Log.write("Play/Pause (sonando=\(player.isPlaying), cursor \(String(format: "%.2f", timelinePane.timeline.playhead)))")
        player.toggle(from: timelinePane.timeline.playhead)
    }
    @objc func stop(_ s: Any?) { player.stop() }
    @objc func jogForward(_ s: Any?) { player.seek(player.position + 5) }
    @objc func jogBackward(_ s: Any?) { player.seek(max(0, player.position - 5)) }
    private var trackStarts: [Double] { session.layout.items.filter { !$0.overlay }.map(\.mixStart).sorted() }
    @objc func previousTrack(_ s: Any?) {
        let p = player.position
        player.seek(trackStarts.last { $0 < p - 1.5 } ?? 0)
    }
    @objc func nextTrack(_ s: Any?) {
        let p = player.position
        if let n = trackStarts.first(where: { $0 > p + 0.05 }) { player.seek(n) }
    }
    /// Mix Now (F6): salta al ancla de salida de la pista que suena, donde empieza la transición.
    @objc func mixNow(_ s: Any?) {
        let p = player.position
        let L = session.layout
        guard let cur = L.items.last(where: { !$0.overlay && $0.mixStart <= p }), cur.index < session.doc.tracks.count,
              let outro = session.doc.tracks[cur.index].markers(MarkerKind.outroAnchor).first else { return }
        let t = cur.toMix(Double(outro.pos_us) * 1e-6)
        if t > p { player.seek(t) }
    }
    @objc func catPreviewPlay(_ s: Any?) {
        guard let it = library.selectedItems.first else { return }
        player.previewPlay(path: it.path)
    }
    @objc func catPreviewStop(_ s: Any?) { player.previewStop() }
    /// Doble clic en la lista: suena desde el principio de esa pista.
    @objc func playFromPlaylistRow(_ s: Any?) {
        let r = playlist.table.clickedRow
        guard r >= 0, let it = session.layout.items.first(where: { $0.index == r }) else { return }
        session.selectedTrack = r
        player.play(from: it.mixStart)
    }

    @objc func doAudioSetupDialog(_ s: Any?) { OutputConfig.runDialog() }

    // MARK: Exportar y CD (botones de arriba a la derecha de la lista y menú File)

    @objc func exportChooser(_ s: Any?) { ExportUI.shared.chooseFileOrDevice() }
    @objc func exportPlaylistToFile(_ s: Any?) { ExportUI.shared.exportToFile() }
    @objc func exportPlaylistToDevice(_ s: Any?) { ExportUI.shared.exportToMusic() }
    @objc func exportPlaylistAsMobileMix(_ s: Any?) { ExportUI.shared.exportToMusic() }
    @objc func burnCD(_ s: Any?) { ExportUI.shared.burnCD() }

    // MARK: Tempo (barra de tempos y Master BPM)

    private var lane: (time: Double, point: (track: Int, type: UInt32, mix: Double)?) { timelinePane.timeline.laneClick }

    /// Añade un marcador de tempo (o de tempo original) en el instante `t` de la mezcla, en la
    /// pista principal que suena ahí.
    private func addTempoMarker(type: UInt32, at t: Double, value: Double?) {
        let L = session.layout
        guard let item = L.primary(at: t), item.index < session.doc.tracks.count else { return }
        let v = value ?? (type == MarkerKind.originalTempo ? item.own : item.tempo(at: t))
        let pos = Int64((item.toSource(t) * 1e6).rounded())
        session.mutate(type == MarkerKind.tempo ? "Add Tempo Marker" : "Add Original Tempo Marker") { d in
            d.tracks[item.index].layer.append(.marker(PLMarker(type: type, pos_us: pos, value: (v * 1000).rounded() / 1000)))
        }
    }
    @objc func rulerAddTempoMarker(_ s: Any?) { addTempoMarker(type: MarkerKind.tempo, at: lane.time, value: nil) }
    @objc func rulerAddOriginalTempoMarker(_ s: Any?) { addTempoMarker(type: MarkerKind.originalTempo, at: lane.time, value: nil) }

    /// El marcador de la barra de tempos sobre el que se hizo clic: (pista, posición en la capa).
    private func laneMarker() -> (track: Int, layer: Int, marker: PLMarker)? {
        guard let p = lane.point, p.track < session.doc.tracks.count,
              let item = session.layout.items.first(where: { $0.index == p.track }) else { return nil }
        let t = session.doc.tracks[p.track]
        var best: (Int, PLMarker, Double)?
        for (k, li) in t.layer.enumerated() {
            if case let .marker(m) = li, m.type == p.type {
                let d = abs(item.toMix(Double(m.pos_us) * 1e-6) - p.mix)
                if best == nil || d < best!.2 { best = (k, m, d) }
            }
        }
        return best.map { (p.track, $0.0, $0.1) }
    }

    /// Valor nuevo para el marcador de la barra de tempos (doble clic o Edit).
    func setLaneMarkerValue(_ v: Double) {
        guard let (ti, li, _) = laneMarker() else { return }
        session.mutate("Edit Tempo Marker") { d in
            if case var .marker(mm) = d.tracks[ti].layer[li] { mm.value = v; d.tracks[ti].layer[li] = .marker(mm) }
        }
    }

    // MARK: Efectos (marcadores de parámetro desde el menú de la pista)

    /// Add Effects Parameter Marker (E): en el cursor, con el valor actual del parámetro que se
    /// sigue en el rack.
    @objc func addEffectsParameterMarker(_ s: Any?) {
        guard let tp = session.trackedParam, tp.track < session.doc.tracks.count,
              let item = session.layout.items.first(where: { $0.index == tp.track }),
              let e = session.doc.tracks[tp.track].effects.first(where: { $0.slot == tp.slot }) else { return }
        let t = timelinePane.timeline.playhead
        let seg = item.segments.first { t >= $0.mixStart && t < $0.mixEnd } ?? item.segments.first
        guard let seg else { return }
        let src = seg.source(item, at: t)
        let v = tp.param == 0xFFF ? (e.flags & 1 == 0 ? 1.0 : 0.0) : (tp.param < e.params.count ? e.params[tp.param] : 0.5)
        session.mutateLight("Add Effects Parameter Marker") { d in
            d.tracks[tp.track].layer.append(.marker(PLMarker(type: MarkerKind.effectParam, pos_us: Int64(src * 1e6), flag: tp.slot << 12 | UInt32(tp.param), value: v)))
        }
    }
    @objc func deleteEffectsMarkers(_ s: Any?) {
        guard let i = session.selectedTrack, i < session.doc.tracks.count else { return }
        session.mutateLight("Delete Effects Markers") { d in
            d.tracks[i].layer.removeAll { if case let .marker(m) = $0 { return m.type == MarkerKind.effectParam }; return false }
        }
    }

    @objc func editRulerMarkerItem(_ s: Any?) {
        guard let (_, _, m) = laneMarker() else { return }
        let a = NSAlert()
        a.messageText = m.type == MarkerKind.originalTempo ? "Original Tempo Marker" : "Tempo Marker"
        a.informativeText = "BPM:"
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        f.stringValue = String(format: "%.2f", m.value)
        a.accessoryView = f
        a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = f
        guard a.runModal() == .alertFirstButtonReturn, let v = Double(f.stringValue.replacingOccurrences(of: ",", with: ".")), v >= 20, v <= 300 else { return }
        setLaneMarkerValue(v)
    }

    @objc func deleteRulerMarkerItem(_ s: Any?) {
        guard let (ti, li, _) = laneMarker() else { return }
        session.mutate("Delete Tempo Marker") { d in d.tracks[ti].layer.remove(at: li) }
    }

    /// Master BPM (flechas o tecleado): cambia el tempo de la mezcla desde el cursor. Como en el
    /// original, deja marcadores de tempo: si la pista aún no tenía, uno con el tempo de antes
    /// justo detrás del cursor (lo ya sonado no cambia) y otro con el nuevo en el cursor; si ya hay
    /// uno a menos de medio segundo, lo cambia.
    func setMasterTempo(_ v: Double, at t: Double) {
        let L = session.layout
        guard let item = L.primary(at: t), item.index < session.doc.tracks.count else { return }
        let tr = session.doc.tracks[item.index]
        let src = item.toSource(t)
        let old = item.tempo(at: t)
        session.mutate("Change Master Tempo") { d in
            var layer = d.tracks[item.index].layer
            if let k = layer.firstIndex(where: { if case let .marker(m) = $0 { return m.type == MarkerKind.tempo && abs(Double(m.pos_us) * 1e-6 - src) < 0.5 }; return false }),
               case var .marker(m) = layer[k] {
                m.value = v; layer[k] = .marker(m)
            } else {
                if tr.markers(MarkerKind.tempo).isEmpty, src > 0.06 {
                    layer.append(.marker(PLMarker(type: MarkerKind.tempo, pos_us: Int64(((src - 0.05) * 1e6).rounded()), value: (old * 1000).rounded() / 1000)))
                }
                layer.append(.marker(PLMarker(type: MarkerKind.tempo, pos_us: Int64((src * 1e6).rounded()), value: v)))
            }
            d.tracks[item.index].layer = layer
        }
        Log.write("Master BPM → \(v) en \(String(format: "%.2f", t)) s (pista \(item.index + 1))")
    }

    // MARK: Nuevo en MixMeister 8

    @objc func recordMix(_ s: Any?) {
        if player.isRecording {
            let u = player.recordURL
            player.stopRecording()
            if let u { NSWorkspace.shared.activateFileViewerSelecting([u]) }
            return
        }
        let p = NSSavePanel()
        p.nameFieldStringValue = "Sesión \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")).wav"
        p.allowedContentTypes = [.wav]
        guard p.runModal() == .OK, let u = p.url else { return }
        player.startRecording(to: u)
    }
    /// Find Similar Tracks (lista y biblioteca): las que mezclan bien con la seleccionada.
    @objc func findSimilarTracks(_ s: Any?) {
        guard let i = session.selectedTrack, i < session.doc.tracks.count, let ref = session.libraryItem(for: session.doc.tracks[i]) else { NSSound.beep(); return }
        library.isHidden = false
        library.showSimilar(to: ref)
    }
    @objc func findSimilarItems(_ s: Any?) {
        guard let ref = library.firstSelectedLibraryItem else { NSSound.beep(); return }
        library.showSimilar(to: ref)
    }
    /// Tools › Order Playlist for Harmonic Flow: reordena la lista (con deshacer) para que cada pista
    /// mezcle bien con la anterior; la primera no se mueve.
    @objc func orderForFlow(_ s: Any?) {
        let items = session.doc.tracks.map { session.libraryItem(for: $0) }
        let order = Similarity.flowOrder(items)
        let before = Similarity.totalFlow(items), after = Similarity.totalFlow(order.map { items[$0] })
        Log.write(String(format: "orden por flujo: compatibilidad %.2f → %.2f", before, after))
        guard after > before + 1e-9 else { return }
        session.mutate("Order Playlist for Harmonic Flow") { d in
            d.tracks = order.map { d.tracks[$0] }
            Self.linkTransitions(&d)
        }
    }
    @objc func toggleColorWaveforms(_ s: Any?) {
        TimelineView.colorWaveforms.toggle()
        UserDefaults.standard.set(TimelineView.colorWaveforms, forKey: "MM8 Color Waveforms")
        NotificationCenter.default.post(name: .viewOptionsChanged, object: nil)
    }

    // MARK: View
    /// View › Skin: se guarda y se aplica al reiniciar (la app se vuelve a abrir sola).
    @objc func chooseSkin(_ item: NSMenuItem) {
        let sk = Skin.all[item.tag]
        guard sk.name != Theme.skin.name else { return }
        UserDefaults.standard.set(sk.name, forKey: Skin.defaultsKey)
        item.menu?.items.forEach { $0.state = $0.tag == item.tag ? .on : .off }
        let a = NSAlert()
        a.messageText = "Skin «\(sk.name)»"
        a.informativeText = "Se aplica al volver a abrir MixMeister 8. ¿Reiniciar ahora?"
        a.addButton(withTitle: "Reiniciar")
        a.addButton(withTitle: "Más tarde")
        guard a.runModal() == .alertFirstButtonReturn, confirmDiscard() else { return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        cfg.arguments = session.path.map { [$0] } ?? []
        session.dirty = false
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: cfg) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    @objc func view2Strips(_ s: Any?) { session.strips = 2 }
    @objc func view4Strips(_ s: Any?) { session.strips = 4 }
    @objc func view6Strips(_ s: Any?) { session.strips = 6 }
    @objc func view8Strips(_ s: Any?) { session.strips = 8 }
    @objc func zoomIn(_ s: Any?) { timelinePane.zoom(by: 1.5) }
    @objc func zoomOut(_ s: Any?) { timelinePane.zoom(by: 1 / 1.5) }
    @objc func timelineRulerTime(_ s: Any?) { timelinePane.timeline.rulerMeasures = false }
    @objc func timelineRulerMeasuresAndBeats(_ s: Any?) { timelinePane.timeline.rulerMeasures = true }
    @objc func viewLibrary(_ s: Any?) { library.isHidden = false; library.showTab(0); topSplit.adjustSubviews() }
    @objc func viewEffects(_ s: Any?) { library.isHidden = false; library.showTab(1); topSplit.adjustSubviews() }
    @objc func viewSongSlicer(_ s: Any?) { bottom.tabs.selectedSegment = 0; bottom.changed() }
    @objc func viewEffectsRack(_ s: Any?) { bottom.tabs.selectedSegment = 1; bottom.changed() }

    // MARK: Tools › Snap To

    private let snapCodes = ["snapTo8Measures:": 7, "snapTo4Measures:": 6, "snapTo2Measures:": 5, "snapTo1Measure:": 4,
                             "snapToHalfNote:": 3, "snapToQuarterNote:": 1, "snapToEighthNote:": 2, "snapToSixteenthNote:": 8]
    @objc func snapToBeat(_ s: Any?) { snapOn.toggle(); UserDefaults.standard.set(snapOn, forKey: "Snap To Beat") }
    /// Ajusta un instante de la mezcla a la rejilla elegida en Tools › Snap To (si Snap To Beat está activo).
    func snap(_ t: Double) -> Double {
        let L = session.layout
        guard snapOn, L.masterBPM > 0 else { return t }
        let beats: [Int: Double] = [7: 32, 6: 16, 5: 8, 4: 4, 3: 2, 1: 1, 2: 0.5, 8: 0.25]
        let step = (beats[snapType] ?? 1) * 60 / L.masterBPM
        return L.barOrigin + ((t - L.barOrigin) / step).rounded() * step
    }
    private func setSnap(_ sel: String) { snapType = snapCodes[sel] ?? 1; UserDefaults.standard.set(snapType, forKey: "Snap Position Type") }
    @objc func snapTo8Measures(_ s: Any?) { setSnap("snapTo8Measures:") }
    @objc func snapTo4Measures(_ s: Any?) { setSnap("snapTo4Measures:") }
    @objc func snapTo2Measures(_ s: Any?) { setSnap("snapTo2Measures:") }
    @objc func snapTo1Measure(_ s: Any?) { setSnap("snapTo1Measure:") }
    @objc func snapToHalfNote(_ s: Any?) { setSnap("snapToHalfNote:") }
    @objc func snapToQuarterNote(_ s: Any?) { setSnap("snapToQuarterNote:") }
    @objc func snapToEighthNote(_ s: Any?) { setSnap("snapToEighthNote:") }
    @objc func snapToSixteenthNote(_ s: Any?) { setSnap("snapToSixteenthNote:") }

    // MARK: Help

    @objc func help(_ s: Any?) {
        let a = NSAlert()
        a.messageText = "MixMeister 8 — versión \(Engine.version)"
        a.informativeText = "Continuación de MixMeister Fusion 7.8 con la misma operativa y los mismos ficheros (.mmp, .mxm y la biblioteca de MixMeister)."
        a.runModal()
    }

    private func show(_ e: Error, _ title: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = e.localizedDescription
        a.alertStyle = .warning
        a.runModal()
    }
}

/// La mezcla por defecto de una pista nueva, como la monta MixMeister al añadirla a la lista:
/// ancla de entrada en el primer tiempo de la ventana de entrada, de salida al principio de la
/// última ventana de 32 tiempos, y los volúmenes de Beatmix 8 (transitions.xml).
enum DefaultMix {
    static func track(for it: LibraryItem) -> PLTrack {
        let a = try? Engine.analyze(path: it.path)
        let bpm = a?.bpm ?? (it.bpm > 0 ? it.bpm : 120)
        let beat = 60 / bpm
        let first = a?.first_beat_s ?? 0
        let len = a?.seconds ?? it.seconds
        let entry = first + (a?.entry_beat ?? 0) * beat
        let exit = a.map { first + $0.exit_beat * beat } ?? max(entry, len - 32 * beat)
        let us = { (t: Double) in Int64((t * 1e6).rounded()) }
        var layer: [PLLayerItem] = [
            .marker(PLMarker(type: MarkerKind.introAnchor, pos_us: us(entry))),
            .marker(PLMarker(type: MarkerKind.outroAnchor, pos_us: us(exit))),
            .marker(PLMarker(type: MarkerKind.autoVolumeIn, pos_us: us(entry - 0.25 * beat), value: -50)),
            .marker(PLMarker(type: MarkerKind.autoVolumeIn, pos_us: us(entry), value: -6)),
            .marker(PLMarker(type: MarkerKind.autoVolumeIn, pos_us: us(entry + 32 * beat), value: 0)),
            .marker(PLMarker(type: MarkerKind.autoVolume, pos_us: us(exit), value: 0)),
            .marker(PLMarker(type: MarkerKind.autoVolume, pos_us: us(exit + 32 * beat), value: -6)),
            .marker(PLMarker(type: MarkerKind.autoVolume, pos_us: us(exit + 32.25 * beat), value: -50)),
        ]
        layer.append(.segment(PLSegment(reversed: false, class: 1, src_start_us: 0, src_end_us: us(len), anchor_us: 0,
                                        overlay_measure: 0, overlay_fraction: 0, overlay_rate: 1)))
        layer.append(.marker(PLMarker(type: MarkerKind.originalTempo, pos_us: us(first), value: bpm)))
        var beats: [Int64] = []
        var t = first
        while t < len { beats.append(us(t)); t += 4 * beat * 8 }   // un marcador cada 8 compases, como el Beat Slicer
        return PLTrack(path: it.path, transition_in: nil, transition_out: nil, file_id: it.fileID, bpm: bpm, original_bpm: bpm,
                       bar_us: us(4 * beat), length_us: us(len), overlay: false, key_semitones: 0, beat_markers_us: beats,
                       effects: [], layer: layer)
    }
}
