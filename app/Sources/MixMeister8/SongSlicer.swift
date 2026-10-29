import AppKit
import AVFoundation

/// Rejilla del Song Slicer (Beat Slicer del original), en segundos del audio de la pista.
///
/// Modelo (comprobado con Spinning310 en MixMeister 7.8): TKTH guarda la duración de un compás
/// (BPM original = 240e6 / bar_us) y los marcadores de compás (TRKM 0x10000000) marcan dónde cae el
/// tiempo 1. Entre dos marcadores seguidos caben round(distancia / compás) compases iguales; la
/// rejilla va del primer marcador al último (con uno solo, sigue hasta el final con la duración del
/// compás). La regla numera cada marcador con su compás contado desde el primero («7:0», «16:0»…).
enum SlicerGrid {
    struct Grid {
        var measures: [(t: Double, n: Int)] = []
        var beats: [Double] = []
        var labels: [(t: Double, n: Int)] = []
    }

    static func build(markers m: [Double], bar: Double, end: Double) -> Grid {
        var g = Grid()
        guard let first = m.first, bar > 0.05 else { return g }
        var k = 0
        for i in 0..<(m.count - 1) {
            let a = m[i], b = m[i + 1]
            let n = max(1, Int(((b - a) / bar).rounded()))
            let len = (b - a) / Double(n)
            g.labels.append((a, k))
            for j in 0..<n {
                g.measures.append((a + Double(j) * len, k + j))
                for q in 0..<4 { g.beats.append(a + (Double(j) + Double(q) / 4) * len) }
            }
            k += n
        }
        let last = m[m.count - 1]
        g.labels.append((last, k))
        if m.count == 1 {
            var t = first
            while t < end {
                g.measures.append((t, k))
                for q in 0..<4 { g.beats.append(t + Double(q) * bar / 4) }
                t += bar; k += 1
            }
        } else { g.measures.append((last, k)); g.beats.append(last) }
        return g
    }

    /// Al cambiar el BPM original, los marcadores siguen en su sitio y se quitan los que ya no caen
    /// en un compás entero. Observado en el original: de 101,96 a 50 BPM (compás ×2) quedan los
    /// marcadores de los compases pares (16→8, 20→10, 28→14, 50→25) y se quitan los impares.
    static func rescale(markers m: [Int64], oldBar: Double, newBar: Double) -> [Int64] {
        guard m.count > 1, oldBar > 0, newBar > 0 else { return m }
        let r = oldBar / newBar
        var frac: (p: Int, q: Int)?
        for q in 1...4 { for p in 1...4 where abs(Double(p) / Double(q) - r) / r < 0.03 && p != q { if frac == nil { frac = (p, q) } } }
        guard let (p, q) = frac else { return m }
        let m0 = m[0]
        return m.enumerated().filter { i, x in
            if i == 0 { return true }
            let k = Int((Double(x - m0) / oldBar).rounded())
            return (k * p) % q == 0
        }.map(\.element)
    }
}

/// Song Slicer: a la izquierda el BPM original (arrastrar para cambiarlo, doble clic para
/// escribirlo), el nombre y los botones; a la derecha la pista entera con la rejilla.
final class SongSlicerView: NSView {
    let badge = BPMBadge()
    private let title = label("", size: 10.5, weight: .semibold)
    let canvas = SlicerCanvas()
    private let scroll = NSScrollView()
    private var buttons: [NSButton] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        let left = FillView(Theme.panelRaised)
        left.translatesAutoresizingMaskIntoConstraints = false
        title.lineBreakMode = .byTruncatingTail
        badge.toolTip = "Original BPM for this track"
        badge.onCommit = { [weak self] v in self?.canvas.setBPM(v) }
        let play = ToolButton(symbol: "play.fill", tip: "Play a preview with metronome", action: #selector(SlicerCanvas.previewPlay), target: canvas, size: 11)
        let stop = ToolButton(symbol: "stop.fill", tip: "Stop previewing", action: #selector(SlicerCanvas.previewStop), target: canvas, size: 11)
        let drop = ToolButton(symbol: "flag", tip: "Add Measure Start Marker", action: #selector(SlicerCanvas.addMeasureStartMarker(_:)), target: canvas, size: 11)
        let save = ToolButton(symbol: "square.and.arrow.down", tip: "Save measure markers as a Tweak", action: #selector(SlicerCanvas.saveTemplate), target: canvas, size: 11)
        let restore = ToolButton(symbol: "arrow.uturn.backward", tip: "Restore default measure markers", action: #selector(SlicerCanvas.restoreTemplate), target: canvas, size: 11)
        let clear = ToolButton(symbol: "xmark", tip: "Delete all measure markers", action: #selector(SlicerCanvas.deleteAllMeasureMarkers(_:)), target: canvas, size: 11)
        buttons = [play, stop, drop, save, restore, clear]
        let row1 = NSStackView(views: [play, stop, NSView(), drop])
        let row2 = NSStackView(views: [save, restore, NSView(), clear])
        for r in [row1, row2] { r.spacing = 2 }
        let top = NSStackView(views: [NSView(), badge])
        let col = NSStackView(views: [top, title, row1, row2])
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 4
        col.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        col.translatesAutoresizingMaskIntoConstraints = false
        left.addSubview(col)
        addSubview(left)
        scroll.documentView = canvas
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = false
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        canvas.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            left.topAnchor.constraint(equalTo: topAnchor), left.bottomAnchor.constraint(equalTo: bottomAnchor),
            left.leadingAnchor.constraint(equalTo: leadingAnchor), left.widthAnchor.constraint(equalToConstant: 150),
            col.topAnchor.constraint(equalTo: left.topAnchor), col.leadingAnchor.constraint(equalTo: left.leadingAnchor),
            col.trailingAnchor.constraint(equalTo: left.trailingAnchor),
            top.widthAnchor.constraint(equalToConstant: 134), title.widthAnchor.constraint(equalToConstant: 134),
            row1.widthAnchor.constraint(equalToConstant: 134), row2.widthAnchor.constraint(equalToConstant: 134),
            badge.widthAnchor.constraint(equalToConstant: 58), badge.heightAnchor.constraint(equalToConstant: 18),
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: left.trailingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            canvas.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            canvas.heightAnchor.constraint(equalTo: scroll.contentView.heightAnchor),
            canvas.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            canvas.widthAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.widthAnchor),
        ])
        canvas.slicer = self
        for n: Notification.Name in [.selectionChanged, .playlistChanged, .waveformReady] {
            NotificationCenter.default.addObserver(self, selector: #selector(reload), name: n, object: nil)
        }
        reload()
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc func reload() {
        let s = Session.shared
        let i = s.selectedTrack.flatMap { $0 < s.doc.tracks.count ? $0 : nil }
        canvas.track = i
        if let i {
            let t = s.doc.tracks[i]
            let lib = s.libraryItem(for: t)
            title.stringValue = "\(i + 1) - \"\(lib.map { $0.title.isEmpty ? t.title : $0.title } ?? t.title)\""
            badge.value = t.bar_us > 0 ? 240e6 / Double(t.bar_us) : (t.original_bpm ?? t.bpm)
        } else {
            title.stringValue = "Selecciona una pista"
            badge.value = 0
        }
        badge.isEnabled = i != nil
        for b in buttons { b.isEnabled = i != nil }
        canvas.resetDraft()
        canvas.needsDisplay = true
        canvas.invalidateIntrinsicContentSize()
    }
}

/// Insignia del BPM original: clic sostenido y arrastrar = subir o bajar el tempo; doble clic =
/// escribirlo (como en el original).
final class BPMBadge: NSView, NSTextFieldDelegate {
    var value: Double = 0 { didSet { needsDisplay = true } }
    var isEnabled = true { didSet { needsDisplay = true } }
    var onCommit: ((Double) -> Void)?
    private var drag: (x: CGFloat, y: CGFloat, v: Double)?
    private var editor: NSTextField?

    override func draw(_ r: NSRect) {
        let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        (drag != nil ? Theme.accentDeep : Theme.background).setFill(); p.fill()
        Theme.gridStrong.setStroke(); p.stroke()
        guard editor == nil else { return }
        let s = value > 0 ? String(format: "%.2f", value) : "—"
        let a: [NSAttributedString.Key: Any] = [.font: Theme.mono(10.5, .semibold), .foregroundColor: isEnabled ? Theme.text : Theme.textDim]
        let sz = (s as NSString).size(withAttributes: a)
        (s as NSString).draw(at: NSPoint(x: (bounds.width - sz.width) / 2, y: (bounds.height - sz.height) / 2), withAttributes: a)
    }

    override func mouseDown(with e: NSEvent) {
        guard isEnabled, value > 0 else { return }
        if e.clickCount == 2 { beginEditing(); return }
        drag = (e.locationInWindow.x, e.locationInWindow.y, value)
        needsDisplay = true
    }
    override func mouseDragged(with e: NSEvent) {
        guard let d = drag else { return }
        let k = e.modifierFlags.contains(.shift) ? 0.002 : 0.02
        value = max(20, min(300, d.v + Double((e.locationInWindow.x - d.x) + (e.locationInWindow.y - d.y)) * k))
    }
    override func mouseUp(with e: NSEvent) {
        guard let d = drag else { return }
        drag = nil
        needsDisplay = true
        if abs(value - d.v) > 1e-4 { onCommit?((value * 100).rounded() / 100) }
    }

    func beginEditing() {
        let f = NSTextField(frame: bounds.insetBy(dx: 3, dy: 1))
        f.stringValue = String(format: "%.2f", value)
        f.font = Theme.mono(10.5, .semibold)
        f.alignment = .center
        f.isBordered = false
        f.drawsBackground = true
        f.backgroundColor = NSColor(white: 0.9, alpha: 1)
        f.textColor = .black
        f.focusRingType = .none
        f.delegate = self
        f.target = self
        f.action = #selector(commit)
        addSubview(f)
        editor = f
        needsDisplay = true
        window?.makeFirstResponder(f)
        f.currentEditor()?.selectAll(nil)
    }
    @objc private func commit() {
        guard let f = editor else { return }
        let v = Double(f.stringValue.replacingOccurrences(of: ",", with: "."))
        endEditing()
        if let v, v >= 20, v <= 300 { value = v; onCommit?(v) }
    }
    private func endEditing() {
        editor?.removeFromSuperview()
        editor = nil
        needsDisplay = true
    }
    func control(_ c: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.cancelOperation(_:)) { endEditing(); return true }
        return false
    }
    func controlTextDidEndEditing(_ obj: Notification) { if editor != nil { commit() } }
}

/// La pista entera en verde con la rejilla de tiempos, los marcadores de compás (naranja, con
/// bandera), la regla «compás:tiempo» y las flechas blancas para mover la rejilla.
final class SlicerCanvas: NSView {
    weak var slicer: SongSlicerView?
    var track: Int?
    var zoom: CGFloat = 1 { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    private var cursor: Double = 0
    /// Cambios en curso (al arrastrar) antes de pasarlos a la lista.
    private var draft: (markers: [Int64], bar: Int64)?
    private enum Drag { case shift(start: Double, orig: [Int64]), stretchEnd(orig: [Int64], bar: Int64), stretchStart(orig: [Int64], bar: Int64), marker(Int, orig: [Int64]) }
    private var drag: Drag?
    private let preview = SlicerPreview()
    static let rulerHeight: CGFloat = 16
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        menu = MenuSpecs.songSlicer.build()
        preview.onTick = { [weak self] in self?.needsDisplay = true }
    }
    required init?(coder: NSCoder) { fatalError() }

    func resetDraft() { draft = nil; drag = nil }

    private var t: PLTrack? { track.flatMap { $0 < Session.shared.doc.tracks.count ? Session.shared.doc.tracks[$0] : nil } }
    private var audioPath: String? { track.flatMap { Session.shared.audioPath($0) } }
    private var duration: Double {
        if let p = audioPath, let w = Waveforms.shared.get(p) { return w.seconds }
        return Double(t?.length_us ?? 0) * 1e-6
    }
    private var markers: [Int64] { draft?.markers ?? (t?.beat_markers_us.sorted() ?? []) }
    private var bar: Int64 { draft?.bar ?? (t?.bar_us ?? 0) }

    override var intrinsicContentSize: NSSize { NSSize(width: max(400, (superview?.bounds.width ?? 800) * zoom), height: NSView.noIntrinsicMetric) }
    private var pps: CGFloat { duration > 0 ? bounds.width / CGFloat(duration) : 1 }
    private func x(_ s: Double) -> CGFloat { CGFloat(s) * pps }
    private func time(_ px: CGFloat) -> Double { Double(px / pps) }

    override func draw(_ dirty: NSRect) {
        Theme.background.setFill(); dirty.fill()
        guard let tr = t, duration > 0 else {
            ("Selecciona una pista en la línea de tiempo o en la lista." as NSString).draw(at: NSPoint(x: 12, y: 24),
                withAttributes: [.font: Theme.font(11), .foregroundColor: Theme.textDim])
            return
        }
        let m = markers.map { Double($0) * 1e-6 }
        let g = SlicerGrid.build(markers: m, bar: Double(bar) * 1e-6, end: duration)
        let body = NSRect(x: 0, y: Self.rulerHeight, width: bounds.width, height: bounds.height - Self.rulerHeight)
        // Zona con rejilla, en verde claro (como el original)
        if let a = g.measures.first?.t, let b = g.measures.last?.t {
            let gx = NSRect(x: x(a), y: body.minY, width: max(1, x(m.count == 1 ? duration : b) - x(a)), height: body.height)
            Theme.accent.withAlphaComponent(0.28).setFill(); gx.fill()
        }
        // Forma de onda
        if let p = audioPath, let w = Waveforms.shared.get(p) {
            let path = NSBezierPath()
            let base = body.maxY - 2, amp = body.height - 6
            var px = max(0, dirty.minX)
            while px < min(bounds.width, dirty.maxX) {
                let bin = Int(time(px) / w.seconds * Double(w.peaks.count))
                if bin >= 0, bin < w.peaks.count {
                    path.move(to: NSPoint(x: px, y: base)); path.line(to: NSPoint(x: px, y: base - CGFloat(w.peaks[bin]) * amp))
                }
                px += 1
            }
            Theme.accent.withAlphaComponent(0.9).setStroke(); path.lineWidth = 1; path.stroke()
        }
        // Tiempos y compases
        for b in g.beats where x(b) >= dirty.minX - 2 && x(b) <= dirty.maxX + 2 {
            Theme.accentDeep.withAlphaComponent(0.55).setFill()
            NSRect(x: x(b), y: body.minY, width: 1, height: body.height).fill()
        }
        for mm in g.measures where x(mm.t) >= dirty.minX - 2 && x(mm.t) <= dirty.maxX + 2 {
            Theme.background.withAlphaComponent(0.55).setFill()
            NSRect(x: x(mm.t), y: body.minY, width: 1, height: body.height).fill()
        }
        // Regla y marcadores de compás
        Theme.header.setFill(); NSRect(x: dirty.minX, y: 0, width: dirty.width, height: Self.rulerHeight).fill()
        if let a = g.measures.first?.t {
            let b = m.count == 1 ? duration : (g.measures.last?.t ?? a)
            Theme.accent.setFill(); NSRect(x: x(a), y: Self.rulerHeight - 5, width: x(b) - x(a), height: 5).fill()
        }
        let la: [NSAttributedString.Key: Any] = [.font: Theme.mono(8.5, .semibold), .foregroundColor: Theme.text]
        for l in g.labels {
            let px = x(l.t)
            Theme.anchor.setFill()
            NSRect(x: px, y: Self.rulerHeight, width: 1.5, height: body.height).fill()
            let flag = NSBezierPath()
            flag.move(to: NSPoint(x: px, y: Self.rulerHeight)); flag.line(to: NSPoint(x: px + 7, y: Self.rulerHeight + 4)); flag.line(to: NSPoint(x: px, y: Self.rulerHeight + 8))
            flag.close(); flag.fill()
            ("\(l.n):0" as NSString).draw(at: NSPoint(x: px + 3, y: 1), withAttributes: la)
        }
        // Flechas para mover la rejilla (primer y último marcador)
        for px in [m.first, m.count > 1 ? m.last : nil].compactMap({ $0 }).map(x) {
            let h = NSBezierPath()
            h.move(to: NSPoint(x: px - 7, y: 8)); h.line(to: NSPoint(x: px - 2, y: 4)); h.line(to: NSPoint(x: px - 2, y: 12)); h.close()
            h.move(to: NSPoint(x: px + 7, y: 8)); h.line(to: NSPoint(x: px + 2, y: 4)); h.line(to: NSPoint(x: px + 2, y: 12)); h.close()
            NSColor.white.setFill(); h.fill()
        }
        // Cursor y preescucha
        Theme.playhead.setFill()
        NSRect(x: x(preview.isPlaying ? preview.position : cursor) - 0.5, y: 0, width: 1.5, height: bounds.height).fill()
        _ = tr
    }

    // MARK: Ratón

    private func hit(_ p: NSPoint) -> Drag? {
        let m = markers
        guard !m.isEmpty else { return nil }
        let xs = m.map { x(Double($0) * 1e-6) }
        if p.y < Self.rulerHeight {
            if abs(p.x - xs[0]) < 9 { return .shift(start: time(p.x), orig: m) }
            if m.count > 1, abs(p.x - xs[xs.count - 1]) < 9 { return .shift(start: time(p.x), orig: m) }
            if let i = xs.indices.dropFirst().dropLast().min(by: { abs(xs[$0] - p.x) < abs(xs[$1] - p.x) }), abs(xs[i] - p.x) < 6 { return .marker(i, orig: m) }
            return nil
        }
        if m.count > 1, abs(p.x - xs[xs.count - 1]) < 4 { return .stretchEnd(orig: m, bar: bar) }
        if abs(p.x - xs[0]) < 4 { return m.count > 1 ? .stretchStart(orig: m, bar: bar) : .shift(start: time(p.x), orig: m) }
        return nil
    }

    override func mouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(e.locationInWindow, from: nil)
        drag = hit(p)
        if drag == nil {
            cursor = max(0, min(duration, time(p.x)))
            if preview.isPlaying, let tr = t, let path = audioPath { preview.play(path: path, from: cursor, beats: grid(tr).beats, downbeats: Set(grid(tr).measures.map(\.t))) }
            needsDisplay = true
        }
    }
    private func grid(_ tr: PLTrack) -> SlicerGrid.Grid {
        SlicerGrid.build(markers: markers.map { Double($0) * 1e-6 }, bar: Double(bar) * 1e-6, end: duration)
    }

    override func mouseDragged(with e: NSEvent) {
        guard let d = drag else { return }
        let now = time(convert(e.locationInWindow, from: nil).x)
        switch d {
        case let .shift(start, orig):
            let dt = Int64((now - start) * 1e6)
            draft = (orig.map { $0 + dt }, bar)
        case let .stretchEnd(orig, b0):
            let a = orig[0], z = orig[orig.count - 1]
            let nz = max(a + 200_000, Int64(now * 1e6))
            let k = Double(nz - a) / Double(z - a)
            draft = (orig.map { a + Int64(Double($0 - a) * k) }, Int64(Double(b0) * k))
        case let .stretchStart(orig, b0):
            let a = orig[0], z = orig[orig.count - 1]
            let na = min(z - 200_000, Int64(now * 1e6))
            let k = Double(z - na) / Double(z - a)
            draft = (orig.map { z - Int64(Double(z - $0) * k) }, Int64(Double(b0) * k))
        case let .marker(i, orig):
            var m = orig
            m[i] = max(orig[i - 1] + 50_000, min(orig[i + 1] - 50_000, Int64(now * 1e6)))
            draft = (m, bar)
        }
        if let b = draft?.bar, b > 0 { slicer?.badge.value = 240e6 / Double(b) }
        needsDisplay = true
    }

    override func mouseUp(with e: NSEvent) {
        defer { drag = nil }
        guard drag != nil, let d = draft, let i = track else { return }
        commit(i, markers: d.markers, bar: d.bar, name: "Song Slicer")
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        cursor = max(0, min(duration, time(convert(event.locationInWindow, from: nil).x)))
        needsDisplay = true
        return track == nil ? nil : MenuSpecs.songSlicer.build(target: self)
    }

    override func scrollWheel(with e: NSEvent) {
        if e.modifierFlags.contains(.command) { zoom = max(1, min(64, zoom * (e.scrollingDeltaY > 0 ? 1.15 : 1 / 1.15))) }
        else { super.scrollWheel(with: e) }
    }

    override func keyDown(with e: NSEvent) {
        if e.charactersIgnoringModifiers == " " { preview.isPlaying ? previewStop() : previewPlay(); return }
        super.keyDown(with: e)
    }

    // MARK: Cambios en la lista

    /// Pasa a la lista la rejilla. Si cambió el compás, cambia también el BPM original de la pista
    /// (TRKH, y el valor de sus marcadores de tempo original), como el original.
    private func commit(_ i: Int, markers m: [Int64], bar b: Int64, name: String) {
        let s = Session.shared
        guard i < s.doc.tracks.count else { return }
        let old = s.doc.tracks[i]
        draft = nil
        let tempoChanged = b != old.bar_us && b > 0
        let change: (inout PLDocument) -> Void = { d in
            d.tracks[i].beat_markers_us = m.sorted()
            d.tracks[i].bar_us = b
            if tempoChanged {
                let bpm = (240e6 / Double(b) * 1000).rounded() / 1000
                d.tracks[i].bpm = bpm
                d.tracks[i].original_bpm = bpm
                d.tracks[i].layer = d.tracks[i].layer.map { li in
                    if case var .marker(mk) = li, mk.type == MarkerKind.originalTempo { mk.value = bpm; return .marker(mk) }
                    return li
                }
            }
        }
        if tempoChanged { s.mutate(name, change) } else { s.mutateLight(name, change) }
    }

    func setBPM(_ v: Double) {
        guard let i = track, let tr = t, v > 0 else { return }
        let nb = Int64((240e6 / v).rounded())
        commit(i, markers: SlicerGrid.rescale(markers: tr.beat_markers_us.sorted(), oldBar: Double(tr.bar_us), newBar: Double(nb)), bar: nb, name: "Change Original BPM")
    }

    @objc func addMeasureStartMarker(_ s: Any?) {
        guard let i = track else { return }
        var m = markers
        let at = Int64(cursor * 1e6)
        guard !m.contains(where: { abs($0 - at) < 20_000 }) else { return }
        m.append(at)
        commit(i, markers: m.sorted(), bar: bar > 0 ? bar : Int64(240e6 / max(1, t?.bpm ?? 120)), name: "Add Measure Start Marker")
    }
    @objc func deleteAllMeasureMarkers(_ s: Any?) {
        guard let i = track else { return }
        commit(i, markers: [], bar: bar, name: "Delete All Measure Markers")
    }
    /// Restore default measure markers: la rejilla del análisis (tempo y primer compás).
    @objc func restoreTemplate() {
        guard let i = track, let p = audioPath else { NSSound.beep(); return }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let a = Engine.analyzeCached(path: p), a.bpm > 0 else { DispatchQueue.main.async { NSSound.beep() }; return }
            let beat = 60 / a.bpm, barS = 4 * beat
            let m0 = a.first_beat_s + Double(a.downbeat) * beat
            let n = max(1, Int(((a.seconds - m0) / barS).rounded(.down)))
            DispatchQueue.main.async {
                self.commit(i, markers: [Int64(m0 * 1e6), Int64((m0 + Double(n) * barS) * 1e6)], bar: Int64(barS * 1e6), name: "Restore Default Measure Markers")
            }
        }
    }
    /// Save measure markers as a Tweak: abre el diálogo Tweaks de la pista (el manual: «click Save
    /// Measure Markers as Tweak, click Save As, type a name»). El Tweak lleva la rejilla (TKTM).
    @objc func saveTemplate() {
        guard let i = Session.shared.selectedTrack, i < Session.shared.doc.tracks.count else { return }
        TweaksDialog(track: i, item: nil).run()
    }

    // MARK: Preescucha con metrónomo

    @objc func previewPlay() {
        guard let tr = t, let path = audioPath else { NSSound.beep(); return }
        Player.shared.stop()
        let g = grid(tr)
        preview.play(path: path, from: cursor, beats: g.beats, downbeats: Set(g.measures.map(\.t)))
    }
    @objc func previewStop() {
        if preview.isPlaying { cursor = preview.position }
        preview.stop()
        needsDisplay = true
    }
}

/// Preescucha del Song Slicer: la pista a su tempo con un metrónomo en cada tiempo de la rejilla
/// (agudo en el tiempo 1). Clics generados aquí, no los del original.
final class SlicerPreview {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let metro = AVAudioPlayerNode()
    private var startHost: UInt64 = 0
    private var from: Double = 0
    private var timer: Timer?
    private(set) var isPlaying = false
    var onTick: (() -> Void)?

    init() {
        engine.attach(player)
        engine.attach(metro)
    }

    var position: Double {
        guard isPlaying else { return from }
        let now = mach_absolute_time()
        guard now > startHost else { return from }
        var tb = mach_timebase_info_data_t(); mach_timebase_info(&tb)
        return from + Double(now - startHost) * Double(tb.numer) / Double(tb.denom) / 1e9
    }

    private static func click(_ fmt: AVAudioFormat, hz: Double, gain: Float) -> AVAudioPCMBuffer? {
        let n = AVAudioFrameCount(fmt.sampleRate * 0.03)
        guard let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n), let ch = b.floatChannelData else { return nil }
        b.frameLength = n
        for i in 0..<Int(n) {
            let t = Double(i) / fmt.sampleRate
            let v = Float(sin(2 * .pi * hz * t) * exp(-t * 140)) * gain
            for c in 0..<Int(fmt.channelCount) { ch[c][i] = v }
        }
        return b
    }

    func play(path: String, from start: Double, beats: [Double], downbeats: Set<Double>) {
        stop()
        guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) else { return }
        let fmt = file.processingFormat, sr = fmt.sampleRate
        engine.connect(player, to: engine.mainMixerNode, format: fmt)
        engine.connect(metro, to: engine.mainMixerNode, format: fmt)
        if let dev = OutputConfig.main(), let au = engine.outputNode.audioUnit {
            var id = dev.id
            AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        // Las marcas están en la línea de tiempo de MixMeister; el fichero, en la de AVAudioFile.
        let lead = Engine.mmOffset(path, rate: sr)
        var a = AVAudioFramePosition(max(0, start) * sr) - lead
        var wait: AVAudioFramePosition = 0
        if a < 0 { wait = -a; a = 0 }
        guard a < file.length else { return }
        player.scheduleSegment(file, startingFrame: a, frameCount: AVAudioFrameCount(file.length - a),
                               at: wait > 0 ? AVAudioTime(sampleTime: wait, atRate: sr) : nil)
        let hi = Self.click(fmt, hz: 1760, gain: 0.6), lo = Self.click(fmt, hz: 1175, gain: 0.45)
        for b in beats where b >= start {
            let isDown = downbeats.contains { abs($0 - b) < 1e-6 }
            if let buf = isDown ? hi : lo {
                metro.scheduleBuffer(buf, at: AVAudioTime(sampleTime: AVAudioFramePosition((b - start) * sr), atRate: sr))
            }
        }
        engine.prepare()
        do { try engine.start() } catch { Log.write("Song Slicer: no arranca el audio: \(error)"); return }
        var tb = mach_timebase_info_data_t(); mach_timebase_info(&tb)
        let host = mach_absolute_time() + UInt64(0.08 * 1e9 * Double(tb.denom) / Double(tb.numer))
        let when = AVAudioTime(hostTime: host)
        player.play(at: when)
        metro.play(at: when)
        startHost = host
        from = start
        isPlaying = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.onTick?() }
    }

    func stop() {
        if isPlaying { from = position }
        timer?.invalidate(); timer = nil
        player.stop(); metro.stop()
        engine.stop()
        isPlaying = false
        onTick?()
    }
}
