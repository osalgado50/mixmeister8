import AppKit
import AVFoundation
import CoreAudioKit

extension NSPasteboard.PasteboardType {
    static let mm8Effect = NSPasteboard.PasteboardType("es.mixmeister8.effect")
}

/// Knob del rack (como los del original: aro verde con el valor, nombre y valor con su unidad).
/// Arrastrar arriba/abajo cambia el valor (con ⇧, fino); doble clic vuelve al valor por defecto.
final class KnobView: NSView {
    var value: Double = 0 { didSet { needsDisplay = true } }
    var name = ""
    var defaultValue: Double = 0
    var text: (Double) -> String = { String(format: "%.2f", $0) }
    var onChange: ((Double, Bool) -> Void)?          // (valor, terminado)
    var tracked = false { didSet { needsDisplay = true } }   // es el parámetro de los marcadores
    private var dragStart: (y: CGFloat, v: Double)?

    static let size = NSSize(width: 96, height: 32)
    override var intrinsicContentSize: NSSize { Self.size }
    override var isFlipped: Bool { true }

    override func draw(_ r: NSRect) {
        let c = NSRect(x: 4, y: 5, width: 22, height: 22)
        Theme.background.setFill(); NSBezierPath(ovalIn: c).fill()
        let track = NSBezierPath()
        let center = NSPoint(x: c.midX, y: c.midY)
        track.appendArc(withCenter: center, radius: 9, startAngle: 225, endAngle: -45, clockwise: true)
        Theme.gridStrong.setStroke(); track.lineWidth = 3; track.stroke()
        let arc = NSBezierPath()
        let end = 225 - 270 * CGFloat(max(0, min(1, value)))
        arc.appendArc(withCenter: center, radius: 9, startAngle: 225, endAngle: end, clockwise: true)
        Theme.accent.setStroke(); arc.lineWidth = 3; arc.stroke()
        let a = end * .pi / 180
        let dot = NSBezierPath()
        dot.move(to: center)
        dot.line(to: NSPoint(x: center.x + 6 * cos(a), y: center.y - 6 * sin(a)))
        Theme.text.setStroke(); dot.lineWidth = 1.5; dot.stroke()
        let nameAttrs: [NSAttributedString.Key: Any] = [.font: Theme.font(8.5), .foregroundColor: tracked ? Theme.accent : Theme.textDim]
        (name as NSString).draw(in: NSRect(x: 30, y: 3, width: bounds.width - 30, height: 12), withAttributes: nameAttrs)
        (text(value) as NSString).draw(in: NSRect(x: 30, y: 16, width: bounds.width - 30, height: 13),
                                       withAttributes: [.font: Theme.mono(9.5, .semibold), .foregroundColor: Theme.text])
    }

    override func mouseDown(with e: NSEvent) {
        if e.clickCount == 2 { value = defaultValue; onChange?(value, true); return }
        dragStart = (e.locationInWindow.y, value)
    }
    override func mouseDragged(with e: NSEvent) {
        guard let d = dragStart else { return }
        let k = e.modifierFlags.contains(.shift) ? 0.001 : 0.006
        value = max(0, min(1, d.v + Double(e.locationInWindow.y - d.y) * k))
        onChange?(value, false)
    }
    override func mouseUp(with e: NSEvent) {
        if dragStart != nil { onChange?(value, true) }
        dragStart = nil
    }
    override func scrollWheel(with e: NSEvent) {
        value = max(0, min(1, value + Double(e.scrollingDeltaY) * 0.002))
        onChange?(value, true)
    }
}

/// Un efecto en el rack: barra de título (Enable/Bypass + nombre) y sus knobs en dos filas.
final class RackModule: NSView {
    let effect: PLEffect
    let resolved: FxCatalog.Resolved
    var knobs: [KnobView] = []
    var selected = false { didSet { needsDisplay = true } }
    var onSelect: (() -> Void)?
    var onToggle: (() -> Void)?
    var onDelete: (() -> Void)?
    private let enable = NSButton()
    static let titleHeight: CGFloat = 20
    override var isFlipped: Bool { true }

    init(effect: PLEffect, resolved: FxCatalog.Resolved) {
        self.effect = effect
        self.resolved = resolved
        super.init(frame: .zero)
        enable.setButtonType(.toggle)
        enable.isBordered = false
        enable.title = ""
        enable.wantsLayer = true
        enable.layer?.cornerRadius = 2
        enable.toolTip = "Enable/Bypass this Effect"
        enable.target = self
        enable.action = #selector(toggled)
        enable.frame = NSRect(x: 6, y: 4, width: 12, height: 12)
        addSubview(enable)
        setEnabled(effect.flags & 1 == 0)
        menu = NSMenu()
        menu?.addItem(withTitle: "Delete", action: #selector(deleteMe), keyEquivalent: "").target = self
    }
    required init?(coder: NSCoder) { fatalError() }

    func setEnabled(_ on: Bool) {
        enable.state = on ? .on : .off
        enable.layer?.backgroundColor = (on ? Theme.accent : Theme.gridStrong).cgColor
    }

    /// Parámetros que muestra: los del efecto (propios o del Audio Unit) o, si es un efecto del
    /// original sin equivalente exacto, sus valores guardados tal cual (los 12 primeros).
    var shownParams: [(name: String, def: Double, text: (Double) -> String)] {
        if resolved.native, let t = resolved.type {
            return t.params.prefix(16).map { p in (p.name, p.defNorm, { p.text($0) }) }
        }
        return effect.params.prefix(12).indices.map { i in ("Param \(i + 1)", 0.5, { String(format: "%.0f %%", $0 * 100) }) }
    }

    func layoutKnobs() {
        let ps = shownParams
        let cols = max(1, (ps.count + 1) / 2)
        for (i, p) in ps.enumerated() {
            let k = KnobView()
            k.name = p.name
            k.defaultValue = p.def
            k.text = p.text
            k.value = i < effect.params.count ? effect.params[i] : p.def
            k.frame = NSRect(origin: NSPoint(x: 4 + CGFloat(i % cols) * KnobView.size.width,
                                             y: Self.titleHeight + 4 + CGFloat(i / cols) * (KnobView.size.height + 2)), size: KnobView.size)
            addSubview(k)
            knobs.append(k)
        }
        frame.size = NSSize(width: max(170, 8 + CGFloat(cols) * KnobView.size.width), height: Self.titleHeight + 8 + 2 * (KnobView.size.height + 2))
    }

    var title: String {
        if resolved.native { return effect.name }
        if let t = resolved.type { return "\(effect.name)  →  \(t.name)" }
        return "\(effect.name)  (sin equivalente)"
    }

    override func draw(_ r: NSRect) {
        Theme.panelRaised.setFill(); NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: Theme.radius, yRadius: Theme.radius).fill()
        let bar = NSRect(x: 0, y: 0, width: bounds.width, height: Self.titleHeight)
        (selected ? Theme.accentDeep : Theme.header).setFill(); NSBezierPath(roundedRect: bar, xRadius: Theme.radius, yRadius: Theme.radius).fill()
        (title as NSString).draw(in: NSRect(x: 24, y: 3, width: bounds.width - 28, height: 14),
                                 withAttributes: [.font: Theme.font(10.5, .semibold), .foregroundColor: selected && !Theme.skin.dark ? NSColor.white : Theme.text])
        (selected ? Theme.accent : Theme.gridStrong).setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: Theme.radius, yRadius: Theme.radius).stroke()
    }

    override func mouseDown(with e: NSEvent) {
        onSelect?()
        window?.makeFirstResponder(superview)
    }
    @objc private func toggled() { onToggle?() }
    @objc private func deleteMe() { onDelete?() }
}

/// Effects Rack (panel inferior): a la izquierda, de quién es el rack (Master Output o la pista),
/// el efecto y el parámetro que se sigue con marcadores y los botones; a la derecha, los efectos.
final class EffectsRackView: NSView {
    private let titleLabel = label("Master Output", size: 11, weight: .semibold)
    private let effectPopup = NSPopUpButton()
    private let paramPopup = NSPopUpButton()
    private let content = RackContent()
    private let scroll = NSScrollView()
    private var modules: [RackModule] = []
    private var panels: [UInt32: NSWindow] = [:]
    /// Pista del rack (nil = Master Output).
    private(set) var target: Int?
    private(set) var selectedSlot: UInt32?
    private var lastRecord: [UInt32: Double] = [:]
    private var structure = ""

    override init(frame: NSRect) {
        super.init(frame: frame)
        let left = FillView(Theme.panelRaised)
        left.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.lineBreakMode = .byTruncatingTail
        for p in [effectPopup, paramPopup] {
            p.controlSize = .small
            p.font = Theme.font(10.5)
            p.target = self
        }
        effectPopup.action = #selector(effectChosen)
        paramPopup.action = #selector(paramChosen)
        effectPopup.toolTip = "Effects"
        paramPopup.toolTip = "Effect Parameters"
        let clearParam = ToolButton(symbol: "circle.dotted", tip: "Clear Automation on this parameter", action: #selector(clearParamAutomation), target: self, size: 11)
        let clearAll = ToolButton(symbol: "circle.slash", tip: "Clear Automation for this effect", action: #selector(clearEffectAutomation), target: self, size: 11)
        let panel = ToolButton(symbol: "slider.horizontal.below.rectangle", tip: "Show the Effect Control Panel", action: #selector(showPanel), target: self, size: 11)
        let buttons = NSStackView(views: [clearParam, clearAll, NSView(), panel])
        buttons.spacing = 2
        let col = NSStackView(views: [titleLabel, effectPopup, paramPopup, buttons])
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 5
        col.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 6, right: 8)
        col.translatesAutoresizingMaskIntoConstraints = false
        left.addSubview(col)
        addSubview(left)

        content.rack = self
        scroll.documentView = content
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = false
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            left.topAnchor.constraint(equalTo: topAnchor), left.bottomAnchor.constraint(equalTo: bottomAnchor),
            left.leadingAnchor.constraint(equalTo: leadingAnchor), left.widthAnchor.constraint(equalToConstant: 150),
            col.topAnchor.constraint(equalTo: left.topAnchor), col.leadingAnchor.constraint(equalTo: left.leadingAnchor),
            col.trailingAnchor.constraint(equalTo: left.trailingAnchor),
            effectPopup.widthAnchor.constraint(equalToConstant: 134), paramPopup.widthAnchor.constraint(equalToConstant: 134),
            titleLabel.widthAnchor.constraint(equalToConstant: 134), buttons.widthAnchor.constraint(equalToConstant: 134),
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: left.trailingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        for n: Notification.Name in [.selectionChanged, .playlistChanged, .effectsChanged] {
            NotificationCenter.default.addObserver(self, selector: #selector(reload), name: n, object: nil)
        }
        reload()
    }
    required init?(coder: NSCoder) { fatalError() }

    var effects: [PLEffect] {
        let d = Session.shared.doc
        if let t = target, t < d.tracks.count { return d.tracks[t].effects }
        return d.master_effects
    }

    @objc func reload() {
        let s = Session.shared
        target = s.selectedTrack.flatMap { $0 < s.doc.tracks.count ? $0 : nil }
        if let t = target {
            let tr = s.doc.tracks[t]
            let title = s.libraryItem(for: tr).map { $0.title.isEmpty ? tr.title : $0.title } ?? tr.title
            titleLabel.stringValue = "\(t + 1) - \"\(title)\""
        } else { titleLabel.stringValue = "Master Output" }
        let fx = effects
        if selectedSlot == nil || !fx.contains(where: { $0.slot == selectedSlot }) { selectedSlot = fx.first?.slot }
        // Si solo cambiaron valores, se actualizan los knobs (no se rehace: no corta un arrastre).
        let key = "\(target ?? -1)|" + fx.map { "\($0.slot):\($0.plugin_id):\($0.params.count)" }.joined(separator: ",")
        if key == structure {
            for (m, e) in zip(modules, fx) {
                m.setEnabled(e.flags & 1 == 0)
                for (i, k) in m.knobs.enumerated() where i < e.params.count && abs(k.value - e.params[i]) > 1e-6 { k.value = e.params[i] }
                m.selected = e.slot == selectedSlot
            }
        } else {
            structure = key
            rebuildModules(fx)
        }
        rebuildPopups()
    }

    private func rebuildModules(_ fx: [PLEffect]) {
        for m in modules { m.removeFromSuperview() }
        modules = []
        var x: CGFloat = 8
        for (idx, e) in fx.enumerated() {
            let m = RackModule(effect: e, resolved: FxCatalog.resolve(e))
            m.layoutKnobs()
            m.frame.origin = NSPoint(x: x, y: 6)
            x += m.frame.width + 8
            m.selected = e.slot == selectedSlot
            let slot = e.slot
            m.onSelect = { [weak self] in self?.select(slot) }
            m.onToggle = { [weak self] in self?.toggleEnable(slot) }
            m.onDelete = { [weak self] in self?.deleteEffect(slot) }
            for (i, k) in m.knobs.enumerated() {
                k.onChange = { [weak self] v, done in self?.knobChanged(slot: slot, param: i, value: v, done: done) }
            }
            content.addSubview(m)
            modules.append(m)
            _ = idx
        }
        content.frame = NSRect(x: 0, y: 0, width: max(x, scroll.contentSize.width), height: max(110, scroll.contentSize.height))
        content.needsDisplay = true
        updateTrackedKnob()
    }

    private func rebuildPopups() {
        let fx = effects
        effectPopup.removeAllItems()
        for e in fx { effectPopup.addItem(withTitle: e.name) }
        if let i = fx.firstIndex(where: { $0.slot == selectedSlot }) { effectPopup.selectItem(at: i) }
        effectPopup.isEnabled = !fx.isEmpty
        let prev = paramPopup.indexOfSelectedItem
        paramPopup.removeAllItems()
        if let e = fx.first(where: { $0.slot == selectedSlot }), let m = modules.first(where: { $0.effect.slot == e.slot }) {
            paramPopup.addItem(withTitle: "Enable/Bypass")
            for p in m.shownParams { paramPopup.addItem(withTitle: p.name) }
            let tp = Session.shared.trackedParam
            if let tp, tp.slot == e.slot { paramPopup.selectItem(at: tp.param == 0xFFF ? 0 : tp.param + 1) }
            else if prev >= 0, prev < paramPopup.numberOfItems { paramPopup.selectItem(at: prev) }
        }
        paramPopup.isEnabled = paramPopup.numberOfItems > 0
        syncTracked()
    }

    private func select(_ slot: UInt32) {
        selectedSlot = slot
        for m in modules { m.selected = m.effect.slot == slot }
        rebuildPopups()
    }

    @objc private func effectChosen() {
        let fx = effects
        let i = effectPopup.indexOfSelectedItem
        if i >= 0, i < fx.count { select(fx[i].slot) }
    }
    @objc private func paramChosen() { syncTracked() }

    /// El parámetro elegido es el que se ve (y se graba) con marcadores en la línea de tiempo.
    private func syncTracked() {
        let s = Session.shared
        let new: Session.TrackedParam?
        if let t = target, let slot = selectedSlot, paramPopup.indexOfSelectedItem >= 0 {
            let i = paramPopup.indexOfSelectedItem
            new = Session.TrackedParam(track: t, slot: slot, param: i == 0 ? 0xFFF : i - 1)
        } else { new = nil }
        if s.trackedParam != new { s.trackedParam = new; NotificationCenter.default.post(name: .viewOptionsChanged, object: nil) }
        updateTrackedKnob()
    }
    private func updateTrackedKnob() {
        let tp = Session.shared.trackedParam
        for m in modules { for (i, k) in m.knobs.enumerated() { k.tracked = tp?.slot == m.effect.slot && tp?.param == i } }
    }

    // MARK: Cambios

    private func editEffect(_ name: String, slot: UInt32, coalesce: Bool = false, _ f: @escaping (inout PLEffect) -> Void) {
        let tgt = target
        Session.shared.mutateLight(name, coalesce: coalesce) { d in
            if let t = tgt { if let i = d.tracks[t].effects.firstIndex(where: { $0.slot == slot }) { f(&d.tracks[t].effects[i]) } }
            else if let i = d.master_effects.firstIndex(where: { $0.slot == slot }) { f(&d.master_effects[i]) }
        }
    }

    private func knobChanged(slot: UInt32, param: Int, value: Double, done: Bool) {
        if selectedSlot != slot { select(slot) }
        editEffect("Effect Parameter", slot: slot, coalesce: true) { e in
            while e.params.count <= param { e.params.append(0) }
            e.params[param] = value
        }
        // Grabación: con la mezcla sonando, mover el parámetro que se sigue deja marcadores.
        let s = Session.shared, p = Player.shared
        guard p.isPlaying, let t = target, let tp = s.trackedParam, tp.track == t, tp.slot == slot, tp.param == param,
              let item = s.layout.items.first(where: { $0.index == t }) else { return }
        let now = p.position
        guard now >= item.mixStart, now < item.mixEnd else { return }
        let key = slot << 12 | UInt32(param)
        if let last = lastRecord[key], now - last < 0.1, !done { return }
        lastRecord[key] = now
        let seg = item.segments.first { now >= $0.mixStart && now < $0.mixEnd } ?? item.segments[0]
        let src = seg.source(item, at: now)
        Session.shared.mutateLight("Record Effect Parameter", coalesce: true) { d in
            d.tracks[t].layer.append(.marker(PLMarker(type: MarkerKind.effectParam, pos_us: Int64(src * 1e6), flag: key, value: value)))
        }
    }

    private func toggleEnable(_ slot: UInt32) {
        editEffect("Enable/Bypass", slot: slot) { e in e.flags ^= 1 }
    }

    func deleteSelected() { if let s = selectedSlot { deleteEffect(s) } }
    private func deleteEffect(_ slot: UInt32) {
        let tgt = target
        panels[slot]?.close()
        Session.shared.mutate("Delete Effect") { d in
            if let t = tgt {
                d.tracks[t].effects.removeAll { $0.slot == slot }
                d.tracks[t].layer.removeAll { if case let .marker(m) = $0 { return m.type == MarkerKind.effectParam && m.flag >> 12 == slot }; return false }
            } else { d.master_effects.removeAll { $0.slot == slot } }
        }
    }

    @objc private func clearParamAutomation() {
        guard let t = target, let tp = Session.shared.trackedParam, tp.track == t else { return }
        let key = tp.slot << 12 | UInt32(tp.param)
        Session.shared.mutateLight("Clear Automation") { d in
            d.tracks[t].layer.removeAll { if case let .marker(m) = $0 { return m.type == MarkerKind.effectParam && m.flag == key }; return false }
        }
    }
    @objc private func clearEffectAutomation() {
        guard let t = target, let slot = selectedSlot else { return }
        Session.shared.mutateLight("Clear Automation") { d in
            d.tracks[t].layer.removeAll { if case let .marker(m) = $0 { return m.type == MarkerKind.effectParam && m.flag >> 12 == slot }; return false }
        }
    }

    // MARK: Panel de control del efecto (la interfaz del Audio Unit)

    @objc private func showPanel() {
        guard let slot = selectedSlot, let e = effects.first(where: { $0.slot == slot }) else { return }
        if let w = panels[slot] { w.makeKeyAndOrderFront(nil); return }
        let r = FxCatalog.resolve(e)
        guard let t = r.type else { NSSound.beep(); return }
        let node = FxPool.shared.existing(slot) ?? FxPool.shared.node(for: e, type: t)
        guard let node else { NSSound.beep(); return }
        FxHost.apply(e, r, to: node)
        let tgt = target
        let open: (NSViewController) -> Void = { [weak self] vc in
            guard let self else { return }
            let w = NSPanel(contentRect: NSRect(origin: .zero, size: vc.preferredContentSize.width > 10 ? vc.preferredContentSize : NSSize(width: 480, height: 300)),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
            w.title = e.name
            w.contentViewController = vc
            w.isReleasedWhenClosed = false
            w.center()
            self.panels[slot] = w
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
                self?.panels[slot] = nil
                guard r.native else { return }
                // Lo tocado en el panel pasa a la lista.
                let vals = t.params.map { FxHost.read(t, $0, from: node) }
                Session.shared.mutateLight("Effect Control Panel") { d in
                    func upd(_ x: inout PLEffect) { for (i, v) in vals.enumerated() { if let v { while x.params.count <= i { x.params.append(0) }; x.params[i] = v } } }
                    if let tt = tgt { if let i = d.tracks[tt].effects.firstIndex(where: { $0.slot == slot }) { upd(&d.tracks[tt].effects[i]) } }
                    else if let i = d.master_effects.firstIndex(where: { $0.slot == slot }) { upd(&d.master_effects[i]) }
                }
            }
            w.makeKeyAndOrderFront(nil)
        }
        node.auAudioUnit.requestViewController { vc in
            DispatchQueue.main.async {
                if let vc { open(vc) } else {
                    let g = AUGenericViewController()
                    g.auAudioUnit = node.auAudioUnit
                    g.preferredContentSize = NSSize(width: 480, height: 320)
                    open(g)
                }
            }
        }
    }
}

/// Fondo del rack: recibe efectos arrastrados desde la lista y la tecla Supr.
final class RackContent: NSView {
    weak var rack: EffectsRackView?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.mm8Effect])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ r: NSRect) {
        Theme.panel.setFill(); r.fill()
        if subviews.isEmpty {
            ("Arrastra un efecto aquí o a una pista (View › Effects)" as NSString).draw(at: NSPoint(x: 14, y: 14),
                                                                                    withAttributes: [.font: Theme.font(11), .foregroundColor: Theme.textDim])
        }
    }
    override func mouseDown(with e: NSEvent) { window?.makeFirstResponder(self) }
    override func keyDown(with e: NSEvent) {
        if e.keyCode == 51 || e.keyCode == 117 { rack?.deleteSelected() } else { super.keyDown(with: e) }
    }
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        guard let name = s.draggingPasteboard.string(forType: .mm8Effect) else { return false }
        return EffectsActions.add(named: name, toTrack: rack?.target)
    }
}

enum EffectsActions {
    /// Añade un efecto a una pista (o al master si `toTrack` es nil) y enseña el rack.
    @discardableResult
    /// `range`: tramo de la mezcla (segundos) si el efecto se suelta sobre una parte resaltada de la pista.
    /// Como MixMeister 7.8: el efecto se añade desactivado (flags bit 0) y cuatro Effects Parameter
    /// Markers de Enable/Bypass lo encienden solo en el tramo — 0 y 1 al principio, 1 y 0 al final
    /// (comprobado en el original, experimento exp-tramo.mmp).
    static func add(named listName: String, toTrack t: Int?, range: (Double, Double)? = nil) -> Bool {
        guard let type = FxCatalog.all.first(where: { $0.listName == listName }) else { return false }
        let s = Session.shared
        var e = FxCatalog.newEffect(type, doc: s.doc)
        var marks: [PLMarker] = []
        if let t, let (a, b) = range, b > a, let item = s.layout.items.first(where: { $0.index == t }), !item.segments.isEmpty {
            func src(_ m: Double) -> Int64 {
                let seg = item.segments.first { m >= $0.mixStart && m <= $0.mixEnd } ?? item.segments[0]
                return Int64((seg.source(item, at: m) * 1e6).rounded())
            }
            let flag = UInt32(e.slot) << 12 | 0xFFF
            let pa = src(max(a, item.mixStart)), pb = src(min(b, item.mixEnd))
            marks = [(pa, 0.0), (pa, 1.0), (pb, 1.0), (pb, 0.0)].map { PLMarker(type: MarkerKind.effectParam, pos_us: $0.0, flag: flag, value: $0.1) }
            e.flags |= 1
        }
        s.mutate(marks.isEmpty ? "Add Effect" : "Add Effect to Selection") { d in
            if let t, t < d.tracks.count { d.tracks[t].effects.append(e); d.tracks[t].layer.append(contentsOf: marks.map { .marker($0) }) } else { d.master_effects.append(e) }
        }
        s.selectedTrack = t
        (NSApp.delegate as? AppDelegate)?.viewEffectsRack(nil)
        NotificationCenter.default.post(name: .effectsChanged, object: nil)
        return true
    }
}

/// Lista de efectos disponibles (pestaña Effects de la biblioteca): «Nombre - Fabricante», como el
/// original. Se arrastran a una pista, al fondo de la línea de tiempo (master) o al rack.
final class EffectsListView: NSScrollView, NSTableViewDataSource, NSTableViewDelegate {
    let table = NSTableView()
    private let types = FxCatalog.all

    override init(frame: NSRect) {
        super.init(frame: frame)
        let c = NSTableColumn(identifier: .init("Effect"))
        c.title = "Effect"
        c.headerCell.font = Theme.font(10, .semibold)
        c.width = 400
        table.addTableColumn(c)
        table.style = .plain
        table.backgroundColor = Theme.panel
        table.rowHeight = 19
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(doubleClicked)
        table.setDraggingSourceOperationMask(.copy, forLocal: true)
        documentView = table
        hasVerticalScroller = true
        drawsBackground = true
        backgroundColor = Theme.panel
    }
    required init?(coder: NSCoder) { fatalError() }

    func numberOfRows(in tableView: NSTableView) -> Int { types.count }
    func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        let f = (tv.makeView(withIdentifier: .init("fx"), owner: nil) as? NSTextField) ?? {
            let l = label("", size: 11.5)
            l.identifier = .init("fx")
            return l
        }()
        f.stringValue = types[row].listName
        f.textColor = types[row].isInstalled ? Theme.textDim : Theme.text
        return f
    }
    func tableView(_ tv: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let p = NSPasteboardItem()
        p.setString(types[row].listName, forType: .mm8Effect)
        return p
    }
    /// Doble clic: a la pista seleccionada (o al master).
    @objc private func doubleClicked() {
        let r = table.clickedRow
        guard r >= 0, r < types.count else { return }
        EffectsActions.add(named: types[r].listName, toTrack: Session.shared.selectedTrack)
    }
}
