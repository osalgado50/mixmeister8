import AppKit

/// Panel de la biblioteca (arriba a la izquierda): pestañas Library / Effects, añadir, categoría,
/// búsqueda y la tabla con las columnas y anchuras de MixMeister.
final class LibraryPane: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSMenuItemValidation {
    let table = NSTableView()
    private let scroll = NSScrollView()
    private let search = NSSearchField()
    private let category = NSPopUpButton()
    private let tabs = NSSegmentedControl(labels: ["Library", "Effects"], trackingMode: .selectOne, target: nil, action: nil)
    private let effectsList = EffectsListView()
    private var libraryControls: [NSView] = []
    private var rows: [LibraryItem] = []
    private var visible: [(key: String, width: CGFloat)] = []
    private let empty = label("La biblioteca de MixMeister aparecerá aquí.", size: 12, color: Theme.textDim)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Theme.panel.cgColor

        let bar = FillView(Theme.header)
        bar.bottomLine = Theme.gridStrong
        bar.translatesAutoresizingMaskIntoConstraints = false
        tabs.selectedSegment = 0
        tabs.segmentStyle = .rounded
        tabs.controlSize = .small
        tabs.target = self
        tabs.action = #selector(tabChanged)
        tabs.setToolTip("Show the Library", forSegment: 0)
        tabs.setToolTip("Show available Effects", forSegment: 1)
        let add = ToolButton(symbol: "plus.circle", tip: "Add Files To Library", action: NSSelectorFromString("addFilesToLibrary:"))
        category.controlSize = .small
        category.font = Theme.font(11)
        category.target = self
        category.action = #selector(filter)
        search.placeholderString = "SEARCH LIBRARY"
        search.controlSize = .small
        search.font = Theme.font(11)
        search.delegate = self
        search.sendsSearchStringImmediately = true
        let stack = NSStackView(views: [tabs, add, NSView(), category, search])
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        addSubview(bar)

        table.style = .plain
        table.backgroundColor = Theme.panel
        table.gridStyleMask = []
        table.rowHeight = 19
        table.intercellSpacing = NSSize(width: 6, height: 0)
        table.usesAlternatingRowBackgroundColors = false
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = true
        table.allowsColumnResizing = true
        table.dataSource = self
        table.delegate = self
        table.doubleAction = NSSelectorFromString("addToEndOfPlaylist:")
        table.menu = MenuSpecs.library.build()
        table.setDraggingSourceOperationMask(.copy, forLocal: true)
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = Theme.panel
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        empty.translatesAutoresizingMaskIntoConstraints = false
        addSubview(empty)
        effectsList.translatesAutoresizingMaskIntoConstraints = false
        effectsList.isHidden = true
        addSubview(effectsList)
        libraryControls = [add, category, search]

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: topAnchor), bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor), bar.heightAnchor.constraint(equalToConstant: 32),
            stack.topAnchor.constraint(equalTo: bar.topAnchor), stack.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor), stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            search.widthAnchor.constraint(equalToConstant: 170), category.widthAnchor.constraint(equalToConstant: 150),
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor), scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor), empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            effectsList.topAnchor.constraint(equalTo: bar.bottomAnchor), effectsList.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectsList.trailingAnchor.constraint(equalTo: trailingAnchor), effectsList.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        visible = Columns.layout(prefix: "Catalog", keys: Columns.libraryKeys, defaults: ["Title", "Artist", "Bpm", "Album", "Time", "Key", "KeyCode"])
        rebuildColumns()
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .libraryChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(referenceChanged), name: .selectionChanged, object: nil)
        reload()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func rebuildColumns() {
        for c in table.tableColumns { table.removeTableColumn(c) }
        for (k, w) in visible {
            guard let d = Columns.def(k) else { continue }
            let c = NSTableColumn(identifier: .init(k))
            c.title = d.title
            c.width = w
            c.minWidth = 24
            c.headerCell.font = Theme.font(10, .semibold)
            c.sortDescriptorPrototype = NSSortDescriptor(key: k, ascending: true)
            table.addTableColumn(c)
        }
        table.headerView?.menu = MenuSpecs.libraryColumns.build(target: self)
    }

    @objc func reload() {
        let cat = Session.shared.catalog
        let current = category.titleOfSelectedItem
        category.removeAllItems()
        category.addItem(withTitle: "(Entire Library)")
        category.addItems(withTitles: cat.categories)
        if let current, category.itemTitles.contains(current) { category.selectItem(withTitle: current) }
        filter()
    }

    @objc private func filter() {
        let q = search.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        let cat = category.indexOfSelectedItem > 0 ? category.titleOfSelectedItem : nil
        rows = Session.shared.catalog.items.filter { it in
            (cat == nil || it.categories.contains(cat!)) &&
                (q.isEmpty || [it.title, it.artist, it.album, it.genre, it.path].contains { $0.lowercased().contains(q) })
        }
        applySort()
        table.reloadData()
        empty.isHidden = !Session.shared.catalog.items.isEmpty
    }

    func controlTextDidChange(_ obj: Notification) { filter() }
    @objc func searchTextDidChange(_ sender: Any?) { filter() }
    @objc private func tabChanged() { showTab(tabs.selectedSegment) }
    /// 0 = Library, 1 = Effects (View › Library / View › Effects).
    func showTab(_ i: Int) {
        tabs.selectedSegment = i
        effectsList.isHidden = i != 1
        scroll.isHidden = i == 1
        empty.isHidden = i == 1 || !Session.shared.catalog.items.isEmpty
        for v in libraryControls { v.isHidden = i == 1 }
    }
    var showingEffects: Bool { tabs.selectedSegment == 1 }

    // MARK: Compatibles con la pista seleccionada (nuevo en MixMeister 8)

    /// Con una pista seleccionada en la lista, la biblioteca marca las que mezclan bien con ella:
    /// tonalidad compatible (mismo KEYCODE, ±1 en el círculo o su relativa mayor/menor) y BPM a
    /// menos de un 6 % (o del doble/mitad).
    private var reference: LibraryItem?
    @objc private func referenceChanged() {
        let s = Session.shared
        reference = s.selectedTrack.flatMap { $0 < s.doc.tracks.count ? s.libraryItem(for: s.doc.tracks[$0]) : nil }
        table.enumerateAvailableRowViews { rv, row in self.tint(rv, row) }
        table.reloadData()
    }
    static func keyCompatible(_ a: LibraryItem, _ b: LibraryItem) -> Bool {
        guard let n = a.keyCodeNumber, let m = b.keyCodeNumber else { return false }
        if a.minor != b.minor { return n == m }
        let d = abs(n - m)
        return d == 0 || d == 1 || d == 11
    }
    static func bpmCompatible(_ a: LibraryItem, _ b: LibraryItem) -> Bool {
        guard a.bpm > 0, b.bpm > 0 else { return false }
        return [1.0, 2.0, 0.5].contains { abs(a.bpm * $0 - b.bpm) / b.bpm < 0.06 }
    }
    private func tint(_ rv: NSTableRowView, _ row: Int) {
        guard let ref = reference, row < rows.count, rows[row].path != ref.path else { rv.backgroundColor = .clear; return }
        let it = rows[row]
        let k = Self.keyCompatible(it, ref), b = Self.bpmCompatible(it, ref)
        rv.backgroundColor = k && b ? Theme.accent.withAlphaComponent(0.16) : .clear
    }
    func tableView(_ tv: NSTableView, didAdd rv: NSTableRowView, forRow row: Int) { tint(rv, row) }

    var selectedItems: [LibraryItem] { table.selectedRowIndexes.compactMap { $0 < rows.count ? rows[$0] : nil } }

    // MARK: Columnas (Library › Columns)

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if let a = item.action, let d = Columns.byToggle(NSStringFromSelector(a)) {
            item.state = visible.contains { $0.key == d.key } ? .on : .off
            return Columns.libraryKeys.contains(d.key)
        }
        return responds(to: item.action)
    }

    private func toggle(_ sel: String) {
        guard let d = Columns.byToggle(sel), Columns.libraryKeys.contains(d.key) else { return }
        if let i = visible.firstIndex(where: { $0.key == d.key }) { if visible.count > 1 { visible.remove(at: i) } }
        else { visible.append((d.key, d.width)) }
        rebuildColumns()
        table.reloadData()
        saveColumns()
    }
    private func saveColumns() {
        visible = table.tableColumns.map { ($0.identifier.rawValue, $0.width) }
        Columns.save(prefix: "Catalog", keys: Columns.libraryKeys, visible: visible)
    }
    func tableViewColumnDidResize(_ notification: Notification) { saveColumns() }
    func tableViewColumnDidMove(_ notification: Notification) { saveColumns() }

    @objc func toggleTitle(_ s: Any?) { toggle("toggleTitle:") }
    @objc func toggleArtist(_ s: Any?) { toggle("toggleArtist:") }
    @objc func toggleBpm(_ s: Any?) { toggle("toggleBpm:") }
    @objc func toggleAlbum(_ s: Any?) { toggle("toggleAlbum:") }
    @objc func toggleTime(_ s: Any?) { toggle("toggleTime:") }
    @objc func toggleKey(_ s: Any?) { toggle("toggleKey:") }
    @objc func toggleKeyCode(_ s: Any?) { toggle("toggleKeyCode:") }
    @objc func toggleTweaked(_ s: Any?) { toggle("toggleTweaked:") }
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
    @objc func togglePlaylist(_ s: Any?) { toggle("togglePlaylist:") }

    // MARK: Tabla

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    static func value(_ it: LibraryItem, _ key: String) -> String {
        switch key {
        case "Title": return it.title.isEmpty ? (it.path as NSString).lastPathComponent : it.title
        case "Artist": return it.artist
        case "Bpm": return it.bpm > 0 ? String(format: "%.1f", it.bpm) : ""
        case "Album": return it.album
        case "Time": return it.timeText
        case "Key": return it.keyText
        case "KeyCode": return it.keyCode
        case "Tweaked": return it.tweaked ? "✓" : ""
        case "Year": return it.year
        case "Genre": return it.genre
        case "Composer": return it.composer
        case "FileName": return it.path
        case "DateAdded": return it.dateAdded.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .none) } ?? ""
        case "Rating": return String(repeating: "★", count: max(0, min(5, it.rating)))
        case "Comments": return it.comments
        case "Track": return it.trackNumber > 0 ? "\(it.trackNumber)" : ""
        case "BitRate": return it.bitrate > 0 ? "\(it.bitrate / 1000)" : ""
        case "Label": return it.label
        case "User1": return it.user1
        case "User2": return it.user2
        default: return ""
        }
    }

    func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        guard let col else { return nil }
        let key = col.identifier.rawValue
        let id = NSUserInterfaceItemIdentifier("cell")
        let t = (tv.makeView(withIdentifier: id, owner: nil) as? NSTextField) ?? {
            let f = label("", size: 11.5)
            f.identifier = id
            return f
        }()
        let it = rows[row]
        t.stringValue = Self.value(it, key)
        t.alignment = Columns.def(key)?.numeric == true ? .right : .left
        t.font = key == "KeyCode" ? Theme.font(13, .semibold) : (Columns.def(key)?.numeric == true ? Theme.mono(11.5) : Theme.font(11.5))
        t.textColor = key == "KeyCode" ? KeyColors.color(it.keyCodeNumber) : Theme.text
        if let ref = reference, ref.path != it.path {
            if (key == "Key" || key == "KeyCode"), Self.keyCompatible(it, ref) { t.font = Theme.font(key == "KeyCode" ? 13 : 11.5, .heavy) }
            if key == "Bpm", Self.bpmCompatible(it, ref) { t.textColor = Theme.accent }
        }
        return t
    }

    func tableView(_ tv: NSTableView, sortDescriptorsDidChange old: [NSSortDescriptor]) { applySort(); tv.reloadData() }

    private func applySort() {
        guard let sd = table.sortDescriptors.first, let key = sd.key else { return }
        rows.sort { a, b in
            let r: Bool
            switch key {
            case "Bpm": r = a.bpm < b.bpm
            case "Time": r = a.seconds < b.seconds
            case "KeyCode": r = (a.keyCodeNumber ?? 99) < (b.keyCodeNumber ?? 99)
            case "Rating": r = a.rating < b.rating
            case "BitRate": r = a.bitrate < b.bitrate
            case "Track": r = a.trackNumber < b.trackNumber
            case "DateAdded": r = (a.dateAdded ?? .distantPast) < (b.dateAdded ?? .distantPast)
            default: r = Self.value(a, key).localizedCaseInsensitiveCompare(Self.value(b, key)) == .orderedAscending
            }
            return sd.ascending ? r : !r
        }
    }

    func tableView(_ tv: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let p = NSPasteboardItem()
        p.setString(rows[row].path, forType: .string)
        p.setString(rows[row].path, forType: .mm8LibraryItem)
        return p
    }
}

extension NSPasteboard.PasteboardType {
    static let mm8LibraryItem = NSPasteboard.PasteboardType("es.mixmeister8.library-item")
    static let mm8PlaylistRow = NSPasteboard.PasteboardType("es.mixmeister8.playlist-row")
}

/// Colores de KEYCODE: una rueda de 12 tonos, como los círculos de color del original.
enum KeyColors {
    static func color(_ n: Int?) -> NSColor {
        guard let n else { return Theme.textDim }
        let h = (CGFloat((n - 1) % 12) / 12.0 + 0.18).truncatingRemainder(dividingBy: 1)
        return NSColor(hue: h, saturation: 0.62, brightness: 0.95, alpha: 1)
    }
}
