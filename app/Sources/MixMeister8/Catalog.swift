import Foundation
import SQLite3

/// Una pista de la biblioteca (fila de ZCATALOG en el catálogo de MixMeister).
struct LibraryItem: Hashable {
    var id: Int
    var path: String
    var fileID: String          // ZMUSICFILEID sin guiones, en mayúsculas: = TRKH+8 de las listas
    var title: String
    var artist: String
    var album: String
    var genre: String
    var composer: String
    var label: String
    var comments: String
    var year: String
    var user1: String
    var user2: String
    var trackNumber: Int
    var rating: Int
    var bpm: Double
    var keyNote: Int?           // 0 = C … 11 = B
    var minor: Bool
    var seconds: Double
    var bitrate: Int
    var dateAdded: Date?
    var categories: [String] = []
    var tweaked: Bool

    static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    var keyText: String {
        guard let k = keyNote else { return "" }
        return Self.noteNames[k] + (minor ? (Self.noteNames[k].count == 1 ? " m" : "m") : "")
    }
    /// Número de KEYCODE como lo muestra MixMeister: posición en el círculo de quintas empezando en
    /// La menor = 1 (A m ①, E m ②, B m ③ … C m ⑩); en mayores, Do = 1. Comprobado contra la
    /// columna KEYCODE de la biblioteca real.
    var keyCodeNumber: Int? {
        guard let k = keyNote else { return nil }
        let base = minor ? 9 : 0
        return (((k - base) * 7) % 12 + 12) % 12 + 1
    }
    var keyCode: String {
        guard let n = keyCodeNumber else { return "" }
        return String(UnicodeScalar(UInt32(0x2460 + n - 1))!)   // ① … ⑫
    }
    var timeText: String { seconds > 0 ? String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60) : "" }
}

/// Lee la biblioteca de MixMeister (Core Data sobre SQLite) sin tocarla: se copia con la API de
/// copia de SQLite (incluye lo pendiente del WAL) y se lee la copia.
final class Catalog {
    private(set) var items: [LibraryItem] = []
    private(set) var categories: [String] = []
    private(set) var sourcePath: String?

    static var candidates: [String] {
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MixMeister Technology")
        return ["MixMeister Engine 7", "MixMeister Engine Studio 7", "MixMeister Engine Express 7"].map {
            base.appendingPathComponent($0).appendingPathComponent("catalog.mdb").path
        }
    }

    static func findMixMeisterCatalog() -> String? {
        candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    func load(from path: String) throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mm8-catalog-\(UUID().uuidString).sqlite").path
        defer { for x in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: tmp + x) } }
        try Self.snapshot(path, to: tmp)
        var db: OpaquePointer?
        guard sqlite3_open_v2(tmp, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { throw EngineError.message("no se puede abrir el catálogo") }
        defer { sqlite3_close(db) }

        var cats: [Int: String] = [:]
        try query(db, "SELECT Z_PK, ZCATEGORYNAME FROM ZCATEGORY ORDER BY ZCATEGORYNAME") { st in
            cats[Int(sqlite3_column_int64(st, 0))] = text(st, 1)
        }
        var links: [Int: [String]] = [:]
        try? query(db, "SELECT Z_1CATALOG1, Z_2CATEGORY FROM Z_1CATEGORY") { st in
            if let c = cats[Int(sqlite3_column_int64(st, 1))] { links[Int(sqlite3_column_int64(st, 0)), default: []].append(c) }
        }
        var out: [LibraryItem] = []
        let sql = """
            SELECT Z_PK, ZFILENAME, ZMUSICFILEID, ZSONGTITLE, ZARTISTNAME, ZALBUMNAME, ZGENRE, ZCOMPOSER, ZLABEL,
                   ZCOMMENTS, ZYEAR, ZUSER1, ZUSER2, ZTRACKNUMBER, ZRATING, ZBPM, ZKEY, ZKEYFLAGS, ZSAMPLECOUNT,
                   ZSAMPLERATE, ZBITRATE, ZDATEADDED, ZDEFAULTTRACKPRESET FROM ZCATALOG
            """
        try query(db, sql) { st in
            let pk = Int(sqlite3_column_int64(st, 0))
            let keyFlags = sqlite3_column_int(st, 17)
            let sr = Double(sqlite3_column_int(st, 19))
            let added = sqlite3_column_double(st, 21)
            out.append(LibraryItem(
                id: pk, path: text(st, 1),
                fileID: text(st, 2).replacingOccurrences(of: "-", with: "").uppercased(),
                title: text(st, 3), artist: text(st, 4), album: text(st, 5), genre: text(st, 6), composer: text(st, 7),
                label: text(st, 8), comments: text(st, 9), year: text(st, 10), user1: text(st, 11), user2: text(st, 12),
                trackNumber: Int(sqlite3_column_int(st, 13)), rating: Int(sqlite3_column_int(st, 14)),
                bpm: sqlite3_column_double(st, 15),
                keyNote: keyFlags & 1 != 0 ? Int(sqlite3_column_int(st, 16)) % 12 : nil,
                minor: keyFlags & 1 != 0,   // ver docs/spec/catalogo.md: las detectadas se muestran como menores
                seconds: sr > 0 ? Double(sqlite3_column_int64(st, 18)) / sr : 0,
                bitrate: Int(sqlite3_column_int(st, 20)),
                dateAdded: added > 0 ? Date(timeIntervalSinceReferenceDate: added) : nil,
                categories: links[pk] ?? [],
                tweaked: sqlite3_column_type(st, 22) != SQLITE_NULL))
        }
        items = out.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        categories = cats.values.sorted()
        sourcePath = path
    }

    func item(fileID: String) -> LibraryItem? { items.first { $0.fileID == fileID.uppercased() } }

    // MARK: SQLite

    /// Copia la base con su WAL y su índice compartido; al abrir la copia, SQLite aplica el WAL.
    /// El original no se abre nunca (MixMeister puede estar usándolo).
    private static func snapshot(_ src: String, to dst: String) throws {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] where fm.fileExists(atPath: src + suffix) {
            try? fm.removeItem(atPath: dst + suffix)
            try fm.copyItem(atPath: src + suffix, toPath: dst + suffix)
        }
        var db: OpaquePointer?
        guard sqlite3_open(dst, &db) == SQLITE_OK else { throw EngineError.message("no se puede abrir la copia del catálogo") }
        sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, nil)
        sqlite3_close(db)
    }

    private func query(_ db: OpaquePointer?, _ sql: String, _ row: (OpaquePointer) -> Void) throws {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK, let st else {
            throw EngineError.message(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(st) }
        while sqlite3_step(st) == SQLITE_ROW { row(st) }
    }
}

private func text(_ st: OpaquePointer, _ i: Int32) -> String {
    guard let c = sqlite3_column_text(st, i) else { return "" }
    return String(cString: c)
}
