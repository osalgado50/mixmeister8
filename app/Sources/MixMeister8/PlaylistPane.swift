import AppKit

/// Las 13 transiciones de MixMeister, con sus nombres exactos (las listas las guardan por nombre).
enum Transitions {
    static let names = ["No Transition", "Simple Full", "Simple Cut", "Simple Crossfade", "Beatmix Full", "Beatmix Cut",
                        "Beatmix 8", "Beatmix 16", "Beatmix 32", "Beatmix 64", "Beatmix Ping Pong", "Beatmix Bass Swap", "Pause"]
    static let `default` = "Beatmix 8"
}

/// Panel de la lista (arriba a la derecha): transporte, tabla con TRANSITION editable por fila.
final class PlaylistPane: NSView, NSTableViewDataSource, NSTableViewDelegate, NSMenuItemValidation {
    let table = NSTableView()
    private let scroll = NSScrollView()
    private var visible: [(key: String, width: CGFloat)] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Theme.panel.cgColor
        let bar = FillView(Theme.header)
        bar.bottomLine = Theme.gridStrong
        bar.translatesAutoresizingMaskIntoConstraints = false
        let buttons: [NSView] = [
            ToolButton(symbol: "play.fill", tip: "Play/Pause", action: NSSelectorFromString("playPause:"), size: 14),
            ToolButton(symbol: "stop.fill", tip: "Stop", action: NSSelectorFromString("stop:"), size: 13),
            ToolButton(symbol: "backward.end.fill", tip: "Previous Track", action: NSSelectorFromString("previousTrack:")),
            ToolButton(symbol: "forward.end.fill", tip: "Next Track", action: NSSelectorFromString("nextTrack:")),
            ToolButton(symbol: "arrow.triangle.merge", tip: "Mix Now (F6)", action: NSSelectorFromString("mixNow:")),
        ]
        let stack = NSStackView(views: buttons + [NSView()])
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        addSubview(bar)

        table.style = .plain
        table.backgroundColor = Theme.panel
        table.rowHeight = 20
        table.intercellSpacing = NSSize(width: 6, height: 1)
        table.allowsMultipleSelection = true
        table.dataSource = self
        table.delegate = self
        table.menu = MenuSpecs.playlist.build()
        table.registerForDraggedTypes([.mm8LibraryItem, .mm8PlaylistRow, .fileURL])
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.backgroundColor = Theme.panel
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: topAnchor), bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor), bar.heightAnchor.constraint(equalToConstant: 32),
            stack.topAnchor.constraint(equalTo: bar.topAnchor), stack.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor), stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor), scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        visible = Columns.layout(prefix: "Playlist", keys: Columns.playlistKeys, defaults: ["Index", "Title", "Artist", "Bpm", "Transition", "Key"])
        rebuildColumns()
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .playlistChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(syncSelection), name: .selectionChanged, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func rebuildColumns() {
        for c in table.tableColumns { table.removeTableColumn(c) }
        for (k, w) in visible {
            guard let d = Columns.def(k) else { continue }
            let c = NSTableColumn(identifier: .init(k))
            c.title = d.title
            c.width = w
            c.headerCell.font = Theme.font(10, .semibold)
            table.addTableColumn(c)
        }
        table.headerView?.menu = MenuSpecs.playlistColumns.build(target: self)
    }

    @objc func reload() { table.reloadData(); syncSelection() }
    @objc private func syncSelection() {
        if let i = Session.shared.selectedTrack, i < table.numberOfRows { table.selectRowIndexes([i], byExtendingSelection: false); table.scrollRowToVisible(i) }
    }
    func tableViewSelectionDidChange(_ n: Notification) {
        Session.shared.selectedTrack = table.selectedRow >= 0 ? table.selectedRow : nil
    }

    // MARK: Columnas

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if let a = item.action, let d = Columns.byToggle(NSStringFromSelector(a)) {
            item.state = visible.contains { $0.key == d.key } ? .on : .off
            return Columns.playlistKeys.contains(d.key)
        }
        return responds(to: item.action)
    }
    private func toggle(_ sel: String) {
        guard let d = Columns.byToggle(sel), Columns.playlistKeys.contains(d.key) else { return }
        if let i = visible.firstIndex(where: { $0.key == d.key }) { if visible.count > 1 { visible.remove(at: i) } }
        else { visible.append((d.key, d.width)) }
        rebuildColumns()
        table.reloadData()
        Columns.save(prefix: "Playlist", keys: Columns.playlistKeys, visible: visible)
    }
    func tableViewColumnDidResize(_ n: Notification) {
        visible = table.tableColumns.map { ($0.identifier.rawValue, $0.width) }
        Columns.save(prefix: "Playlist", keys: Columns.playlistKeys, visible: visible)
    }
    @objc func toggleIndex(_ s: Any?) { toggle("toggleIndex:") }
    @objc func toggleTitle(_ s: Any?) { toggle("toggleTitle:") }
    @objc func toggleArtist(_ s: Any?) { toggle("toggleArtist:") }
    @objc func toggleBpm(_ s: Any?) { toggle("toggleBpm:") }
    @objc func toggleKey(_ s: Any?) { toggle("toggleKey:") }
    @objc func toggleKeyCode(_ s: Any?) { toggle("toggleKeyCode:") }
    @objc func toggleTransition(_ s: Any?) { toggle("toggleTransition:") }
    @objc func toggleAlbum(_ s: Any?) { toggle("toggleAlbum:") }
    @objc func toggleTime(_ s: Any?) { toggle("toggleTime:") }
    @objc func toggleYear(_ s: Any?) { toggle("toggleYear:") }
    @objc func toggleGenre(_ s: Any?) { toggle("toggleGenre:") }
    @objc func toggleComposer(_ s: Any?) { toggle("toggleComposer:") }
    @objc func toggleFileName(_ s: Any?) { toggle("toggleFileName:") }
    @objc func toggleDateAdded(_ s: Any?) { toggle("toggleDateAdded:") }
    @objc func toggleRating(_ s: Any?) { toggle("toggleRating:") }
    @objc func toggleComments(_ s: Any?) { toggle("toggleComments:") }
    @objc func toggleTrack(_ s: Any?) { toggle("toggleTrack:") }
    @objc func toggleBitRate(_ s: Any?) { toggle("toggleBitRate:") }
    @objc func toggleLabel(_ s: Any?) { toggle("toggleLabel:") }
    @objc func toggleUser1(_ s: Any?) { toggle("toggleUser1:") }
    @objc func toggleUser2(_ s: Any?) { toggle("toggleUser2:") }

    // MARK: Tabla

    func numberOfRows(in tv: NSTableView) -> Int { Session.shared.doc.tracks.count }

    func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        guard let col else { return nil }
        let s = Session.shared
        let t = s.doc.tracks[row]
        let key = col.identifier.rawValue
        if key == "Transition" {
            let p = NSPopUpButton(frame: .zero, pullsDown: false)
            p.controlSize = .mini
            p.font = Theme.font(10.5, .medium)
            p.isBordered = false
            p.wantsLayer = true
            p.layer?.backgroundColor = (t.overlay ? Theme.overlay : Theme.accentDeep).cgColor
            p.layer?.cornerRadius = 3
            let current = t.transition_out ?? (row == s.doc.tracks.count - 1 ? "" : Transitions.default)
            var names = Transitions.names
            if !current.isEmpty, !names.contains(current) { names.append(current) }   // «Beatmix Custom»…
            p.addItems(withTitles: names)
            if current.isEmpty { p.selectItem(at: -1); p.isEnabled = row < s.doc.tracks.count - 1 } else { p.selectItem(withTitle: current) }
            p.tag = row
            p.target = self
            p.action = #selector(transitionChosen(_:))
            if t.overlay { p.isEnabled = false }
            return p
        }
        let id = NSUserInterfaceItemIdentifier("cell")
        let f = (tv.makeView(withIdentifier: id, owner: nil) as? NSTextField) ?? { let x = label("", size: 11.5); x.identifier = id; return x }()
        let lib = s.libraryItem(for: t)
        let found = s.audioPath(row) != nil
        switch key {
        case "Index": f.stringValue = "\(row + 1)"
        case "Title": f.stringValue = (lib?.title.isEmpty == false ? lib!.title : t.title)
        case "Bpm":
            let tempo = s.layout.items.first { $0.index == row }?.tempo ?? t.bpm
            f.stringValue = String(format: "%.1f", tempo)
        case "Key":
            if let k = lib?.keyNote {
                let shifted = ((k + Int(t.key_semitones.rounded())) % 12 + 12) % 12
                var l = lib!; l.keyNote = shifted
                f.stringValue = l.keyText
            } else { f.stringValue = "" }
        case "FileName": f.stringValue = t.path
        default: f.stringValue = lib.map { LibraryPane.value($0, key) } ?? ""
        }
        f.alignment = Columns.def(key)?.numeric == true ? .right : .left
        f.font = Columns.def(key)?.numeric == true ? Theme.mono(11.5) : Theme.font(11.5)
        f.textColor = found ? (t.overlay ? Theme.volume : Theme.text) : Theme.bass   // en rojo: audio no encontrado
        f.toolTip = found ? s.audioPath(row) : "No se encuentra el audio: \(t.path)"
        return f
    }

    @objc private func transitionChosen(_ p: NSPopUpButton) {
        guard let name = p.titleOfSelectedItem else { return }
        (NSApp.delegate as? AppDelegate)?.setTransition(row: p.tag, name: name)
    }
}
