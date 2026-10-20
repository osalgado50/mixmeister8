import AppKit

/// Descripción de un menú tal como sale del nib de MixMeister (ver Generated/MenuSpec.swift).
struct MenuSpec {
    enum Mod { case cmd, shift, opt, ctrl }
    indirect enum Entry {
        case separator
        case item(String, action: String? = nil, key: String = "", mods: [Mod] = [], tag: Int = 0, submenu: MenuSpec? = nil)
    }
    let title: String
    let entries: [Entry]
    init(_ title: String, _ entries: [Entry]) { self.title = title; self.entries = entries }

    /// Construye el NSMenu. Las acciones van por la cadena de respuesta (target nil): un ítem cuya
    /// acción aún no implementa nadie sale desactivado, como en cualquier app de Mac.
    func build(target: AnyObject? = nil) -> NSMenu {
        let menu = NSMenu(title: title)
        for e in entries {
            switch e {
            case .separator:
                menu.addItem(.separator())
            case let .item(title, action, key, mods, tag, submenu):
                let it = NSMenuItem(title: title, action: action.map { NSSelectorFromString($0) }, keyEquivalent: key)
                var mask: NSEvent.ModifierFlags = []
                for m in mods {
                    switch m {
                    case .cmd: mask.insert(.command)
                    case .shift: mask.insert(.shift)
                    case .opt: mask.insert(.option)
                    case .ctrl: mask.insert(.control)
                    }
                }
                it.keyEquivalentModifierMask = key.isEmpty ? [] : mask
                it.tag = tag
                it.target = target
                if let s = submenu { it.submenu = s.build(target: target) }
                menu.addItem(it)
            }
        }
        return menu
    }
}

enum MenuTags {
    // Tools → acciones que el nib despacha por handleMenuItem: con estas etiquetas.
    static let addToCategory = 2001, removeFromCategory = 2002, findSimilar = 2003
    static let volume = 2101, treble = 2102, mid = 2103, bass = 2104, label = 2105, effectParam = 2106
    static let loopStart = 2107, loopEnd = 2108, split = 2109, reverse = 2110
    static let nextPerformance = 2201, tweaks = 2202, quickSaveTweak = 2203, editTag = 2204, trackSettings = 2205
}
