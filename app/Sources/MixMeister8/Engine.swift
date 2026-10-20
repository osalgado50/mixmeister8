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

    static func analyze(path: String) throws -> TrackAnalysis {
        var err: UnsafeMutablePointer<CChar>?
        guard let s = mmn_analyze_json(path, &err) else { throw takeError(err) }
        defer { mmn_free_string(s) }
        return try JSONDecoder().decode(TrackAnalysis.self, from: Data(String(cString: s).utf8))
    }
}
