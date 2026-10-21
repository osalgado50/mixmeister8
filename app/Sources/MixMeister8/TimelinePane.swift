import AppKit

/// Línea de tiempo con su barra (Snap To Beat, carriles, CURRENT/REMAINING/TOTAL, tempo master,
/// zoom), controles de carril a la izquierda y medidores a la derecha.
final class TimelinePane: NSView {
    let timeline = TimelineView()
    private let scroll = NSScrollView()
    private let status = label("CURRENT 00:00:00   REMAINING 00:00:00   TOTAL 00:00:00", size: 10.5, weight: .semibold, color: Theme.onAccent)
    private let bpmField = NSTextField()
    private let bpmStepper = NSStepper()
    private let zoom = NSSlider(value: 0.35, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let snap = NSButton()
    private let strips = NSPopUpButton()
    private let stripControls = StripControls()
    private let meters = MeterView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Theme.background.cgColor

        let bar = FillView(Theme.header)
        bar.bottomLine = Theme.gridStrong
        bar.translatesAutoresizingMaskIntoConstraints = false
        snap.setButtonType(.toggle)
        snap.bezelStyle = .recessed
        snap.title = "Snap"
        snap.font = Theme.font(10.5, .medium)
        snap.controlSize = .small
        snap.action = NSSelectorFromString("snapToBeat:")
        snap.toolTip = "Snap To Beat (⇧⌘B)"
        strips.controlSize = .small
        strips.font = Theme.font(10.5)
        strips.addItems(withTitles: ["2 Strips", "4 Strips", "6 Strips", "8 Strips"])
        strips.target = self
        strips.action = #selector(stripsChosen)
        let pill = FillView(Theme.accent)
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 9
        pill.translatesAutoresizingMaskIntoConstraints = false
        status.font = Theme.mono(10.5, .semibold)
        status.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(status)
        bpmField.font = Theme.mono(11, .semibold)
        bpmField.alignment = .right
        bpmField.isBordered = false
        bpmField.drawsBackground = true
        bpmField.backgroundColor = Theme.panelRaised
        bpmField.textColor = Theme.text
        bpmField.isEditable = true
        bpmField.focusRingType = .none
        bpmField.target = self
        bpmField.action = #selector(bpmTyped)
        bpmField.toolTip = "Master BPM: escribe un tempo o usa las flechas (añade un marcador de tempo en el cursor)"
        bpmStepper.minValue = 20; bpmStepper.maxValue = 300; bpmStepper.increment = 0.1
        bpmStepper.valueWraps = false
        bpmStepper.controlSize = .small
        bpmStepper.target = self
        bpmStepper.action = #selector(bpmStepped)
        zoom.controlSize = .small
        zoom.target = self
        zoom.action = #selector(zoomed)
        let bpmLabel = label("BPM", size: 9.5, weight: .semibold, color: Theme.textDim)
        let stack = NSStackView(views: [snap, strips, pill, NSView(), bpmLabel, bpmField, bpmStepper, label("ZOOM", size: 9.5, weight: .semibold, color: Theme.textDim), zoom])
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        addSubview(bar)

        scroll.documentView = timeline
        scroll.hasHorizontalScroller = true
        scroll.scrollerStyle = .overlay          // flota sobre la línea de tiempo: sin hueco abajo
        scroll.autohidesScrollers = true
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        timeline.translatesAutoresizingMaskIntoConstraints = false
        stripControls.translatesAutoresizingMaskIntoConstraints = false
        meters.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stripControls)
        addSubview(scroll)
        addSubview(meters)

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: topAnchor), bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor), bar.heightAnchor.constraint(equalToConstant: 30),
            stack.topAnchor.constraint(equalTo: bar.topAnchor), stack.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor), stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            pill.heightAnchor.constraint(equalToConstant: 18),
            status.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 10), status.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -10),
            status.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            bpmField.widthAnchor.constraint(equalToConstant: 56), zoom.widthAnchor.constraint(equalToConstant: 160),
            stripControls.topAnchor.constraint(equalTo: bar.bottomAnchor), stripControls.leadingAnchor.constraint(equalTo: leadingAnchor),
            stripControls.bottomAnchor.constraint(equalTo: bottomAnchor), stripControls.widthAnchor.constraint(equalToConstant: 132),
            meters.topAnchor.constraint(equalTo: bar.bottomAnchor), meters.trailingAnchor.constraint(equalTo: trailingAnchor),
            meters.bottomAnchor.constraint(equalTo: bottomAnchor), meters.widthAnchor.constraint(equalToConstant: 44),
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor), scroll.leadingAnchor.constraint(equalTo: stripControls.trailingAnchor),
            scroll.trailingAnchor.constraint(equalTo: meters.leadingAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            timeline.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            timeline.heightAnchor.constraint(equalTo: scroll.contentView.heightAnchor),
            timeline.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(update), name: .playlistChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(playerTick), name: .playerTick, object: nil)
        zoomed()
        update()
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc func update() {
        let s = Session.shared
        strips.selectItem(at: [2, 4, 6, 8].firstIndex(of: s.strips) ?? 1)
        showTempo()
        stripControls.strips = s.strips
        updateStatus()
    }

    /// Master BPM: el tempo de la mezcla en el cursor.
    func showTempo() {
        let L = Session.shared.layout
        guard L.masterBPM > 0, window?.firstResponder !== bpmField.currentEditor() else { if L.masterBPM <= 0 { bpmField.stringValue = "—" }; return }
        let t = L.tempo(at: timeline.playhead)
        bpmField.stringValue = String(format: "%.2f", t)
        bpmStepper.doubleValue = t
    }
    @objc private func bpmStepped() { setTempo(bpmStepper.doubleValue) }
    @objc private func bpmTyped() {
        if let v = Double(bpmField.stringValue.replacingOccurrences(of: ",", with: ".")), v >= 20, v <= 300 { setTempo(v) }
        window?.makeFirstResponder(timeline)
    }
    private func setTempo(_ v: Double) {
        (NSApp.delegate as? AppDelegate)?.setMasterTempo((v * 100).rounded() / 100, at: timeline.playhead)
    }

    func updateStatus() {
        let s = Session.shared
        let total = s.layout.total
        let cur = min(timeline.playhead, total)
        let idx = s.layout.items.last { !$0.overlay && $0.mixStart <= cur }.map { $0.index + 1 } ?? (s.doc.tracks.isEmpty ? 0 : 1)
        func hms(_ t: Double) -> String { String(format: "%02d:%02d:%02d", Int(t) / 3600, Int(t) / 60 % 60, Int(t) % 60) }
        let rec = Player.shared.isRecording ? "   ● REC \(hms(Player.shared.recordedSeconds))" : ""
        status.stringValue = "CURRENT \(hms(cur))(\(idx))   REMAINING \(hms(max(0, total - cur)))   TOTAL \(hms(total))(\(s.doc.tracks.count))" + rec
    }

    /// Sigue a la reproducción: cursor, contadores, medidores y desplazamiento de la vista.
    @objc private func playerTick() {
        let p = Player.shared
        timeline.playhead = p.position
        meters.left = p.peakL; meters.right = p.peakR; meters.lufs = p.isPlaying ? p.shortTermLUFS : -.infinity; meters.needsDisplay = true
        updateStatus()
        showTempo()
        if p.isPlaying {
            let x = timeline.x(p.position)
            let vis = scroll.contentView.bounds
            if x > vis.maxX - 60 || x < vis.minX {
                scroll.contentView.scroll(to: NSPoint(x: max(0, x - vis.width * 0.25), y: 0))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
    }

    @objc private func stripsChosen() { Session.shared.strips = [2, 4, 6, 8][max(0, strips.indexOfSelectedItem)] }

    /// El deslizador va en escala logarítmica: de ver toda la mezcla a ver tiempos sueltos.
    @objc private func zoomed() {
        timeline.pps = CGFloat(0.5 * pow(400.0, zoom.doubleValue))
        updateStatus()
    }
    func zoom(by factor: Double) {
        let v = zoom.doubleValue + log(factor) / log(400.0)
        zoom.doubleValue = max(0, min(1, v))
        zoomed()
    }
}

/// Controles de cada carril (como en el original: activar, volumen y ecualización, bucle 1/2/4/8).
final class StripControls: FillView {
    var strips = 4 { didSet { needsDisplay = true } }
    init() { super.init(Theme.panelRaised) }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ r: NSRect) {
        super.draw(r)
        let h = (bounds.height - TimelineView.rulerHeight - TimelineView.tempoLaneHeight) / CGFloat(strips)
        let a: [NSAttributedString.Key: Any] = [.font: Theme.font(9, .semibold), .foregroundColor: Theme.textDim]
        for k in 0..<strips {
            let y = TimelineView.rulerHeight + CGFloat(k) * h
            Theme.grid.setFill(); NSRect(x: 0, y: y + h - 1, width: bounds.width, height: 1).fill()
            ("STRIP \(k + 1)" as NSString).draw(at: NSPoint(x: 8, y: y + 5), withAttributes: a)
            for (i, name) in ["VOL", "BASS", "MID", "TREB"].enumerated() {
                let c = NSRect(x: 8 + CGFloat(i) * 30, y: y + 20, width: 22, height: 22)
                Theme.panel.setFill(); NSBezierPath(ovalIn: c).fill()
                Theme.gridStrong.setStroke(); NSBezierPath(ovalIn: c).stroke()
                Theme.accent.setFill(); NSRect(x: c.midX - 1, y: c.minY + 3, width: 2, height: 7).fill()
                (name as NSString).draw(at: NSPoint(x: c.minX + (name.count == 3 ? 3 : 0), y: c.maxY + 1), withAttributes: [.font: Theme.font(7.5), .foregroundColor: Theme.textDim])
            }
            if h > 70 {
                for (i, n) in ["1", "2", "4", "8"].enumerated() {
                    let b = NSRect(x: 8 + CGFloat(i) * 26, y: y + 56, width: 22, height: 14)
                    Theme.panel.setFill(); NSBezierPath(roundedRect: b, xRadius: 3, yRadius: 3).fill()
                    (n as NSString).draw(at: NSPoint(x: b.minX + 8, y: b.minY + 1), withAttributes: [.font: Theme.font(9, .semibold), .foregroundColor: Theme.text])
                }
            }
        }
    }
}

/// Medidores de salida L/R (se mueven con la reproducción).
final class MeterView: FillView {
    var left: Float = 0, right: Float = 0
    /// Sonoridad a corto plazo (LUFS), debajo de los medidores (nuevo en MixMeister 8).
    var lufs: Double = -.infinity
    init() { super.init(Theme.panelRaised) }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ r: NSRect) {
        super.draw(r)
        let h = bounds.height - 40
        let a: [NSAttributedString.Key: Any] = [.font: Theme.mono(9, .semibold), .foregroundColor: lufs > -9 ? Theme.bass : Theme.text]
        let txt = lufs.isFinite && lufs > -70 ? String(format: "%.1f", lufs) : "—"
        let sz = (txt as NSString).size(withAttributes: a)
        (txt as NSString).draw(at: NSPoint(x: (bounds.width - sz.width) / 2, y: bounds.height - 26), withAttributes: a)
        ("LUFS" as NSString).draw(at: NSPoint(x: 9, y: bounds.height - 14), withAttributes: [.font: Theme.font(7.5, .semibold), .foregroundColor: Theme.textDim])
        for (i, v) in [left, right].enumerated() {
            let bar = NSRect(x: 10 + CGFloat(i) * 14, y: 10, width: 9, height: h)
            Theme.background.setFill(); bar.fill()
            let lvl = CGFloat(max(0, min(1, v)))
            let fill = NSRect(x: bar.minX, y: bar.maxY - h * lvl, width: bar.width, height: h * lvl)
            (lvl > 0.9 ? Theme.bass : Theme.accent).setFill(); fill.fill()
        }
    }
}

/// Panel inferior: Song Slicer / Effects Rack (pestañas, como en el original).
final class BottomPane: NSView {
    let tabs = NSSegmentedControl(labels: ["Song Slicer", "Effects Rack"], trackingMode: .selectOne, target: nil, action: nil)
    let slicer = SongSlicerView()
    let rack = EffectsRackView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Theme.panel.cgColor
        let bar = FillView(Theme.header)
        bar.bottomLine = Theme.gridStrong
        bar.translatesAutoresizingMaskIntoConstraints = false
        tabs.selectedSegment = UserDefaults.standard.object(forKey: "MM8 Bottom Tab") as? Int ?? 1
        tabs.controlSize = .small
        tabs.target = self
        tabs.action = #selector(changed)
        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabs.setToolTip("Show the Song Slicer", forSegment: 0)
        tabs.setToolTip("Show the Effects Rack", forSegment: 1)
        bar.addSubview(tabs)
        addSubview(bar)
        for v in [slicer, rack] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
            NSLayoutConstraint.activate([
                v.topAnchor.constraint(equalTo: bar.bottomAnchor), v.bottomAnchor.constraint(equalTo: bottomAnchor),
                v.leadingAnchor.constraint(equalTo: leadingAnchor), v.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: topAnchor), bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor), bar.heightAnchor.constraint(equalToConstant: 24),
            tabs.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 8), tabs.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        changed()
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc func changed() {
        slicer.isHidden = tabs.selectedSegment != 0
        rack.isHidden = tabs.selectedSegment != 1
        UserDefaults.standard.set(tabs.selectedSegment, forKey: "MM8 Bottom Tab")
        if tabs.selectedSegment == 0 { slicer.reload() } else { rack.reload() }
    }
}
