import AppKit

extension Notification.Name {
    static let playlistChanged = Notification.Name("mm8.playlistChanged")
    static let libraryChanged = Notification.Name("mm8.libraryChanged")
    static let selectionChanged = Notification.Name("mm8.selectionChanged")
    static let waveformReady = Notification.Name("mm8.waveformReady")
    static let viewOptionsChanged = Notification.Name("mm8.viewOptionsChanged")
    static let effectsChanged = Notification.Name("mm8.effectsChanged")
}

/// Estado de la sesión: la lista abierta, la biblioteca y lo que hay seleccionado.
final class Session {
    static let shared = Session()

    let catalog = Catalog()
    private(set) var engineDoc = EngineDocument()
    private(set) var doc = PLDocument(format: "mmp", version: nil, master_gain_db: 0, master_effects: [], tracks: [])
    private(set) var path: String?
    private(set) var layout = MixLayout.empty
    var dirty = false
    /// Parámetro de efecto que se ve con marcadores en la línea de tiempo (lo elige el rack).
    struct TrackedParam: Equatable { var track: Int; var slot: UInt32; var param: Int }
    var trackedParam: TrackedParam?
    var selectedTrack: Int? { didSet { if oldValue != selectedTrack { NotificationCenter.default.post(name: .selectionChanged, object: nil) } } }
    var strips: Int = {
        let k = "Number of Strips in the Timeline"
        let v = (UserDefaults.standard.object(forKey: k) as? Int) ?? (UserDefaults(suiteName: "com.mixmeister.MixMeisterStudio")?.object(forKey: k) as? Int) ?? 4
        return [2, 4, 6, 8].contains(v) ? v : 4
    }() {
        didSet { UserDefaults.standard.set(strips, forKey: "Number of Strips in the Timeline"); relayout() }
    }
    /// Dónde está de verdad el audio de cada pista (la ruta guardada puede ser de otra máquina).
    private(set) var resolved: [String?] = []

    var title: String { path.map { ($0 as NSString).lastPathComponent } ?? "untitled" }

    func loadLibrary() {
        guard let p = Catalog.findMixMeisterCatalog() else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.catalog.load(from: p)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .libraryChanged, object: nil)
                    if !self.doc.tracks.isEmpty { self.resolveAll(); self.relayout() }
                }
            } catch { NSLog("MixMeister 8: biblioteca: \(error)") }
        }
    }

    func newPlaylist() {
        Player.shared.stop()
        FxPool.shared.reset()
        engineDoc = EngineDocument()
        doc = PLDocument(format: "mmp", version: nil, master_gain_db: 0, master_effects: [], tracks: [])
        path = nil
        dirty = false
        selectedTrack = nil
        resolveAll()
        relayout()
    }

    func open(_ p: String) throws {
        let e = try EngineDocument(path: p)
        let d = try e.read()
        Player.shared.stop()
        FxPool.shared.reset()
        engineDoc = e
        doc = d
        path = p
        dirty = false
        selectedTrack = nil
        RecentFiles.add(p)
        resolveAll()
        relayout()
    }

    func save(to p: String) throws {
        try engineDoc.write(doc)
        try engineDoc.save(to: p)
        doc = try engineDoc.read()
        path = p
        dirty = false
        RecentFiles.add(p)
        NotificationCenter.default.post(name: .playlistChanged, object: nil)
    }

    let undo = UndoManager()

    /// Cambia la lista (con deshacer) y vuelve a calcular la mezcla.
    func mutate(_ name: String, _ change: (inout PLDocument) -> Void) {
        let before = doc
        change(&doc)
        let after = doc
        undo.registerUndo(withTarget: self) { s in s.restore(before, redo: after, name: name) }
        undo.setActionName(name)
        dirty = true
        resolveAll()
        relayout()
    }
    /// Cambios que no mueven nada en la mezcla (parámetros de efectos, automatización, compases del
    /// Song Slicer sin cambio de tempo): con deshacer, sin recolocar y sin cortar la reproducción.
    /// `coalesce`: varios cambios seguidos con el mismo nombre (girar un knob) son un solo deshacer.
    private var lastLight: (name: String, at: Date)?
    func mutateLight(_ name: String, coalesce: Bool = false, _ change: (inout PLDocument) -> Void) {
        let before = doc
        change(&doc)
        let after = doc
        let join = coalesce && lastLight?.name == name && Date().timeIntervalSince(lastLight!.at) < 1.0
        if !join { undo.registerUndo(withTarget: self) { s in s.restore(before, redo: after, name: name) }; undo.setActionName(name) }
        lastLight = (name, Date())
        dirty = true
        Player.shared.effectsChanged()
        NotificationCenter.default.post(name: .effectsChanged, object: nil)
        NotificationCenter.default.post(name: .playlistChanged, object: nil)
    }

    private func restore(_ d: PLDocument, redo: PLDocument, name: String) {
        doc = d
        undo.registerUndo(withTarget: self) { s in s.restore(redo, redo: d, name: name) }
        undo.setActionName(name)
        dirty = true
        resolveAll()
        relayout()
    }

    func relayout() {
        layout = MixLayout(doc: doc, strips: strips)
        // Si está sonando, la mezcla nueva sigue sonando desde el mismo punto.
        if Player.shared.isPlaying { DispatchQueue.main.async { Player.shared.play(from: Player.shared.position) } }
        NotificationCenter.default.post(name: .playlistChanged, object: nil)
        for (i, r) in resolved.enumerated() { if let r { Waveforms.shared.request(r, track: i) } }
    }

    // MARK: Encontrar el audio

    private func resolveAll() {
        let base = path.map { ($0 as NSString).deletingLastPathComponent }
        resolved = doc.tracks.map { TrackLocator.locate($0, catalog: catalog, near: base) }
    }

    func audioPath(_ i: Int) -> String? { i < resolved.count ? resolved[i] : nil }
    func libraryItem(for t: PLTrack) -> LibraryItem? {
        catalog.item(fileID: t.file_id) ?? catalog.items.first { $0.path.hasSuffix("/" + t.fileName) }
    }
}

/// Busca el audio de una pista como haría MixMeister y algo más: la ruta tal cual; el mismo
/// identificador de fichero en la biblioteca; el mismo nombre junto a la lista (o una carpeta
/// por encima); y por último el nombre en la biblioteca. Funciona con rutas de Windows.
enum TrackLocator {
    static func locate(_ t: PLTrack, catalog: Catalog, near: String?) -> String? {
        let fm = FileManager.default
        if fm.fileExists(atPath: t.path) { return t.path }
        if let it = catalog.item(fileID: t.file_id), fm.fileExists(atPath: it.path) { return it.path }
        let name = t.fileName
        if let near {
            for dir in [near, (near as NSString).deletingLastPathComponent] {
                let c = (dir as NSString).appendingPathComponent(name)
                if fm.fileExists(atPath: c) { return c }
            }
            if let hit = search(name, in: near, depth: 2) { return hit }
        }
        if let it = catalog.items.first(where: { ($0.path as NSString).lastPathComponent.caseInsensitiveCompare(name) == .orderedSame }),
           fm.fileExists(atPath: it.path) { return it.path }
        return nil
    }

    private static func search(_ name: String, in dir: String, depth: Int) -> String? {
        guard depth > 0, let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return nil }
        for i in items where i.caseInsensitiveCompare(name) == .orderedSame { return (dir as NSString).appendingPathComponent(i) }
        for i in items {
            let p = (dir as NSString).appendingPathComponent(i)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue, let hit = search(name, in: p, depth: depth - 1) { return hit }
        }
        return nil
    }
}

enum RecentFiles {
    static let key = "RecentFiles"
    static var list: [String] {
        if let mine = UserDefaults.standard.stringArray(forKey: key) { return mine }
        return UserDefaults(suiteName: "com.mixmeister.MixMeisterStudio")?.stringArray(forKey: key) ?? []
    }
    static func add(_ p: String) {
        var l = list.filter { $0 != p }
        l.insert(p, at: 0)
        UserDefaults.standard.set(Array(l.prefix(10)), forKey: key)
        NSDocumentController.shared.noteNewRecentDocumentURL(URL(fileURLWithPath: p))
    }
    static func clear() { UserDefaults.standard.set([String](), forKey: key) }
}

/// Formas de onda calculadas en segundo plano con el motor.
final class Waveforms {
    static let shared = Waveforms()
    private var cache: [String: (peaks: [Float], seconds: Double)] = [:]
    private var pending: Set<String> = []
    private let queue = DispatchQueue(label: "mm8.waveforms", qos: .utility, attributes: .concurrent)
    static let bins = 4096

    func get(_ path: String) -> (peaks: [Float], seconds: Double)? { cache[path] }

    func request(_ path: String, track: Int) {
        guard cache[path] == nil, !pending.contains(path) else { return }
        pending.insert(path)
        queue.async {
            let r = try? Engine.peaks(path: path, bins: Self.bins)
            DispatchQueue.main.async {
                self.pending.remove(path)
                if let r { self.cache[path] = r }
                NotificationCenter.default.post(name: .waveformReady, object: path)
            }
        }
    }
}
