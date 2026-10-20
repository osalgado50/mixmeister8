import AppKit

/// Columnas de la biblioteca y de la lista: los mismos nombres, etiquetas (tags de Library ›
/// Columns) y claves de preferencias que MixMeister ("Catalog<Clave>ColumnOrder/Width",
/// "Playlist<Clave>ColumnOrder/Width"; orden −1 = oculta).
struct ColumnDef {
    let key: String        // clave de preferencias
    let title: String      // cabecera
    let tag: Int           // tag del ítem en Library › Columns (0 = solo lista)
    let toggle: String     // selector toggleX:
    let width: CGFloat
    let numeric: Bool
}

enum Columns {
    static let all: [ColumnDef] = [
        .init(key: "Index", title: "#", tag: 0, toggle: "toggleIndex:", width: 34, numeric: true),
        .init(key: "Title", title: "TITLE", tag: 1, toggle: "toggleTitle:", width: 160, numeric: false),
        .init(key: "Artist", title: "ARTIST", tag: 2, toggle: "toggleArtist:", width: 110, numeric: false),
        .init(key: "Bpm", title: "BPM", tag: 3, toggle: "toggleBpm:", width: 58, numeric: true),
        .init(key: "Album", title: "ALBUM", tag: 4, toggle: "toggleAlbum:", width: 90, numeric: false),
        .init(key: "Time", title: "TIME", tag: 5, toggle: "toggleTime:", width: 52, numeric: true),
        .init(key: "Key", title: "KEY", tag: 6, toggle: "toggleKey:", width: 46, numeric: false),
        .init(key: "KeyCode", title: "KEYCODE", tag: 7, toggle: "toggleKeyCode:", width: 64, numeric: false),
        .init(key: "Transition", title: "TRANSITION", tag: 0, toggle: "toggleTransition:", width: 110, numeric: false),
        .init(key: "Tweaked", title: "TWEAKED", tag: 8, toggle: "toggleTweaked:", width: 60, numeric: false),
        .init(key: "Year", title: "YEAR", tag: 9, toggle: "toggleYear:", width: 46, numeric: true),
        .init(key: "Genre", title: "GENRE", tag: 10, toggle: "toggleGenre:", width: 80, numeric: false),
        .init(key: "Composer", title: "COMPOSER", tag: 11, toggle: "toggleComposer:", width: 90, numeric: false),
        .init(key: "FileName", title: "FILENAME", tag: 12, toggle: "toggleFileName:", width: 200, numeric: false),
        .init(key: "DateAdded", title: "DATE ADDED", tag: 13, toggle: "toggleDateAdded:", width: 90, numeric: false),
        .init(key: "Rating", title: "RATING", tag: 14, toggle: "toggleRating:", width: 60, numeric: false),
        .init(key: "Comments", title: "COMMENTS", tag: 15, toggle: "toggleComments:", width: 120, numeric: false),
        .init(key: "Track", title: "TRACK", tag: 16, toggle: "toggleTrack:", width: 44, numeric: true),
        .init(key: "BitRate", title: "BITRATE", tag: 17, toggle: "toggleBitRate:", width: 56, numeric: true),
        .init(key: "Label", title: "LABEL", tag: 18, toggle: "toggleLabel:", width: 80, numeric: false),
        .init(key: "User1", title: "USER 1", tag: 19, toggle: "toggleUser1:", width: 70, numeric: false),
        .init(key: "User2", title: "USER 2", tag: 20, toggle: "toggleUser2:", width: 70, numeric: false),
        .init(key: "Playlist", title: "PLAYLIST", tag: 21, toggle: "togglePlaylist:", width: 60, numeric: false),
    ]
    static func def(_ key: String) -> ColumnDef? { all.first { $0.key == key } }
    static func byToggle(_ sel: String) -> ColumnDef? { all.first { $0.toggle == sel } }

    static let libraryKeys = all.filter { $0.key != "Index" && $0.key != "Transition" }.map(\.key)
    static let playlistKeys = all.filter { $0.key != "Tweaked" && $0.key != "Playlist" }.map(\.key)

    /// Columnas visibles en orden, con anchura. Primero las de MixMeister 8; si no hay, las que
    /// tenía MixMeister (com.mixmeister.*); si tampoco, las de fábrica del original.
    static func layout(prefix: String, keys: [String], defaults: [String]) -> [(key: String, width: CGFloat)] {
        let mine = UserDefaults.standard
        let theirs = ["com.mixmeister.MixMeisterFusion", "com.mixmeister.MixMeisterStudio"].compactMap { UserDefaults(suiteName: $0) }
        for src in [mine] + theirs {
            var cols: [(Int, String, CGFloat)] = []
            for k in keys {
                guard let order = src.object(forKey: "\(prefix)\(k)ColumnOrder") as? Int else { continue }
                if order >= 0 {
                    let w = src.double(forKey: "\(prefix)\(k)ColumnWidth")
                    cols.append((order, k, max(CGFloat(w), 30)))
                }
            }
            if !cols.isEmpty { return cols.sorted { $0.0 < $1.0 }.map { ($0.1, $0.2) } }
        }
        return defaults.compactMap { k in def(k).map { (k, $0.width) } }
    }

    static func save(prefix: String, keys: [String], visible: [(key: String, width: CGFloat)]) {
        let d = UserDefaults.standard
        for k in keys {
            if let i = visible.firstIndex(where: { $0.key == k }) {
                d.set(i, forKey: "\(prefix)\(k)ColumnOrder")
                d.set(Double(visible[i].width), forKey: "\(prefix)\(k)ColumnWidth")
            } else {
                d.set(-1, forKey: "\(prefix)\(k)ColumnOrder")
            }
        }
    }
}
