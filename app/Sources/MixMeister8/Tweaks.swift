import AppKit

// Tweaks (Tools › Tweaks…, ⌃W; Quick Save Tweak, ⌃S): los ajustes de una pista guardados por canción
// para volver a usarlos. Comprobado en MixMeister 7.8 (experimentos del 29-10-2026, docs/spec/mmp.md):
//  · Un Tweak es la pista tal como va en la lista (RIFF «MMDM»: segmentos, volumen, transición, tipo
//    de pista, etiquetas, EQ, anclas, tempo, efectos y su automatización). Lo genera el motor.
//  · Diálogo: «"Título" by Artista», lista de Tweaks propios por orden alfabético y luego los tres
//    presets (Beatmix, Simple, No Transition); segunda columna «(Default)». Load aplica al momento;
//    Save, Rename y Delete solo para Tweaks propios (los presets no se pueden borrar).
//  · Quick Save Tweak guarda «Quick Save» y lo pone por defecto.
//  · Set As Default: la canción entra con ese Tweak al añadirla a una lista.
// MixMeister 8 no escribe en la biblioteca de MixMeister: guarda sus Tweaks en
// ~/Library/Application Support/MixMeister 8/Tweaks/<identificador del audio>/ (el bloque MMDM tal
// cual, más un índice) y la primera vez copia ahí los que tuviera la canción en MixMeister 7.8.

enum TweakStore {
    static let presets = ["Preset - Beatmix", "Preset - Simple", "Preset - No Transition"]
    static let quickSave = "Quick Save"

    struct Index: Codable {
        var tweaks: [Entry] = []
        var defaultName: String?
        struct Entry: Codable { var name: String; var file: String }
    }

    static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MixMeister 8/Tweaks")
    }
    private static func dir(_ fileID: String) -> URL { root.appendingPathComponent(fileID.uppercased()) }
    private static func indexURL(_ fileID: String) -> URL { dir(fileID).appendingPathComponent("index.json") }

    /// Índice de la canción; la primera vez, con los Tweaks que tuviera en MixMeister 7.8.
    static func index(_ fileID: String) -> Index {
        if let d = try? Data(contentsOf: indexURL(fileID)), let i = try? JSONDecoder().decode(Index.self, from: d) { return i }
        var i = Index()
        let imported = Session.shared.catalog.tweaks[fileID.uppercased()] ?? []
        if !imported.isEmpty {
            for t in imported {
                let f = UUID().uuidString + ".mmdm"
                try? FileManager.default.createDirectory(at: dir(fileID), withIntermediateDirectories: true)
                if (try? t.data.write(to: dir(fileID).appendingPathComponent(f))) != nil { i.tweaks.append(.init(name: t.name, file: f)) }
                if t.isDefault { i.defaultName = t.name }
            }
            write(i, fileID)
        }
        return i
    }
    private static func write(_ i: Index, _ fileID: String) {
        try? FileManager.default.createDirectory(at: dir(fileID), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(i) { try? d.write(to: indexURL(fileID)) }
        if tweakedCache != nil { if i.tweaks.isEmpty { tweakedCache!.remove(fileID.uppercased()) } else { tweakedCache!.insert(fileID.uppercased()) } }
        NotificationCenter.default.post(name: .tweaksChanged, object: fileID)
    }

    /// Nombres en el orden del diálogo: propios por orden alfabético y luego los presets.
    static func names(_ fileID: String) -> [String] {
        index(fileID).tweaks.map(\.name).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } + presets
    }
    /// Canciones con Tweaks propios (columna TWEAKED, «>» como en el original). En memoria: se monta
    /// una vez (almacén de MixMeister 8 + biblioteca de MixMeister) y se actualiza al guardar.
    private static var tweakedCache: Set<String>?
    static func resetCache() { tweakedCache = nil }
    static func hasTweaks(_ fileID: String) -> Bool {
        if tweakedCache == nil {
            var set = Set(Session.shared.catalog.tweaks.filter { !$0.value.isEmpty }.keys)
            for d in (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [] {
                if let x = try? Data(contentsOf: root.appendingPathComponent(d).appendingPathComponent("index.json")),
                   let i = try? JSONDecoder().decode(Index.self, from: x) {
                    if i.tweaks.isEmpty { set.remove(d) } else { set.insert(d) }
                }
            }
            tweakedCache = set
        }
        return tweakedCache!.contains(fileID.uppercased())
    }
    static func data(_ fileID: String, _ name: String) -> Data? {
        guard let e = index(fileID).tweaks.first(where: { $0.name == name }) else { return nil }
        return try? Data(contentsOf: dir(fileID).appendingPathComponent(e.file))
    }
    static func save(_ fileID: String, _ name: String, _ blob: Data) throws {
        var i = index(fileID)
        let f = i.tweaks.first { $0.name == name }?.file ?? (UUID().uuidString + ".mmdm")
        try FileManager.default.createDirectory(at: dir(fileID), withIntermediateDirectories: true)
        try blob.write(to: dir(fileID).appendingPathComponent(f))
        if !i.tweaks.contains(where: { $0.name == name }) { i.tweaks.append(.init(name: name, file: f)) }
        write(i, fileID)
    }
    static func rename(_ fileID: String, _ old: String, to new: String) {
        var i = index(fileID)
        guard let k = i.tweaks.firstIndex(where: { $0.name == old }), !i.tweaks.contains(where: { $0.name == new }) else { return }
        i.tweaks[k].name = new
        if i.defaultName == old { i.defaultName = new }
        write(i, fileID)
    }
    static func delete(_ fileID: String, _ name: String) {
        var i = index(fileID)
        guard let k = i.tweaks.firstIndex(where: { $0.name == name }) else { return }
        try? FileManager.default.removeItem(at: dir(fileID).appendingPathComponent(i.tweaks[k].file))
        i.tweaks.remove(at: k)
        if i.defaultName == name { i.defaultName = nil }
        write(i, fileID)
    }
    static func setDefault(_ fileID: String, _ name: String?) {
        var i = index(fileID)
        i.defaultName = name
        write(i, fileID)
    }
    static func defaultName(_ fileID: String) -> String? { index(fileID).defaultName }

    // MARK: Aplicar

    /// La pista `t` con el Tweak o preset `name` (nil si no se puede).
    static func applied(_ name: String, to t: PLTrack, item: LibraryItem?) -> PLTrack? {
        if presets.contains(name) { return preset(name, for: t, item: item) }
        guard let blob = data(t.file_id, name), var n = try? Session.shared.engineDoc.addTweakTrack(blob) else { return nil }
        n.path = t.path                       // la ruta de esta lista (el Tweak guarda la de cuando se hizo)
        return n
    }

    /// Presets: la mezcla por defecto de la canción (como recién añadida) con ese estilo.
    /// Simple / No Transition: sin volúmenes automáticos ni tempo, anclas al principio y al final
    /// del sonido, estilo 0x11 (observado con Preset - Simple en MixMeister 7.8).
    static func preset(_ name: String, for t: PLTrack, item: LibraryItem?) -> PLTrack? {
        guard let it = item ?? Session.shared.libraryItem(for: t) else { return nil }
        var n = DefaultMix.track(for: it)
        n.path = t.path
        n.transition_in = t.transition_in
        switch name {
        case "Preset - Beatmix":
            n.mix_style = 0x22
            n.transition_out = t.transition_out == nil ? nil : "Beatmix 8"
        default:
            n.mix_style = 0x11
            n.transition_out = t.transition_out == nil ? nil : (name == "Preset - Simple" ? "Simple Crossfade" : "No Transition")
            let a = try? Engine.analyze(path: it.path)
            let beat = 60 / (a?.bpm ?? max(1, it.bpm))
            let first = (a?.first_beat_s ?? 0) + (a?.first_sounding_beat ?? 0) * beat
            let len = Double(n.length_us ?? 0) * 1e-6
            n.layer = n.layer.compactMap { li -> PLLayerItem? in
                guard case var .marker(m) = li else { return li }
                switch m.type {
                case MarkerKind.autoVolume, MarkerKind.autoVolumeIn, MarkerKind.tempo: return nil
                case MarkerKind.introAnchor, MarkerKind.originalTempo: m.pos_us = Int64(max(0, first) * 1e6)
                case MarkerKind.outroAnchor: m.pos_us = Int64(max(first, len - 16 * beat) * 1e6)
                default: break
                }
                return .marker(m)
            }
        }
        return n
    }

    /// Pone `n` en el lugar de la pista `i`: los efectos del Tweak toman números de instancia libres
    /// en la lista (y sus marcadores con ellos).
    static func place(_ n: PLTrack, at i: Int, in d: inout PLDocument) {
        var n = n
        let used = d.master_effects.map(\.slot) + d.tracks.enumerated().filter { $0.offset != i }.flatMap { $0.element.effects.map(\.slot) }
        var next = (used.max() ?? 0) + 1
        var map: [UInt32: UInt32] = [:]
        for k in n.effects.indices { map[n.effects[k].slot] = next; n.effects[k].slot = next; next += 1 }
        n.layer = n.layer.map { li in
            guard case var .marker(m) = li, m.type == MarkerKind.effectParam, let s = map[m.flag >> 12] else { return li }
            m.flag = s << 12 | (m.flag & 0xFFF)
            return .marker(m)
        }
        if let v = n.fx_view_slot, v > 0, let s = map[UInt32(v)] { n.fx_view_slot = Int32(s) }
        n.transition_in = d.tracks[i].transition_in
        d.tracks[i] = n
    }
}

extension Notification.Name {
    static let tweaksChanged = Notification.Name("mm8.tweaksChanged")
}

/// Diálogo Tweaks (TweaksDlg.nib del original): mismos textos y botones.
final class TweaksDialog: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let fileID: String
    private let track: Int?               // pista de la lista (nil: desde la biblioteca)
    private let item: LibraryItem?
    private var names: [String] = []
    private let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
    private let table = NSTableView()
    private var buttons: [String: NSButton] = [:]
    private var loads = 0

    init(track: Int?, item: LibraryItem?) {
        let s = Session.shared
        self.track = track
        self.item = item ?? track.flatMap { s.libraryItem(for: s.doc.tracks[$0]) }
        fileID = track.map { s.doc.tracks[$0].file_id } ?? item?.fileID ?? ""
        super.init()
    }

    func run() {
        names = TweakStore.names(fileID)
        panel.title = "Tweaks"
        let v = panel.contentView!
        let s = Session.shared
        let title = item.map { "\"\($0.title)\" by \($0.artist.isEmpty ? "unknown" : $0.artist)" }
            ?? track.map { "\"\(s.doc.tracks[$0].title)\" by unknown" } ?? ""
        let header = NSTextField(labelWithString: title)
        header.frame = NSRect(x: 14, y: 270, width: 372, height: 18)
        header.lineBreakMode = .byTruncatingTail
        v.addSubview(header)
        let c1 = NSTableColumn(identifier: .init("name")); c1.width = 150; c1.title = ""
        let c2 = NSTableColumn(identifier: .init("def")); c2.width = 80; c2.title = ""
        table.addTableColumn(c1); table.addTableColumn(c2)
        table.headerView = nil
        table.dataSource = self; table.delegate = self
        table.rowHeight = 17
        table.target = self; table.doubleAction = #selector(load)
        let sc = NSScrollView(frame: NSRect(x: 14, y: 50, width: 250, height: 214))
        sc.documentView = table; sc.hasVerticalScroller = true; sc.borderType = .bezelBorder
        v.addSubview(sc)
        var y: CGFloat = 244
        for (key, t, sel) in [("load", "(L)oad", #selector(load)), ("save", "(S)ave", #selector(save)), ("saveas", "Save (A)s...", #selector(saveAs)),
                              ("default", "Set As (D)efault", #selector(setDefault)), ("rename", "(R)ename", #selector(rename)), ("delete", "(Del)ete", #selector(delete))] {
            let b = NSButton(title: t, target: self, action: sel)
            b.frame = NSRect(x: 276, y: y, width: 112, height: 24)
            b.bezelStyle = .rounded
            v.addSubview(b); buttons[key] = b
            y -= 30
        }
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel)); cancel.frame = NSRect(x: 168, y: 12, width: 100, height: 26)
        let ok = NSButton(title: "OK", target: self, action: #selector(ok)); ok.frame = NSRect(x: 276, y: 12, width: 112, height: 26)
        cancel.bezelStyle = .rounded; ok.bezelStyle = .rounded
        ok.keyEquivalent = "\r"; cancel.keyEquivalent = "\u{1b}"
        v.addSubview(cancel); v.addSubview(ok)
        table.reloadData()
        table.selectRowIndexes([0], byExtendingSelection: false)
        update()
        panel.center()
        NSApp.runModal(for: panel)
        panel.orderOut(nil)
    }

    private var selected: String? { table.selectedRow >= 0 && table.selectedRow < names.count ? names[table.selectedRow] : nil }
    private func update() {
        let own = selected.map { !TweakStore.presets.contains($0) } ?? false
        buttons["load"]?.isEnabled = track != nil && selected != nil
        buttons["save"]?.isEnabled = track != nil && own
        buttons["saveas"]?.isEnabled = track != nil
        buttons["default"]?.isEnabled = selected != nil
        buttons["rename"]?.isEnabled = own
        buttons["delete"]?.isEnabled = own
    }
    private func reload(select name: String?) {
        names = TweakStore.names(fileID)
        table.reloadData()
        if let name, let r = names.firstIndex(of: name) { table.selectRowIndexes([r], byExtendingSelection: false) }
        update()
    }

    func numberOfRows(in t: NSTableView) -> Int { names.count }
    func tableView(_ t: NSTableView, viewFor c: NSTableColumn?, row: Int) -> NSView? {
        let isName = c?.identifier.rawValue == "name"
        let txt = isName ? names[row] : (TweakStore.defaultName(fileID) == names[row] ? "(Default)" : "")
        let f = NSTextField(labelWithString: txt)
        f.font = .systemFont(ofSize: 11)
        return f
    }
    func tableViewSelectionDidChange(_ n: Notification) { update() }

    private static func askName(_ title: String, _ value: String) -> String? {
        let a = NSAlert()
        a.messageText = title
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        f.stringValue = value
        a.accessoryView = f
        a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = f
        guard a.runModal() == .alertFirstButtonReturn else { return nil }
        let n = f.stringValue.trimmingCharacters(in: .whitespaces)
        return n.isEmpty || TweakStore.presets.contains(n) ? nil : n
    }

    @objc private func load() {
        guard let track, let name = selected else { return }
        if TweaksActions.load(name, track: track) { loads += 1 }
    }
    @objc private func save() {
        guard let track, let name = selected, !TweakStore.presets.contains(name) else { return }
        TweaksActions.save(name, track: track)
        reload(select: name)
    }
    @objc private func saveAs() {
        guard let track, let name = Self.askName("Tweak Name:", "") else { return }
        TweaksActions.save(name, track: track)
        reload(select: name)
    }
    @objc private func setDefault() {
        guard let name = selected else { return }
        TweakStore.setDefault(fileID, name)
        reload(select: name)
    }
    @objc private func rename() {
        guard let old = selected, !TweakStore.presets.contains(old), let new = Self.askName("Tweak Name:", old) else { return }
        TweakStore.rename(fileID, old, to: new)
        reload(select: new)
    }
    @objc private func delete() {
        guard let name = selected, !TweakStore.presets.contains(name) else { return }
        TweakStore.delete(fileID, name)
        reload(select: nil)
    }
    @objc private func ok() { NSApp.stopModal() }
    /// Cancel deshace lo cargado en el diálogo (los Tweaks guardados se quedan).
    @objc private func cancel() {
        for _ in 0..<loads where Session.shared.undo.canUndo { Session.shared.undo.undo() }
        NSApp.stopModal()
    }
}

enum TweaksActions {
    /// Guarda la pista `track` como Tweak `name` de su canción.
    @discardableResult
    static func save(_ name: String, track: Int) -> Bool {
        let s = Session.shared
        guard track < s.doc.tracks.count else { return false }
        do {
            try s.syncEngine()
            try TweakStore.save(s.doc.tracks[track].file_id, name, s.engineDoc.tweakBlob(track: track))
            return true
        } catch {
            Log.write("Tweak \(name): no se pudo guardar: \(error)")
            return false
        }
    }
    @discardableResult
    static func load(_ name: String, track: Int) -> Bool {
        let s = Session.shared
        guard track < s.doc.tracks.count, let n = TweakStore.applied(name, to: s.doc.tracks[track], item: nil) else { return false }
        s.mutate("Load Tweak") { d in TweakStore.place(n, at: track, in: &d) }
        return true
    }
    /// Quick Save Tweak: «Quick Save», y queda por defecto.
    static func quickSave(track: Int) {
        let s = Session.shared
        guard track < s.doc.tracks.count, save(TweakStore.quickSave, track: track) else { return }
        TweakStore.setDefault(s.doc.tracks[track].file_id, TweakStore.quickSave)
    }
    /// Al añadir canciones a la lista: la que tenga un Tweak por defecto entra con él.
    static func withDefaults(_ tracks: [PLTrack], items: [LibraryItem]) -> [PLTrack] {
        zip(tracks, items).map { t, it in
            guard let def = TweakStore.defaultName(it.fileID), let n = TweakStore.applied(def, to: t, item: it) else { return t }
            var n2 = n
            n2.transition_in = nil; n2.transition_out = nil
            return n2
        }
    }
}
