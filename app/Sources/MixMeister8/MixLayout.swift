import Foundation

/// Dónde cae cada pista en la mezcla y a qué tempo suena en cada instante.
///
/// Reglas de MixMeister (docs/spec/mmp.md, transitions.xml y comprobaciones con Spinning310):
/// · El ancla de entrada de una pista cae en el ancla de salida de la anterior, sea cual sea la
///   transición (la transición decide dónde se ponen las anclas y los volúmenes al aplicarla).
/// · Tempo propio de una pista: su marcador de tempo original (lo que muestra la columna BPM).
/// · Sin marcadores de tempo, la pista suena a su tempo propio ("Automatic").
/// · Los marcadores de tempo de todas las pistas forman la curva de tempo de la mezcla, con rampas
///   lineales entre uno y el siguiente aunque estén en pistas distintas; una pista con marcadores
///   sigue esa curva en toda su duración. Así sale el 131,7 y el 130,5 de las filas 13 y 14 de
///   Spinning310, que no están en ningún marcador.
/// · Overlays: por compás de la mezcla, al tempo de la mezcla (Beat sync with Master Tempo).
struct MixLayout {
    struct Seg {
        var mixStart: Double; var mixEnd: Double; var srcStart: Double; var srcEnd: Double; var reversed: Bool
        /// Valor de Item.toSource en el inicio del segmento (en pistas principales = srcStart; en
        /// overlays, el audio acumulado). Audio real en t: srcStart + (toSource(t) − acc).
        var acc: Double
        func source(_ item: Item, at mix: Double) -> Double {
            let s = srcStart + (item.toSource(mix) - acc)
            return reversed ? srcEnd - (s - srcStart) : s
        }
    }

    struct Item {
        var index: Int
        var strip: Int
        var overlay: Bool
        var own: Double                 // tempo propio (BPM)
        var segments: [Seg] = []
        // Correspondencia mezcla ↔ audio, muestreada cada `dt` s de mezcla desde t0.
        var t0: Double = 0
        var dt: Double = 0.1
        var src: [Double] = []          // segundos del audio en t0 + k·dt
        var tempoCurve: (Double) -> Double = { _ in 120 }

        var mixStart: Double { segments.map(\.mixStart).min() ?? t0 }
        var mixEnd: Double { segments.map(\.mixEnd).max() ?? t0 }
        func tempo(at mix: Double) -> Double { tempoCurve(mix) }
        func rate(at mix: Double) -> Double { own > 0 ? tempo(at: mix) / own : 1 }
        /// Tempo al que entra (ancla de entrada): lo que muestra la columna BPM de la lista.
        var tempo: Double = 120
        var rate: Double { rate(at: mixStart) }

        func toSource(_ mix: Double) -> Double {
            guard src.count > 1 else { return mix - t0 }
            let x = (mix - t0) / dt
            if x <= 0 { return src[0] + x * dt * rate(at: t0) }
            let k = Int(x)
            if k >= src.count - 1 { return src[src.count - 1] + (x - Double(src.count - 1)) * dt * rate(at: mix) }
            let u = x - Double(k)
            return src[k] + (src[k + 1] - src[k]) * u
        }
        func toMix(_ s: Double) -> Double {
            guard src.count > 1 else { return t0 + s }
            if s <= src[0] { return t0 - (src[0] - s) / max(1e-6, rate(at: t0)) }
            if s >= src[src.count - 1] { return t0 + Double(src.count - 1) * dt + (s - src[src.count - 1]) / max(1e-6, rate(at: t0 + Double(src.count - 1) * dt)) }
            var lo = 0, hi = src.count - 1
            while hi - lo > 1 { let m = (lo + hi) / 2; if src[m] <= s { lo = m } else { hi = m } }
            let u = (s - src[lo]) / max(1e-12, src[hi] - src[lo])
            return t0 + (Double(lo) + u) * dt
        }
    }

    var items: [Item]
    var total: Double
    var masterBPM: Double
    var barOrigin: Double                       // instante de la mezcla del compás 0
    var tempoPoints: [(mix: Double, bpm: Double, track: Int, original: Bool)] = []

    static let empty = MixLayout(items: [], total: 0, masterBPM: 0, barOrigin: 0)
    init(items: [Item], total: Double, masterBPM: Double, barOrigin: Double) {
        self.items = items; self.total = total; self.masterBPM = masterBPM; self.barOrigin = barOrigin
    }

    /// Tempo al que suena la pista sin marcadores de tempo: su marcador de tempo original (lo que
    /// muestra la columna BPM) o, si no tiene, el tempo de su audio.
    static func ownTempo(_ t: PLTrack) -> Double {
        t.markers(MarkerKind.originalTempo).first?.value ?? audioTempo(t)
    }
    /// Tempo real del audio (TRKH; el BPM original del Song Slicer). La velocidad de reproducción es
    /// tempo de la mezcla / tempo del audio. Comprobado en MixMeister 7.8: Spinning310, pista 2,
    /// audio a 101,96 con marcador de tempo original 100 suena al 98 % (al pasar el audio a 50 BPM
    /// en el Song Slicer, la pista se acorta y la mezcla pasa de 47:34 a 47:30).
    static func audioTempo(_ t: PLTrack) -> Double {
        t.bpm > 0 ? t.bpm : (t.original_bpm ?? (t.bar_us > 0 ? 240e6 / Double(t.bar_us) : 120))
    }

    /// Curva de tempo de la mezcla: interpolación lineal entre puntos (mezcla, BPM).
    static func curve(_ pts: [(Double, Double)]) -> (Double) -> Double {
        let p = pts.sorted { $0.0 < $1.0 }
        return { t in
            guard let f = p.first else { return 120 }
            if t <= f.0 { return f.1 }
            for i in 1..<p.count where t < p[i].0 {
                let a = p[i - 1], b = p[i]
                return a.1 + (b.1 - a.1) * (t - a.0) / max(1e-9, b.0 - a.0)
            }
            return p.last!.1
        }
    }

    init(doc: PLDocument, strips: Int) {
        // Se resuelve por aproximaciones: los marcadores de tempo están en tiempo del audio y su
        // instante en la mezcla depende de los tempos anteriores. Tres pasadas bastan (cambia < 1 ms).
        var points: [(Double, Double)] = []
        var lay = MixLayout.pass(doc: doc, strips: strips, points: points)
        for _ in 0..<3 {
            let tps = lay.tempoPoints.filter { !$0.original }
            points = tps.map { ($0.mix, $0.bpm) }
            var owners: [Int: [Double]] = [:]
            for p in tps { owners[p.track, default: []].append(p.mix) }
            lay = MixLayout.pass(doc: doc, strips: strips, points: points, owners: owners)
        }
        self = lay
    }

    private static func pass(doc: PLDocument, strips: Int, points: [(Double, Double)], owners: [Int: [Double]] = [:]) -> MixLayout {
        let tp0 = owners
        let us = 1e-6
        let global = curve(points)
        var out: [Item] = []
        var prevOutro: Double? = nil
        var firstIntro: Double? = nil
        var master = 0.0
        var tp: [(mix: Double, bpm: Double, track: Int, original: Bool)] = []

        for (i, t) in doc.tracks.enumerated() where !t.overlay {
            let segs = t.segments.sorted { $0.src_start_us < $1.src_start_us }
            let own = audioTempo(t)
            let base = ownTempo(t)
            let marks = t.markers(MarkerKind.tempo)
            let srcStart = Double(segs.first?.src_start_us ?? 0) * us
            let srcEnd = Double(segs.map(\.src_end_us).max() ?? (t.length_us ?? 0)) * us
            let intro = Double(t.markers(MarkerKind.introAnchor).first?.pos_us ?? Int64(srcStart / us)) * us
            let outro = Double(t.markers(MarkerKind.outroAnchor).first?.pos_us ?? Int64(srcEnd / us)) * us
            var item = Item(index: i, strip: i % strips, overlay: false, own: own)
            // Sin marcadores: a su tempo; con marcadores: la curva de la mezcla (o, en la primera
            // pasada, el primer marcador).
            // Sin marcadores: a su tempo. Con marcadores: rampas entre SUS marcadores (antes del
            // primero, el valor del primero). Comprobado con Spinning310: 19 de 21 filas iguales al
            // original. Pendiente de observar en MixMeister: el arrastre de tempo en las transiciones
            // beatmix (filas 13 y 21).
            if marks.isEmpty { item.tempoCurve = { _ in base } }
            else if points.isEmpty { let v = marks[0].value; item.tempoCurve = { _ in v } }
            else {
                let mine = points.filter { p in tp0[i]?.contains { abs($0 - p.0) < 1e-6 } ?? false }
                item.tempoCurve = mine.isEmpty ? global : curve(mine)
            }

            let first = prevOutro == nil
            let introMix = prevOutro ?? 0
            // Integración del tempo desde el ancla de entrada, hacia delante y hacia atrás.
            let dt = 0.1
            var fwd: [Double] = [intro]
            var tt = introMix, s = intro
            while s < srcEnd + 1 { s += item.rate(at: tt + dt / 2) * dt; tt += dt; fwd.append(s) }
            var back: [Double] = []
            tt = introMix; s = intro
            while s > srcStart - 1 { s -= item.rate(at: tt - dt / 2) * dt; tt -= dt; back.append(s) }
            item.t0 = introMix - Double(back.count) * dt
            item.dt = dt
            item.src = back.reversed() + fwd
            if first {
                // La primera pista empieza en 0: se corre todo para que su inicio caiga en 0.
                let startMix = item.toMix(srcStart)
                item.t0 -= startMix
            }
            let anchorMix = item.toMix(intro)
            if firstIntro == nil { firstIntro = anchorMix }
            for sg in segs {
                let a = Double(sg.src_start_us) * us, b = Double(sg.src_end_us) * us
                item.segments.append(Seg(mixStart: item.toMix(a), mixEnd: item.toMix(b), srcStart: a, srcEnd: b, reversed: sg.reversed, acc: a))
            }
            if item.segments.isEmpty, srcEnd > 0 {
                item.segments = [Seg(mixStart: item.toMix(0), mixEnd: item.toMix(srcEnd), srcStart: 0, srcEnd: srcEnd, reversed: false, acc: 0)]
            }
            item.tempo = item.tempo(at: (item.mixStart + item.mixEnd) / 2)
            if master == 0 { master = item.tempo }
            for m in marks { tp.append((item.toMix(Double(m.pos_us) * us), m.value, i, false)) }
            for m in t.markers(MarkerKind.originalTempo) { tp.append((item.toMix(Double(m.pos_us) * us), m.value, i, true)) }
            prevOutro = item.toMix(outro)
            out.append(item)
        }

        // Overlays: compás de la mezcla + fracción, al tempo de la mezcla; segmentos seguidos.
        let origin = firstIntro ?? 0
        let masterCurve: (Double) -> Double = points.isEmpty ? { _ in master > 0 ? master : 120 } : global
        for (i, t) in doc.tracks.enumerated() where t.overlay {
            let segs = t.segments
            let own = audioTempo(t)
            var item = Item(index: i, strip: i % strips, overlay: true, own: own)
            item.tempoCurve = masterCurve
            let bar = 240 / max(1, masterCurve(origin))
            let f = segs.first
            let at = origin + (Double(f?.overlay_measure ?? 0) + (f?.overlay_fraction ?? 0)) * bar
            let srcStart = Double(f?.src_start_us ?? 0) * us
            let total = segs.reduce(0.0) { $0 + Double($1.src_end_us - $1.src_start_us) * us }
            let dt = 0.1
            var arr: [Double] = [0]
            var tt = at, s = 0.0
            while s < total + 1 { s += item.rate(at: tt + dt / 2) * dt; tt += dt; arr.append(s) }
            item.t0 = at; item.dt = dt; item.src = arr          // aquí «src» = audio acumulado del overlay
            var acc = 0.0
            for sg in segs {
                let len = Double(sg.src_end_us - sg.src_start_us) * us
                item.segments.append(Seg(mixStart: item.toMix(acc), mixEnd: item.toMix(acc + len),
                                         srcStart: Double(sg.src_start_us) * us, srcEnd: Double(sg.src_end_us) * us, reversed: sg.reversed, acc: acc))
                acc += len
            }
            _ = srcStart
            item.tempo = masterCurve(at)
            out.append(item)
        }
        out.sort { $0.index < $1.index }
        var lay = MixLayout(items: out, total: out.map(\.mixEnd).max() ?? 0, masterBPM: master, barOrigin: origin)
        lay.tempoPoints = tp.sorted { $0.mix < $1.mix }
        return lay
    }

    /// Pista principal que suena en un instante (la última que ha empezado).
    func primary(at t: Double) -> Item? { items.last { !$0.overlay && $0.mixStart <= t } ?? items.first { !$0.overlay } }
    func tempo(at t: Double) -> Double { primary(at: t)?.tempo(at: t) ?? masterBPM }
}
