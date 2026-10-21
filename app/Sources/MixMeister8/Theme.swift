import AppKit

/// Aspectos (skins) de MixMeister 8: la distribución del original con seis acabados a elegir en
/// View › Skin. Los colores de los marcadores son los del original (manual de Fusion, tabla 1) en
/// todos, para que una lista se lea igual con cualquier aspecto.
struct Skin {
    let name: String
    let dark: Bool
    let background, panel, panelRaised, header: NSColor
    let grid, gridStrong, text, textDim: NSColor
    let accent, accentDeep: NSColor
    let clip, clipSelected, wave, overlay, playhead: NSColor
    var radius: CGFloat = 4

    static func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
    }

    static let all: [Skin] = [
        // 1. Grafito: grafito oscuro con el verde lima del original (el de hasta ahora).
        Skin(name: "Grafito", dark: true,
             background: rgb(0x131416), panel: rgb(0x1B1C1F), panelRaised: rgb(0x25262A), header: rgb(0x202125),
             grid: NSColor(white: 1, alpha: 0.06), gridStrong: NSColor(white: 1, alpha: 0.13),
             text: NSColor(white: 0.92, alpha: 1), textDim: NSColor(white: 0.56, alpha: 1),
             accent: rgb(0x9EDB3D), accentDeep: rgb(0x598C1A),
             clip: rgb(0x333740), clipSelected: rgb(0x455733), wave: NSColor(white: 0.78, alpha: 0.85), overlay: rgb(0x2E3D52), playhead: rgb(0xFF4D40)),
        // 2. Clásico: los grises metálicos y el verde de MixMeister 7, más claros y con contraste alto.
        Skin(name: "Clásico", dark: true,
             background: rgb(0x0A0A0A), panel: rgb(0x2B2C2B), panelRaised: rgb(0x3A3B3A), header: rgb(0x4A4B4A),
             grid: NSColor(white: 1, alpha: 0.07), gridStrong: NSColor(white: 1, alpha: 0.18),
             text: NSColor(white: 0.95, alpha: 1), textDim: NSColor(white: 0.66, alpha: 1),
             accent: rgb(0x8BD12B), accentDeep: rgb(0x4F7D14),
             clip: rgb(0xB9BCBF), clipSelected: rgb(0xB8E07A), wave: rgb(0x4A4E52, 0.9), overlay: rgb(0x8FA9C4), playhead: rgb(0xFFFFFF), radius: 2),
        // 3. Medianoche: azul marino profundo con acento cian (cabina de noche).
        Skin(name: "Medianoche", dark: true,
             background: rgb(0x0B1020), panel: rgb(0x111830), panelRaised: rgb(0x18213F), header: rgb(0x151D38),
             grid: rgb(0x7FA6FF, 0.07), gridStrong: rgb(0x7FA6FF, 0.16),
             text: rgb(0xE3EAFF), textDim: rgb(0x7D8AB3),
             accent: rgb(0x3FD4F5), accentDeep: rgb(0x1B6E8A),
             clip: rgb(0x1E2A4E), clipSelected: rgb(0x16465A), wave: rgb(0xA9C4FF, 0.85), overlay: rgb(0x34295C), playhead: rgb(0xFF5C7A), radius: 6),
        // 4. Ámbar: negro cálido y naranja ámbar, como una mesa analógica.
        Skin(name: "Ámbar", dark: true,
             background: rgb(0x14110D), panel: rgb(0x1E1A15), panelRaised: rgb(0x2A241C), header: rgb(0x262019),
             grid: rgb(0xFFC27A, 0.06), gridStrong: rgb(0xFFC27A, 0.14),
             text: rgb(0xF3E6D2), textDim: rgb(0x9C8B74),
             accent: rgb(0xFFA62B), accentDeep: rgb(0x9A5A0C),
             clip: rgb(0x3A3027), clipSelected: rgb(0x5A3E1C), wave: rgb(0xE8D3B4, 0.85), overlay: rgb(0x3B3A2A), playhead: rgb(0xFF5A36), radius: 3),
        // 5. Neón: negro puro con magenta y violeta, para cabina de club.
        Skin(name: "Neón", dark: true,
             background: rgb(0x050507), panel: rgb(0x0C0C12), panelRaised: rgb(0x15151F), header: rgb(0x101019),
             grid: rgb(0xD66BFF, 0.07), gridStrong: rgb(0xD66BFF, 0.17),
             text: rgb(0xF2EEFF), textDim: rgb(0x8A83A6),
             accent: rgb(0xFF3DB8), accentDeep: rgb(0x8A1A66),
             clip: rgb(0x1B1A2B), clipSelected: rgb(0x3D1640), wave: rgb(0x9FE8FF, 0.85), overlay: rgb(0x14304A), playhead: rgb(0x3DFFC8), radius: 8),
        // 6. Estudio claro: tema claro para trabajar de día o con mucha luz.
        Skin(name: "Estudio claro", dark: false,
             background: rgb(0xE9EBEE), panel: rgb(0xF6F7F9), panelRaised: rgb(0xFFFFFF), header: rgb(0xDDE1E6),
             grid: NSColor(white: 0, alpha: 0.06), gridStrong: NSColor(white: 0, alpha: 0.14),
             text: rgb(0x1D2128), textDim: rgb(0x6A7280),
             accent: rgb(0x1E7BE0), accentDeep: rgb(0x0F4C91),
             clip: rgb(0xFFFFFF), clipSelected: rgb(0xD6E8FB), wave: rgb(0x58606C, 0.85), overlay: rgb(0xE6DDF7), playhead: rgb(0xE0352B), radius: 5),
    ]

    static let defaultsKey = "MM8 Skin"
    /// El elegido (View › Skin), o el de `--skin N` al arrancar (pruebas).
    static let current: Skin = {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--skin"), i + 1 < args.count, let n = Int(args[i + 1]), n >= 1, n <= all.count { return all[n - 1] }
        let name = UserDefaults.standard.string(forKey: defaultsKey)
        return all.first { $0.name == name } ?? all[0]
    }()
}

enum Theme {
    static let skin = Skin.current
    static var background: NSColor { skin.background }
    static var panel: NSColor { skin.panel }
    static var panelRaised: NSColor { skin.panelRaised }
    static var header: NSColor { skin.header }
    static var grid: NSColor { skin.grid }
    static var gridStrong: NSColor { skin.gridStrong }
    static var text: NSColor { skin.text }
    static var textDim: NSColor { skin.textDim }
    static var accent: NSColor { skin.accent }
    static var accentDeep: NSColor { skin.accentDeep }
    static var selection: NSColor { skin.accent.withAlphaComponent(0.22) }
    /// Texto sobre el color de acento (pastillas verdes, banderas).
    static var onAccent: NSColor { skin.dark ? skin.background : .white }

    // Colores de los marcadores: los del original (manual de Fusion, tabla 1).
    static let volume = NSColor(srgbRed: 0.27, green: 0.66, blue: 1.00, alpha: 1)       // azul
    static let bass = NSColor(srgbRed: 0.96, green: 0.33, blue: 0.30, alpha: 1)         // rojo
    static let mid = NSColor(srgbRed: 0.72, green: 0.45, blue: 0.98, alpha: 1)          // morado
    static let treble = NSColor(srgbRed: 1.00, green: 0.82, blue: 0.25, alpha: 1)       // amarillo
    static var tempo: NSColor { skin.dark ? NSColor(srgbRed: 0.32, green: 0.88, blue: 0.52, alpha: 1) : NSColor(srgbRed: 0.10, green: 0.58, blue: 0.27, alpha: 1) }
    static let anchor = NSColor(srgbRed: 1.00, green: 0.55, blue: 0.20, alpha: 1)       // naranja
    static var label: NSColor { skin.dark ? NSColor(white: 0.95, alpha: 1) : NSColor(white: 0.2, alpha: 1) }
    static let loop = NSColor(srgbRed: 0.98, green: 0.42, blue: 0.62, alpha: 1)
    static var clip: NSColor { skin.clip }
    static var clipSelected: NSColor { skin.clipSelected }
    static var wave: NSColor { skin.wave }
    static var overlay: NSColor { skin.overlay }
    static let effect = NSColor(srgbRed: 0.36, green: 0.88, blue: 0.95, alpha: 1)       // automatización de efectos
    static var playhead: NSColor { skin.playhead }
    static var radius: CGFloat { skin.radius }
    /// Las pistas claras (Clásico, Estudio claro) llevan el texto oscuro.
    static var clipIsLight: Bool { (skin.clip.usingColorSpace(.sRGB)?.brightnessComponent ?? 0) > 0.6 }
    static var clipText: NSColor { clipIsLight ? NSColor(white: 0.12, alpha: 1) : text }
    static var clipSelectedInk: NSColor { clipIsLight ? accentDeep : accent }

    static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont { .systemFont(ofSize: size, weight: weight) }
    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont { .monospacedDigitSystemFont(ofSize: size, weight: weight) }
}

/// Vista con fondo plano (las de AppKit son transparentes por defecto).
class FillView: NSView {
    var fill: NSColor { didSet { needsDisplay = true } }
    var bottomLine: NSColor?
    init(_ fill: NSColor) { self.fill = fill; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func draw(_ r: NSRect) {
        fill.setFill(); bounds.fill()
        if let c = bottomLine { c.setFill(); NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill() }
    }
}

func label(_ s: String, size: CGFloat = 11, weight: NSFont.Weight = .regular, color: NSColor = Theme.text) -> NSTextField {
    let t = NSTextField(labelWithString: s)
    t.font = Theme.font(size, weight)
    t.textColor = color
    t.lineBreakMode = .byTruncatingTail
    return t
}

/// Botón de barra de herramientas: símbolo SF, sin borde, que se ilumina al pasar.
final class ToolButton: NSButton {
    init(symbol: String, tip: String, action: Selector?, target: AnyObject? = nil, size: CGFloat = 13) {
        super.init(frame: .zero)
        let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?.withSymbolConfiguration(cfg)
        isBordered = false
        bezelStyle = .regularSquare
        contentTintColor = Theme.text
        toolTip = tip
        self.action = action
        self.target = target
        setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 26).isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }
}
