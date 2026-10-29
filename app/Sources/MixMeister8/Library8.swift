import AppKit
import AudioToolbox
import CryptoKit

// Biblioteca de MixMeister 8 (File › Add Files to Library…, el botón ⊕ de la biblioteca, arrastrar
// desde el Finder). Como el original (manual, «Get Your Music Ready»): las canciones entran al
// momento y se analizan en segundo plano —tempo, tiempos, compás, tonalidad—; el BPM y la tonalidad
// aparecen al terminar cada una. MixMeister 8 no escribe en la biblioteca de MixMeister: guarda las
// suyas en ~/Library/Application Support/MixMeister 8/Library.json y las muestra junto a aquellas.
// El análisis va en paralelo (todos los núcleos menos dos) y queda en caché por fichero: añadir la
// canción a una lista ya no vuelve a analizarla.

/// Caché en disco del análisis del motor, por fichero (ruta, tamaño, fecha) y versión del análisis.
enum AnalysisCache {
    /// Subir al cambiar el motor de análisis (las cifras guardadas dejan de valer).
    static let version = "a3"
    private static let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/es.mixmeister8/analysis")
    private static func url(_ path: String) -> URL? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: path),
              let size = a[.size] as? Int64, let mod = a[.modificationDate] as? Date else { return nil }
        var h: UInt64 = 1469598103934665603
        for b in "\(version)|\(path)|\(size)|\(mod.timeIntervalSince1970)".utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return dir.appendingPathComponent(String(format: "%016llx.json", h))
    }
    static func get(_ path: String) -> TrackAnalysis? {
        guard let u = url(path), let d = try? Data(contentsOf: u) else { return nil }
        return try? JSONDecoder().decode(TrackAnalysis.self, from: d)
    }
    static func put(_ path: String, _ a: TrackAnalysis) {
        guard let u = url(path), let d = try? JSONEncoder().encode(a) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? d.write(to: u)
    }
}

final class Library8 {
    static let shared = Library8()

    struct Entry: Codable {
        var path: String
        var fileID: String
        var title: String, artist: String, album: String, genre: String, composer: String, year: String, comments: String
        var trackNumber: Int
        var bitrate: Int
        var dateAdded: Date
        var seconds: Double?
        var bpm: Double?
        var keyTonic: Int?
        var keyMinor: Bool?
        var failed: Bool?
    }
    private struct Store: Codable { var entries: [Entry] = []; var monitored: [String] = [] }

    /// MM8_LIBRARY: otra ruta (pruebas: no tocar la biblioteca de verdad).
    private let url: URL = {
        if let p = ProcessInfo.processInfo.environment["MM8_LIBRARY"] { return URL(fileURLWithPath: p) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MixMeister 8/Library.json")
    }()
    private var store = Store()
    private let queue = OperationQueue()
    private(set) var total = 0, done = 0
    private var started = Date()
    static let extensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "aifc", "flac", "caf"]

    private init() {
        queue.maxConcurrentOperationCount = max(1, ProcessInfo.processInfo.activeProcessorCount - 2)
        queue.qualityOfService = .utility
        if let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Store.self, from: d) { store = s }
    }

    var monitored: [String] { store.monitored }
    var isBusy: Bool { done < total }

    /// Al arrancar: lo de MixMeister 8 a la biblioteca, lo pendiente a analizar y las carpetas vigiladas.
    func start() {
        publish()
        for e in store.entries where e.bpm == nil && e.failed != true { enqueue(e.path) }
        if !store.monitored.isEmpty { scanMonitored(); watch() }
    }

    // MARK: Añadir

    /// Ficheros o carpetas (recorre subcarpetas). Devuelve cuántas canciones nuevas.
    @discardableResult
    func add(_ urls: [URL]) -> Int {
        var files: [String] = []
        let fm = FileManager.default
        for u in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: u.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue, let en = fm.enumerator(at: u, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for case let f as URL in en where Self.extensions.contains(f.pathExtension.lowercased()) { files.append(f.path) }
            } else if Self.extensions.contains(u.pathExtension.lowercased()) { files.append(u.path) }
        }
        let have = Set(store.entries.map(\.path))
        let cat = Session.shared.catalog
        let new = files.filter { !have.contains($0) && !cat.hasPath($0) }
        guard !new.isEmpty else { return 0 }
        for p in new { store.entries.append(Self.entry(for: p)) }
        save(); publish()
        for p in new { enqueue(p) }
        return new.count
    }

    /// Etiquetas del fichero (Core Audio) e identificador estable (MD5 del tamaño y el principio).
    private static func entry(for path: String) -> Entry {
        var info: [String: Any] = [:]
        var bitrate: UInt32 = 0
        var f: AudioFileID?
        if AudioFileOpenURL(URL(fileURLWithPath: path) as CFURL, .readPermission, 0, &f) == noErr, let f {
            var dict: Unmanaged<CFDictionary>?
            var size = UInt32(MemoryLayout<Unmanaged<CFDictionary>?>.size)
            if AudioFileGetProperty(f, kAudioFilePropertyInfoDictionary, &size, &dict) == noErr, let d = dict?.takeRetainedValue() as? [String: Any] { info = d }
            var bs = UInt32(MemoryLayout<UInt32>.size)
            AudioFileGetProperty(f, kAudioFilePropertyBitRate, &bs, &bitrate)
            AudioFileClose(f)
        }
        func s(_ k: String) -> String { (info[k] as? String) ?? "" }
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        return Entry(path: path, fileID: fileID(path), title: s(kAFInfoDictionary_Title).isEmpty ? name : s(kAFInfoDictionary_Title),
                     artist: s(kAFInfoDictionary_Artist), album: s(kAFInfoDictionary_Album), genre: s(kAFInfoDictionary_Genre),
                     composer: s(kAFInfoDictionary_Composer), year: s(kAFInfoDictionary_Year), comments: s(kAFInfoDictionary_Comments),
                     trackNumber: Int(s(kAFInfoDictionary_TrackNumber).split(separator: "/").first ?? "") ?? 0,
                     bitrate: Int(bitrate), dateAdded: Date(), seconds: nil, bpm: nil, keyTonic: nil, keyMinor: nil, failed: nil)
    }
    static func fileID(_ path: String) -> String {
        var md5 = Insecure.MD5()
        if let h = FileHandle(forReadingAtPath: path) {
            let size = (try? h.seekToEnd()) ?? 0
            md5.update(data: withUnsafeBytes(of: size) { Data($0) })
            try? h.seek(toOffset: 0)
            if let d = try? h.read(upToCount: 65536) { md5.update(data: d) }
            try? h.close()
        } else { md5.update(data: Data(path.utf8)) }
        return md5.finalize().map { String(format: "%02X", $0) }.joined()
    }

    // MARK: Análisis en paralelo

    private func enqueue(_ path: String) {
        if done >= total { total = 0; done = 0; started = Date() }
        total += 1
        queue.addOperation { [weak self] in
            let a = Engine.analyzeCached(path: path)
            DispatchQueue.main.async { self?.finished(path, a) }
        }
        progressChanged()
    }
    private func finished(_ path: String, _ a: TrackAnalysis?) {
        done += 1
        if let i = store.entries.firstIndex(where: { $0.path == path }) {
            if let a {
                store.entries[i].bpm = a.bpm; store.entries[i].seconds = a.seconds
                if !a.key.isEmpty { store.entries[i].keyTonic = a.key_tonic; store.entries[i].keyMinor = a.key_minor }
            } else { store.entries[i].failed = true }
        }
        // Guardar y refrescar la biblioteca a ritmo humano, no 30 veces por segundo.
        if !saveScheduled {
            saveScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + (isBusy ? 1.0 : 0.05)) { [weak self] in
                guard let self else { return }
                self.saveScheduled = false
                self.save(); self.publish()
            }
        }
        progressChanged()
        if !isBusy { Log.write(String(format: "biblioteca: %d canciones analizadas en %.1f s", total, Date().timeIntervalSince(started))) }
    }
    private var saveScheduled = false

    /// Para la cola (lo que falta se analiza la próxima vez que se abra la app).
    func cancel() {
        queue.cancelAllOperations()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            self.total = 0; self.done = 0
            self.progressChanged()
        }
    }

    private func progressChanged() { NotificationCenter.default.post(name: .libraryProgress, object: nil) }

    // MARK: Biblioteca

    private func publish() {
        let items = store.entries.enumerated().map { i, e in
            LibraryItem(id: -(i + 1), path: e.path, fileID: e.fileID, title: e.title, artist: e.artist, album: e.album, genre: e.genre,
                        composer: e.composer, label: "", comments: e.comments, year: e.year, user1: "", user2: "", trackNumber: e.trackNumber,
                        rating: 0, bpm: e.bpm ?? 0, keyNote: e.keyTonic, minor: e.keyMinor ?? false, seconds: e.seconds ?? 0,
                        bitrate: e.bitrate, dateAdded: e.dateAdded, categories: [], tweaked: false)
        }
        Session.shared.catalog.setExtra(items)
        NotificationCenter.default.post(name: .libraryChanged, object: nil)
    }
    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(store) { try? d.write(to: url, options: .atomic) }
    }

    // MARK: Carpetas vigiladas («Automatically add files by monitoring folders»)

    func monitor(_ folders: [URL]) {
        for f in folders where !store.monitored.contains(f.path) { store.monitored.append(f.path) }
        save()
        scanMonitored()
        watch()
    }
    func stopMonitoring(_ path: String) {
        store.monitored.removeAll { $0 == path }
        save()
        watch()
    }
    private func scanMonitored() { add(store.monitored.map { URL(fileURLWithPath: $0) }) }
    private var stream: FSEventStreamRef?
    private func watch() {
        if let s = stream { FSEventStreamStop(s); FSEventStreamInvalidate(s); FSEventStreamRelease(s); stream = nil }
        guard !store.monitored.isEmpty else { return }
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let cb: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let me = Unmanaged<Library8>.fromOpaque(info).takeUnretainedValue()
            DispatchQueue.main.async { me.scanMonitored() }
        }
        stream = FSEventStreamCreate(nil, cb, &ctx, store.monitored as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 2.0,
                                     FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone))
        if let s = stream { FSEventStreamSetDispatchQueue(s, .main); FSEventStreamStart(s) }
    }
}

extension Notification.Name {
    static let libraryProgress = Notification.Name("mm8.libraryProgress")
}

extension Engine {
    /// Análisis con caché en disco (AnalysisCache): la segunda vez es inmediato.
    static func analyzeCached(path: String) -> TrackAnalysis? {
        if let a = AnalysisCache.get(path) { return a }
        guard let a = try? analyze(path: path) else { return nil }
        AnalysisCache.put(path, a)
        return a
    }
}

/// File › Add Files to Library… (AddMusicFilesToLibraryDlg.nib): los tres modos del original.
enum AddFilesDialog {
    static func run() {
        let a = NSAlert()
        a.messageText = "Add Music Files To The Library"
        a.informativeText = "MixMeister supports these music file formats:\nAIFC, AIFF, AIF, M4A, MP3, WAV (y en MixMeister 8 también FLAC)"
        a.addButton(withTitle: "Add files and/or folders...")
        a.addButton(withTitle: "Add a single file...")
        a.addButton(withTitle: "Automatically add files by monitoring folders...")
        a.addButton(withTitle: "Cancel")
        switch a.runModal() {
        case .alertFirstButtonReturn: choose(files: true, folders: true, multiple: true) { Library8.shared.add($0) }
        case .alertSecondButtonReturn: choose(files: true, folders: false, multiple: false) { Library8.shared.add($0) }
        case .alertThirdButtonReturn: monitorDialog()
        default: break
        }
    }
    private static func choose(files: Bool, folders: Bool, multiple: Bool, _ done: ([URL]) -> Void) {
        let p = NSOpenPanel()
        p.canChooseFiles = files
        p.canChooseDirectories = folders
        p.allowsMultipleSelection = multiple
        p.prompt = "Add"
        if p.runModal() == .OK { done(p.urls) }
    }
    /// Carpetas vigiladas: lista actual, añadir y dejar de vigilar.
    private static func monitorDialog() {
        let lib = Library8.shared
        let a = NSAlert()
        a.messageText = "Automatically add files by monitoring folders"
        a.informativeText = lib.monitored.isEmpty ? "No hay carpetas vigiladas. Las canciones nuevas que aparezcan en las carpetas vigiladas entran solas en la biblioteca."
            : "Carpetas vigiladas:\n" + lib.monitored.joined(separator: "\n")
        a.addButton(withTitle: "Add Folder...")
        if !lib.monitored.isEmpty { a.addButton(withTitle: "Stop Monitoring All") }
        a.addButton(withTitle: "OK")
        let r = a.runModal()
        if r == .alertFirstButtonReturn { choose(files: false, folders: true, multiple: true) { lib.monitor($0) } }
        else if r == .alertSecondButtonReturn, !lib.monitored.isEmpty { for m in lib.monitored { lib.stopMonitoring(m) } }
    }
}
