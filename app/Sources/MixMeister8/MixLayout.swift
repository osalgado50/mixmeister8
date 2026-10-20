import Foundation

/// Dónde cae cada pista en la mezcla (segundos de la mezcla) a partir de la lista.
///
/// Reglas de MixMeister (docs/spec/mmp.md y transitions.xml): en una transición con solape, el
/// ancla de entrada de una pista coincide con el ancla de salida de la anterior; sin solape
/// ("No Transition", "Pause"), la pista empieza cuando acaba la anterior. Cada pista suena al tempo
/// de su marcador de tempo (si lo tiene) o al suyo. Los overlays se colocan por compás de la
/// mezcla. Fase 1: tempo constante por pista (las rampas de tempo llegan con la reproducción).
struct MixLayout {
    struct Seg { var mixStart: Double; var mixEnd: Double; var srcStart: Double; var srcEnd: Double; var reversed: Bool }
    struct Item {
        var index: Int
        var strip: Int
        var overlay: Bool
        var rate: Double            // velocidad de reproducción (tempo de la mezcla / tempo propio)
        var tempo: Double           // BPM al que suena
        var origin: Double          // instante de la mezcla que corresponde a src = srcOrigin
        var srcOrigin: Double
        var segments: [Seg]
        var mixStart: Double { segments.map(\.mixStart).min() ?? origin }
        var mixEnd: Double { segments.map(\.mixEnd).max() ?? origin }
        func toMix(_ src: Double) -> Double { origin + (src - srcOrigin) / rate }
        func toSource(_ mix: Double) -> Double { srcOrigin + (mix - origin) * rate }
    }
    var items: [Item]
    var total: Double
    var masterBPM: Double
    var barOrigin: Double           // instante de la mezcla del compás 0

    static let empty = MixLayout(items: [], total: 0, masterBPM: 0, barOrigin: 0)

    init(items: [Item], total: Double, masterBPM: Double, barOrigin: Double) {
        self.items = items; self.total = total; self.masterBPM = masterBPM; self.barOrigin = barOrigin
    }

    static func noOverlap(_ name: String?) -> Bool { name == "No Transition" || name == "Pause" }

    init(doc: PLDocument, strips: Int) {
        var out: [Item] = []
        var prevOutro: Double? = nil, prevEnd = 0.0
        var prevTransition: String? = nil
        var master = 0.0, origin0: Double? = nil
        for (i, t) in doc.tracks.enumerated() {
            let us = 1e-6
            let segs = t.segments
            // Tempo propio: el marcador de tempo original (el que muestra MixMeister en BPM); el de
            // la mezcla: el primer marcador de tempo, si lo hay. Sin marcadores, suena a su tempo.
            let own = t.markers(MarkerKind.originalTempo).first?.value ?? (t.bpm > 0 ? t.bpm : t.original_bpm ?? 120)
            let tempo = t.markers(MarkerKind.tempo).first?.value ?? own
            let rate = own > 0 ? tempo / own : 1
            if master == 0, !t.overlay { master = tempo }
            let srcStart = Double(segs.map(\.src_start_us).min() ?? 0) * us
            if t.overlay {
                // Overlay: compás de la mezcla + fracción; los segmentos van uno tras otro.
                let bar = master > 0 ? 240 / master : 2
                let first = segs.first
                let at = (origin0 ?? 0) + (Double(first?.overlay_measure ?? 0) + (first?.overlay_fraction ?? 0)) * bar
                var cursor = at
                var ss: [Seg] = []
                for s in segs {
                    let len = Double(s.src_end_us - s.src_start_us) * us / rate
                    ss.append(Seg(mixStart: cursor, mixEnd: cursor + len, srcStart: Double(s.src_start_us) * us, srcEnd: Double(s.src_end_us) * us, reversed: s.reversed))
                    cursor += len
                }
                out.append(Item(index: i, strip: i % strips, overlay: true, rate: rate, tempo: tempo, origin: at, srcOrigin: srcStart, segments: ss))
                continue
            }
            let intro = Double(t.markers(MarkerKind.introAnchor).first?.pos_us ?? Int64(srcStart / us)) * us
            let outro = Double(t.markers(MarkerKind.outroAnchor).first?.pos_us ?? (segs.map(\.src_end_us).max() ?? 0)) * us
            // Instante de la mezcla donde cae el ancla de entrada.
            // El ancla de entrada cae siempre en el ancla de salida de la anterior, sea cual sea la
            // transición: la transición solo decide dónde se colocan las anclas y los volúmenes al
            // aplicarla (comprobado con Spinning310: «No Transition» solapa por sus anclas).
            let introMix = prevOutro ?? ((intro - srcStart) / rate)
            _ = prevEnd
            if origin0 == nil { origin0 = introMix }
            var item = Item(index: i, strip: i % strips, overlay: false, rate: rate, tempo: tempo, origin: introMix, srcOrigin: intro, segments: [])
            // Segmentos en el orden de la pista (cortes contiguos en el audio).
            for s in segs.sorted(by: { $0.src_start_us < $1.src_start_us }) {
                let a = Double(s.src_start_us) * us, b = Double(s.src_end_us) * us
                item.segments.append(Seg(mixStart: item.toMix(a), mixEnd: item.toMix(b), srcStart: a, srcEnd: b, reversed: s.reversed))
            }
            if item.segments.isEmpty, let len = t.length_us {
                item.segments = [Seg(mixStart: item.toMix(0), mixEnd: item.toMix(Double(len) * us), srcStart: 0, srcEnd: Double(len) * us, reversed: false)]
            }
            prevOutro = item.toMix(outro)
            prevEnd = item.mixEnd
            prevTransition = t.transition_out; _ = prevTransition
            out.append(item)
        }
        // La mezcla empieza en 0: se desplaza todo si la primera pista arranca antes.
        let shift = -(out.map(\.mixStart).min() ?? 0)
        for k in out.indices {
            out[k].origin += shift
            for j in out[k].segments.indices { out[k].segments[j].mixStart += shift; out[k].segments[j].mixEnd += shift }
        }
        self.items = out
        self.total = out.map(\.mixEnd).max() ?? 0
        self.masterBPM = master
        self.barOrigin = (origin0 ?? 0) + shift
    }
}
