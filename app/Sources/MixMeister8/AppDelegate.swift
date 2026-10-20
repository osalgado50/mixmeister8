import AppKit
import UniformTypeIdentifiers

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
        NSApp.appearance = NSAppearance(named: .darkAqua)
        buildMenus()
        buildWindow()
        playlist.table.target = self
        playlist.table.doubleAction = #selector(playFromPlaylistRow(_:))
        session.loadLibrary()
        session.newPlaylist()
        if let last = RecentFiles.list.first, FileManager.default.fileExists(atPath: last), CommandLine.arguments.count < 2 {
            try? session.open(last)
        }
        for a in CommandLine.arguments.dropFirst() where a.lowercased().hasSuffix(".mmp") { openFile(a) }
        updateTitle()
        NotificationCenter.default.addObserver(forName: .playlistChanged, object: nil, queue: .main) { [weak self] _ in self?.updateTitle() }
        // Verificación sin pantalla: MixMeister8 --snapshot salida.png [lista.mmp] [--select N] [--zoom Z]
        let args = CommandLine.arguments
        // Prueba de audio: MixMeister8 lista.mmp --playtest INSTANTE  (suena 4 s y anota niveles)
        if let i = args.firstIndex(of: "--playtest"), i + 1 < args.count, let t0 = Double(args[i + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                Player.shared.play(from: t0)
                var n = 0
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { tm in
                    let p = Player.shared
                    print(String(format: "PLAYTEST pos=%.2f playing=%d L=%.3f R=%.3f chains_ok", p.position, p.isPlaying ? 1 : 0, p.peakL, p.peakR))
                    fflush(stdout)
                    n += 1
                    if n >= 8 { tm.invalidate(); p.stop(); NSApp.terminate(nil) }
                }
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

    func application(_ sender: NSApplication, openFile filename: String) -> Bool { openFile(filename); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ s: NSApplication) -> NSApplication.TerminateReply { confirmDiscard() ? .terminateNow : .terminateCancel }
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
        case "viewLibrary:": item.state = library.isHidden ? .off : .on
        case "viewSongSlicer:": item.state = bottom.tabs.selectedSegment == 0 ? .on : .off
        case "viewEffectsRack:": item.state = bottom.tabs.selectedSegment == 1 ? .on : .off
        case "savePlayList:", "savePlayListAs:": return !session.doc.tracks.isEmpty || session.path != nil
        case "delete:", "del:", "tweaks:", "adjustTrackSettings:", "editTag:":
            return session.selectedTrack != nil && (sel == "delete:" || sel == "del:")
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
    @objc func playPause(_ s: Any?) { player.toggle(from: timelinePane.timeline.playhead) }
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

    // MARK: View

    @objc func view2Strips(_ s: Any?) { session.strips = 2 }
    @objc func view4Strips(_ s: Any?) { session.strips = 4 }
    @objc func view6Strips(_ s: Any?) { session.strips = 6 }
    @objc func view8Strips(_ s: Any?) { session.strips = 8 }
    @objc func zoomIn(_ s: Any?) { timelinePane.zoom(by: 1.5) }
    @objc func zoomOut(_ s: Any?) { timelinePane.zoom(by: 1 / 1.5) }
    @objc func timelineRulerTime(_ s: Any?) { timelinePane.timeline.rulerMeasures = false }
    @objc func timelineRulerMeasuresAndBeats(_ s: Any?) { timelinePane.timeline.rulerMeasures = true }
    @objc func viewLibrary(_ s: Any?) { library.isHidden.toggle(); topSplit.adjustSubviews() }
    @objc func viewEffects(_ s: Any?) { library.isHidden = false }
    @objc func viewSongSlicer(_ s: Any?) { bottom.tabs.selectedSegment = 0; bottom.changed() }
    @objc func viewEffectsRack(_ s: Any?) { bottom.tabs.selectedSegment = 1; bottom.changed() }

    // MARK: Tools › Snap To

    private let snapCodes = ["snapTo8Measures:": 7, "snapTo4Measures:": 6, "snapTo2Measures:": 5, "snapTo1Measure:": 4,
                             "snapToHalfNote:": 3, "snapToQuarterNote:": 1, "snapToEighthNote:": 2, "snapToSixteenthNote:": 8]
    @objc func snapToBeat(_ s: Any?) { snapOn.toggle(); UserDefaults.standard.set(snapOn, forKey: "Snap To Beat") }
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
