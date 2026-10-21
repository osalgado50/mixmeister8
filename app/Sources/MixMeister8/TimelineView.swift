import AppKit

/// Línea de tiempo: carriles (2/4/6/8), regla de compases o tiempo, pistas con forma de onda,
/// envolvente de volumen, marcadores de EQ, tempo, etiquetas, bucles y anclas, y cursor.
final class TimelineView: NSView {
    var pps: CGFloat = 4 { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }   // píxeles por segundo
    var rulerMeasures = true { didSet { needsDisplay = true } }
    var playhead: Double = 0 { didSet { needsDisplay = true } }
    static let rulerHeight: CGFloat = 20
    static let tempoLaneHeight: CGFloat = 20   // barra de tempos (marcadores verdes), abajo
    /// Último clic derecho en la barra de tempos: instante y, si cayó sobre uno, el marcador.
    var laneClick: (time: Double, point: (track: Int, type: UInt32, mix: Double)?) = (0, nil)
    private var trackRects: [(index: Int, rect: NSRect)] = []

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        for n: Notification.Name in [.playlistChanged, .waveformReady, .selectionChanged, .viewOptionsChanged] {
            NotificationCenter.default.addObserver(self, selector: #selector(changed), name: n, object: nil)
        }
        menu = MenuSpecs.timelineTrack.build()
        registerForDraggedTypes([.mm8Effect])
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func changed() { invalidateIntrinsicContentSize(); needsDisplay = true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: max(800, CGFloat(Session.shared.layout.total + 30) * pps), height: NSView.noIntrinsicMetric)
    }

    var stripHeight: CGFloat { (bounds.height - Self.rulerHeight - Self.tempoLaneHeight) / CGFloat(Session.shared.strips) }
    var laneTop: CGFloat { bounds.height - Self.tempoLaneHeight }
    func x(_ t: Double) -> CGFloat { CGFloat(t) * pps }
    func time(_ x: CGFloat) -> Double { Double(x / pps) }

    override func draw(_ dirty: NSRect) {
        let s = Session.shared
        let L = s.layout
        Theme.background.setFill()
        dirty.fill()

        // Carriles
        for k in 0..<s.strips {
            let r = NSRect(x: dirty.minX, y: Self.rulerHeight + CGFloat(k) * stripHeight, width: dirty.width, height: stripHeight)
            (k % 2 == 0 ? Theme.panel : Theme.background).setFill()
            r.fill()
            Theme.grid.setFill()
            NSRect(x: dirty.minX, y: r.maxY - 1, width: dirty.width, height: 1).fill()
        }
        drawGrid(L, dirty)
        drawRuler(L, dirty)

        trackRects.removeAll()
        for item in L.items {
            guard item.index < s.doc.tracks.count else { continue }
            let t = s.doc.tracks[item.index]
            let y = Self.rulerHeight + CGFloat(item.strip) * stripHeight + 3
            let h = stripHeight - 6
            let full = NSRect(x: x(item.mixStart), y: y, width: max(2, x(item.mixEnd) - x(item.mixStart)), height: h)
            trackRects.append((item.index, full))
            guard full.intersects(dirty) else { continue }
            drawTrack(t, item, full, selected: s.selectedTrack == item.index)
        }

        drawTempoLane(L, dirty)

        // Cursor de reproducción
        let px = x(playhead)
        Theme.playhead.setFill()
        NSRect(x: px - 0.5, y: 0, width: 1.5, height: bounds.height).fill()
    }

    private func drawGrid(_ L: MixLayout, _ dirty: NSRect) {
        guard L.masterBPM > 0 else { return }
        let bar = 240 / L.masterBPM
        let step = pps * CGFloat(bar) < 6 ? 8.0 : (pps * CGFloat(bar) < 14 ? 4.0 : 1.0)
        var m = floor((time(dirty.minX) - L.barOrigin) / bar / step) * step
        while true {
            let t = L.barOrigin + m * bar
            let px = x(t)
            if px > dirty.maxX { break }
            (Int(m) % 32 == 0 ? Theme.gridStrong : Theme.grid).setFill()
            NSRect(x: px, y: Self.rulerHeight, width: 1, height: bounds.height).fill()
            m += step
        }
    }

    private func drawRuler(_ L: MixLayout, _ dirty: NSRect) {
        let r = NSRect(x: dirty.minX, y: 0, width: dirty.width, height: Self.rulerHeight)
        Theme.header.setFill(); r.fill()
        Theme.gridStrong.setFill(); NSRect(x: dirty.minX, y: Self.rulerHeight - 1, width: dirty.width, height: 1).fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: Theme.mono(9.5), .foregroundColor: Theme.textDim]
        if rulerMeasures, L.masterBPM > 0 {
            let bar = 240 / L.masterBPM
            let every = max(1, Int((60 / (pps * CGFloat(bar))).rounded(.up)))
            let nice = [1, 2, 4, 8, 16, 32, 64].first { $0 >= every } ?? 64
            var m = Int(floor((time(dirty.minX) - L.barOrigin) / bar / Double(nice))) * nice
            while true {
                let px = x(L.barOrigin + Double(m) * bar)
                if px > dirty.maxX { break }
                if m >= 0 {
                    Theme.textDim.setFill(); NSRect(x: px, y: 12, width: 1, height: 8).fill()
                    ("\(m)" as NSString).draw(at: NSPoint(x: px + 3, y: 3), withAttributes: attrs)
                }
                m += nice
            }
        } else {
            let every = [5.0, 10, 15, 30, 60, 120, 300].first { CGFloat($0) * pps >= 60 } ?? 600
            var t = floor(time(dirty.minX) / every) * every
            while x(t) <= dirty.maxX {
                let px = x(t)
                Theme.textDim.setFill(); NSRect(x: px, y: 12, width: 1, height: 8).fill()
                (String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) as NSString).draw(at: NSPoint(x: px + 3, y: 3), withAttributes: attrs)
                t += every
            }
        }
    }

    private func drawTrack(_ t: PLTrack, _ item: MixLayout.Item, _ full: NSRect, selected: Bool) {
        let s = Session.shared
        let header: CGFloat = 13
        // Segmentos
        for seg in item.segments {
            let r = NSRect(x: x(seg.mixStart), y: full.minY, width: max(2, x(seg.mixEnd) - x(seg.mixStart)), height: full.height)
            let path = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
            (selected ? Theme.clipSelected : (item.overlay ? Theme.overlay : Theme.clip)).setFill()
            path.fill()
            (selected ? Theme.accent : Theme.gridStrong).setStroke()
            path.lineWidth = selected ? 1.5 : 1
            path.stroke()
            // Forma de onda
            if let p = s.audioPath(item.index), let w = Waveforms.shared.get(p), w.seconds > 0 {
                let mid = r.minY + header + (r.height - header) / 2
                let amp = (r.height - header) / 2 - 2
                let wavePath = NSBezierPath()
                let step: CGFloat = 1
                var px = r.minX
                while px < r.maxX {
                    let tm = time(px)
                    let src = seg.source(item, at: tm)
                    let bin = Int(src / w.seconds * Double(w.peaks.count))
                    if bin >= 0, bin < w.peaks.count {
                        let a = CGFloat(w.peaks[bin]) * amp
                        wavePath.move(to: NSPoint(x: px, y: mid - a))
                        wavePath.line(to: NSPoint(x: px, y: mid + a))
                    }
                    px += step
                }
                (selected ? Theme.accent.withAlphaComponent(0.85) : Theme.wave).setStroke()
                wavePath.lineWidth = 1
                wavePath.stroke()
            } else if s.audioPath(item.index) == nil {
                ("Audio no encontrado" as NSString).draw(at: NSPoint(x: r.minX + 6, y: r.minY + header + 4),
                                                         withAttributes: [.font: Theme.font(10), .foregroundColor: Theme.bass])
            }
            if seg.reversed {
                ("◀︎ reverse" as NSString).draw(at: NSPoint(x: r.maxX - 60, y: r.maxY - 14), withAttributes: [.font: Theme.font(9), .foregroundColor: Theme.loop])
            }
        }
        // Título
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: full).addClip()
        let lib = s.libraryItem(for: t)
        let name = "\(item.index + 1) - \"\(lib?.title.isEmpty == false ? lib!.title : t.title)\"" + (lib.map { $0.artist.isEmpty ? "" : " by \($0.artist)" } ?? "")
        (name as NSString).draw(at: NSPoint(x: full.minX + 5, y: full.minY + 1),
                                withAttributes: [.font: Theme.font(10, .medium), .foregroundColor: selected ? Theme.accent : Theme.text])

        // Bucles: sombreado entre inicio y fin
        let starts = t.markers(MarkerKind.loopStart).map { item.toMix(Double($0.pos_us) * 1e-6) }.sorted()
        let ends = t.markers(MarkerKind.loopEnd).map { item.toMix(Double($0.pos_us) * 1e-6) }.sorted()
        for (a, b) in zip(starts, ends) where b > a {
            Theme.loop.withAlphaComponent(0.16).setFill()
            NSRect(x: x(a), y: full.minY + header, width: x(b) - x(a), height: full.height - header).fill()
        }

        // Envolventes: volumen (incluidos los automáticos de la transición) y EQ
        let bodyTop = full.minY + header + 2, bodyH = full.height - header - 4
        func yFor(db: Double, range: Double) -> CGFloat { bodyTop + bodyH * CGFloat(min(1, max(0, -db / range))) }
        let vol = t.markers.filter { [MarkerKind.volume, MarkerKind.autoVolume, MarkerKind.autoVolumeIn].contains($0.type) }.sorted { $0.pos_us < $1.pos_us }
        drawEnvelope(vol.map { (item.toMix(Double($0.pos_us) * 1e-6), yFor(db: $0.value, range: 50)) }, color: Theme.volume, full: full, baseline: yFor(db: 0, range: 50))
        for (kind, color) in [(MarkerKind.bass, Theme.bass), (MarkerKind.mid, Theme.mid), (MarkerKind.treble, Theme.treble)] {
            let m = t.markers(kind).sorted { $0.pos_us < $1.pos_us }
            if m.isEmpty { continue }
            drawEnvelope(m.map { (item.toMix(Double($0.pos_us) * 1e-6), bodyTop + bodyH / 2 + CGFloat(-$0.value / 50) * bodyH / 2) }, color: color, full: full, baseline: nil)
        }

        // Automatización del parámetro de efecto elegido en el rack (Effects Parameter Markers)
        if let tp = s.trackedParam, tp.track == item.index {
            let key = tp.slot << 12 | UInt32(tp.param)
            let m = t.markers.filter { $0.type == MarkerKind.effectParam && $0.flag == key }.sorted { $0.pos_us < $1.pos_us }
            drawEnvelope(m.map { (item.toMix(Double($0.pos_us) * 1e-6), bodyTop + bodyH * CGFloat(1 - min(1, max(0, $0.value)))) },
                         color: Theme.effect, full: full, baseline: nil)
        }

        // Tempo (verde), etiquetas (bandera numerada), anclas (triángulos naranja)
        for m in t.markers(MarkerKind.tempo) {
            let px = x(item.toMix(Double(m.pos_us) * 1e-6))
            Theme.tempo.setFill(); NSRect(x: px, y: full.minY + header, width: 1, height: full.height - header).fill()
            (String(format: "%.2f", m.value) as NSString).draw(at: NSPoint(x: px + 2, y: full.maxY - 12), withAttributes: [.font: Theme.mono(8.5), .foregroundColor: Theme.tempo])
        }
        for m in t.markers(MarkerKind.label) {
            let px = x(item.toMix(Double(m.pos_us) * 1e-6))
            Theme.label.withAlphaComponent(0.7).setFill(); NSRect(x: px, y: full.minY + header, width: 1, height: full.height - header).fill()
            let txt = m.label as NSString
            let a: [NSAttributedString.Key: Any] = [.font: Theme.font(9, .semibold), .foregroundColor: Theme.background]
            let sz = txt.size(withAttributes: a)
            let flag = NSRect(x: px, y: full.minY + header, width: sz.width + 6, height: 12)
            Theme.label.setFill(); NSBezierPath(roundedRect: flag, xRadius: 2, yRadius: 2).fill()
            txt.draw(at: NSPoint(x: px + 3, y: flag.minY), withAttributes: a)
        }
        for (kind, up) in [(MarkerKind.introAnchor, true), (MarkerKind.outroAnchor, false)] {
            for m in t.markers(kind) {
                let px = x(item.toMix(Double(m.pos_us) * 1e-6))
                let p = NSBezierPath()
                let yb = full.minY
                if up { p.move(to: NSPoint(x: px, y: yb)); p.line(to: NSPoint(x: px + 7, y: yb)); p.line(to: NSPoint(x: px, y: yb + 9)) }
                else { p.move(to: NSPoint(x: px, y: yb)); p.line(to: NSPoint(x: px - 7, y: yb)); p.line(to: NSPoint(x: px, y: yb + 9)) }
                p.close(); Theme.anchor.setFill(); p.fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Barra de tempos: cada marcador de tempo de la mezcla como un «⊥ 139.99» verde (los de tempo
    /// original, más apagados), como la fila inferior de la línea de tiempo del original.
    private func drawTempoLane(_ L: MixLayout, _ dirty: NSRect) {
        let r = NSRect(x: dirty.minX, y: laneTop, width: dirty.width, height: Self.tempoLaneHeight)
        Theme.header.setFill(); r.fill()
        Theme.gridStrong.setFill(); NSRect(x: dirty.minX, y: laneTop, width: dirty.width, height: 1).fill()
        var pts = L.tempoPoints
        if pts.isEmpty, let f = L.items.first(where: { !$0.overlay }) { pts = [(f.mixStart, f.tempo, f.index, true)] }
        for p in pts {
            let px = x(p.mix)
            guard px > dirty.minX - 60, px < dirty.maxX + 2 else { continue }
            let c = p.original ? Theme.tempo.withAlphaComponent(0.55) : Theme.tempo
            c.setFill()
            NSRect(x: px - 0.5, y: laneTop + 3, width: 1.5, height: 13).fill()
            NSRect(x: px - 4, y: laneTop + 15, width: 9, height: 1.5).fill()
            (String(format: "%.2f", p.bpm) as NSString).draw(at: NSPoint(x: px + 4, y: laneTop + 3),
                                                            withAttributes: [.font: Theme.mono(9.5, .semibold), .foregroundColor: c])
        }
    }

    private func lanePoint(at px: CGFloat) -> (track: Int, type: UInt32, mix: Double)? {
        let L = Session.shared.layout
        return L.tempoPoints.min { abs(x($0.mix) - px) < abs(x($1.mix) - px) }
            .flatMap { abs(x($0.mix) - px) <= 6 ? ($0.track, $0.original ? MarkerKind.originalTempo : MarkerKind.tempo, $0.mix) : nil }
    }

    private func drawEnvelope(_ pts: [(Double, CGFloat)], color: NSColor, full: NSRect, baseline: CGFloat?) {
        guard !pts.isEmpty else { return }
        let p = NSBezierPath()
        let first = pts[0]
        p.move(to: NSPoint(x: baseline != nil ? full.minX : x(first.0), y: baseline != nil ? first.1 : first.1))
        for (t, y) in pts { p.line(to: NSPoint(x: x(t), y: y)) }
        if baseline != nil { p.line(to: NSPoint(x: full.maxX, y: pts.last!.1)) }
        color.setStroke(); p.lineWidth = 1.4; p.stroke()
        for (t, y) in pts {
            let d = NSRect(x: x(t) - 3, y: y - 3, width: 6, height: 6)
            color.setFill(); NSBezierPath(ovalIn: d).fill()
        }
    }

    // MARK: Interacción

    override func mouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(e.locationInWindow, from: nil)
        if p.y >= laneTop {
            laneClick = (max(0, time(p.x)), lanePoint(at: p.x))
            if e.clickCount == 2, let pt = laneClick.point { beginLaneEdit(pt); return }
        } else if p.y >= Self.rulerHeight {
            let hit = trackRects.last { $0.rect.contains(p) }
            Session.shared.selectedTrack = hit?.index
        }
        playhead = max(0, time(p.x))
        Player.shared.seek(playhead)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        if p.y >= laneTop {
            laneClick = (max(0, time(p.x)), lanePoint(at: p.x))
            return laneClick.point == nil ? MenuSpecs.timelineRuler.build() : MenuSpecs.timelineRulerMarker.build()
        }
        if p.y < Self.rulerHeight { return nil }
        if let hit = trackRects.last(where: { $0.rect.contains(p) }) {
            Session.shared.selectedTrack = hit.index
            playhead = max(0, time(p.x))
            return MenuSpecs.timelineTrack.build()
        }
        return MenuSpecs.timelineStrips.build()
    }

    // MARK: Doble clic en un BPM de la barra de tempos: se escribe ahí mismo

    private var laneEditor: NSTextField?
    private func beginLaneEdit(_ pt: (track: Int, type: UInt32, mix: Double)) {
        laneEditor?.removeFromSuperview()
        let v = Session.shared.layout.tempoPoints.first { $0.track == pt.track && abs($0.mix - pt.mix) < 1e-6 }?.bpm ?? 0
        let f = NSTextField(frame: NSRect(x: x(pt.mix) + 2, y: laneTop + 1, width: 62, height: Self.tempoLaneHeight - 2))
        f.stringValue = String(format: "%.2f", v)
        f.font = Theme.mono(9.5, .semibold)
        f.isBordered = false
        f.drawsBackground = true
        f.backgroundColor = NSColor(white: 0.92, alpha: 1)
        f.textColor = .black
        f.focusRingType = .none
        f.target = self
        f.action = #selector(laneEditDone(_:))
        addSubview(f)
        laneEditor = f
        window?.makeFirstResponder(f)
        f.currentEditor()?.selectAll(nil)
    }
    @objc private func laneEditDone(_ f: NSTextField) {
        let v = Double(f.stringValue.replacingOccurrences(of: ",", with: "."))
        f.removeFromSuperview()
        laneEditor = nil
        window?.makeFirstResponder(self)
        if let v, v >= 20, v <= 300 { (NSApp.delegate as? AppDelegate)?.setLaneMarkerValue(v) }
    }
    override func cancelOperation(_ sender: Any?) { laneEditor?.removeFromSuperview(); laneEditor = nil }

    // MARK: Soltar un efecto: en una pista (efecto de pista) o en el fondo (efecto del master)

    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { s.draggingPasteboard.types?.contains(.mm8Effect) == true ? .copy : [] }
    override func draggingUpdated(_ s: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        guard let name = s.draggingPasteboard.string(forType: .mm8Effect) else { return false }
        let p = convert(s.draggingLocation, from: nil)
        let hit = p.y >= Self.rulerHeight && p.y < laneTop ? trackRects.last { $0.rect.contains(p) }?.index : nil
        return EffectsActions.add(named: name, toTrack: hit)
    }

    override func keyDown(with e: NSEvent) {
        if e.charactersIgnoringModifiers == " " { Player.shared.toggle(from: playhead); return }
        super.keyDown(with: e)
    }

    override func scrollWheel(with e: NSEvent) {
        if e.modifierFlags.contains(.command) {
            pps = max(0.2, min(400, pps * (e.scrollingDeltaY > 0 ? 1.15 : 1 / 1.15)))
        } else { super.scrollWheel(with: e) }
    }
}
