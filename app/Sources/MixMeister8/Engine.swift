import AppKit
import Foundation
import MMNEngine

enum EngineError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(m) = self { return m }; return nil }
}

private func takeError(_ e: UnsafeMutablePointer<CChar>?) -> EngineError {
    guard let e else { return .message("error desconocido del motor") }
    defer { mmn_free_string(e) }
    return .message(String(cString: e))
}

// MARK: - Modelo de lista (mismo esquema que mmn_playlist_json)

struct PLMarker: Codable, Hashable {
    var _src: Int?
    var kind: String = "marker"
    var type: UInt32
    var name: String?
    var pos_us: Int64
    var flag: UInt32 = 0
    var value: Double = 0
    var label: String = ""
}

struct PLSegment: Codable, Hashable {
    var _src: Int?
    var kind: String = "segment"
    var reversed: Bool
    var `class`: UInt32
    var src_start_us: Int64
    var src_end_us: Int64
    var anchor_us: Int64
    var overlay_measure: Int32
    var overlay_fraction: Double
    var overlay_rate: Double
}

enum PLLayerItem: Codable, Hashable {
    case marker(PLMarker)
    case segment(PLSegment)
    private enum K: CodingKey { case kind }
    init(from d: Decoder) throws {
        let kind = try d.container(keyedBy: K.self).decode(String.self, forKey: .kind)
        self = kind == "segment" ? .segment(try PLSegment(from: d)) : .marker(try PLMarker(from: d))
    }
    func encode(to e: Encoder) throws {
        switch self { case let .marker(m): try m.encode(to: e); case let .segment(s): try s.encode(to: e) }
    }
}

struct PLEffect: Codable, Hashable {
    var plugin_id: UInt32
    var code: String?
    var slot: UInt32
    var flags: UInt32
    var params: [Double]
    var name: String
}

struct PLTrack: Codable, Hashable {
    var _src: Int?
    var path: String
    var transition_in: String?
    var transition_out: String?
    var file_id: String
    var bpm: Double
    var original_bpm: Double?
    var bar_us: Int64
    var length_us: Int64?
    var overlay: Bool
    var key_semitones: Double
    var beat_markers_us: [Int64]
    var effects: [PLEffect]
    var layer: [PLLayerItem]

    var markers: [PLMarker] { layer.compactMap { if case let .marker(m) = $0 { return m }; return nil } }
    var segments: [PLSegment] { layer.compactMap { if case let .segment(s) = $0 { return s }; return nil } }
    func markers(_ t: UInt32) -> [PLMarker] { markers.filter { $0.type == t } }
    var fileName: String { path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? path }
    var title: String { (fileName as NSString).deletingPathExtension }
}

struct PLDocument: Codable {
    var format: String?
    var version: [UInt32]?
    var master_gain_db: Double
    var master_effects: [PLEffect]
    var tracks: [PLTrack]
}

enum MarkerKind {
    static let introAnchor: UInt32 = 0x1, outroAnchor: UInt32 = 0x2
    static let autoVolumeIn: UInt32 = 0x80, autoVolume: UInt32 = 0x100
    static let volume: UInt32 = 0x8000, treble: UInt32 = 0x10000, mid: UInt32 = 0x20000, bass: UInt32 = 0x40000
    static let tempo: UInt32 = 0x0100_0000, originalTempo: UInt32 = 0x0200_0000, label: UInt32 = 0x0400_0000
    static let effectParam: UInt32 = 0x0800_0000, measure: UInt32 = 0x1000_0000
    static let loopStart: UInt32 = 0x4000_0000, loopEnd: UInt32 = 0x8000_0000
}

// MARK: - Acceso al motor

/// Una lista .mmp abierta en el motor: lo que no interpretamos se conserva al guardar.
final class EngineDocument {
    private let handle: OpaquePointer

    init() { handle = mmn_playlist_new() }
    init(path: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        guard let h = mmn_playlist_open(path, &err) else { throw takeError(err) }
        handle = h
    }
    deinit { mmn_playlist_free(handle) }

    func read() throws -> PLDocument {
        let json = String(cString: mmn_playlist_json(handle))
        return try JSONDecoder().decode(PLDocument.self, from: Data(json.utf8))
    }

    func write(_ doc: PLDocument) throws {
        let data = try JSONEncoder().encode(doc)
        var err: UnsafeMutablePointer<CChar>?
        let rc = String(decoding: data, as: UTF8.self).withCString { mmn_playlist_set_json(handle, $0, &err) }
        if rc != 0 { throw takeError(err) }
    }

    func save(to path: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if mmn_playlist_save(handle, path, &err) != 0 { throw takeError(err) }
    }
}

struct TrackAnalysis: Codable {
    var bpm: Double
    var first_beat_s: Double
    var downbeat: Int
    var first_sounding_beat: Double
    var confidence: Double
    var entry_beat: Double
    var exit_beat: Double
    var seconds: Double
    var sample_rate: Int
    var key: String
    var camelot: String
    var key_tonic: Int
    var key_minor: Bool
}

/// Forma de onda de un fichero: pico por bin, y graves/medios/agudos (3 por bin).
struct Wave {
    var peaks: [Float]
    var bands: [Float]
    var seconds: Double
    /// Color del bin (graves rojo, medios verde, agudos azul), con el brillo según la mezcla.
    func color(_ bin: Int) -> NSColor {
        guard bin >= 0, 3 * bin + 2 < bands.count else { return .gray }
        let l = CGFloat(bands[3 * bin]), m = CGFloat(bands[3 * bin + 1]), h = CGFloat(bands[3 * bin + 2])
        let mx = max(l, m, h, 1e-6)
        return NSColor(srgbRed: 0.25 + 0.75 * l / mx, green: 0.25 + 0.75 * m / mx, blue: 0.3 + 0.7 * h / mx, alpha: 0.95)
    }
    /// El mismo color reducido a una paleta de 4×4×4 (índice 0..63), para dibujar agrupando por color.
    func colorIndex(_ bin: Int) -> Int {
        guard bin >= 0, 3 * bin + 2 < bands.count else { return 0 }
        let l = bands[3 * bin], m = bands[3 * bin + 1], h = bands[3 * bin + 2]
        let mx = max(l, m, h, 1e-6)
        func q(_ v: Float) -> Int { min(3, Int(v / mx * 4)) }
        return q(l) * 16 + q(m) * 4 + q(h)
    }
    static let palette: [NSColor] = (0..<64).map { i in
        let l = CGFloat(i / 16) / 3, m = CGFloat((i / 4) % 4) / 3, h = CGFloat(i % 4) / 3
        return NSColor(srgbRed: 0.25 + 0.75 * l, green: 0.25 + 0.75 * m, blue: 0.3 + 0.7 * h, alpha: 0.95)
    }
}

enum Engine {
    static var version: String { String(cString: mmn_version()) }

    /// Envolvente de la forma de onda (0..1) y duración en segundos.
    static func peaks(path: String, bins: Int) throws -> (peaks: [Float], seconds: Double) {
        var out = [Float](repeating: 0, count: bins)
        var err: UnsafeMutablePointer<CChar>?
        let secs = out.withUnsafeMutableBufferPointer { mmn_audio_peaks(path, $0.baseAddress, bins, &err) }
        if secs < 0 { throw takeError(err) }
        return (out, secs)
    }

    /// Forma de onda por bandas: pico total y graves/medios/agudos por bin.
    static func peaks3(path: String, bins: Int) throws -> Wave {
        var out = [Float](repeating: 0, count: bins * 4)
        var err: UnsafeMutablePointer<CChar>?
        let secs = out.withUnsafeMutableBufferPointer { mmn_audio_peaks3(path, $0.baseAddress, bins, &err) }
        if secs < 0 { throw takeError(err) }
        var w = Wave(peaks: [Float](repeating: 0, count: bins), bands: [Float](repeating: 0, count: bins * 3), seconds: secs)
        for i in 0..<bins {
            w.peaks[i] = out[4 * i]
            for b in 0..<3 { w.bands[3 * i + b] = out[4 * i + 1 + b] }
        }
        return w
    }

    static func analyze(path: String) throws -> TrackAnalysis {
        var err: UnsafeMutablePointer<CChar>?
        guard let s = mmn_analyze_json(path, &err) else { throw takeError(err) }
        defer { mmn_free_string(s) }
        return try JSONDecoder().decode(TrackAnalysis.self, from: Data(String(cString: s).utf8))
    }
}

extension Sequence {
    /// Orden estable: con dos elementos iguales conserva el orden original. Los marcadores en el mismo
    /// instante (p. ej. Enable 0 y 1 al principio de un tramo con efecto) dependen de ello.
    func stableSorted(by less: (Element, Element) -> Bool) -> [Element] {
        enumerated().sorted { less($0.element, $1.element) || (!less($1.element, $0.element) && $0.offset < $1.offset) }.map(\.element)
    }
}
