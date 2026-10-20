import AppKit

/// Aspecto de MixMeister 8: la distribución del original con un acabado actual (grafito oscuro,
/// acento verde lima heredado del original, tipografía del sistema, esquinas suaves).
enum Theme {
    static let background = NSColor(srgbRed: 0.075, green: 0.078, blue: 0.086, alpha: 1)
    static let panel = NSColor(srgbRed: 0.105, green: 0.110, blue: 0.122, alpha: 1)
    static let panelRaised = NSColor(srgbRed: 0.145, green: 0.150, blue: 0.165, alpha: 1)
    static let header = NSColor(srgbRed: 0.125, green: 0.130, blue: 0.145, alpha: 1)
    static let grid = NSColor(white: 1, alpha: 0.06)
    static let gridStrong = NSColor(white: 1, alpha: 0.13)
    static let text = NSColor(white: 0.92, alpha: 1)
    static let textDim = NSColor(white: 0.56, alpha: 1)
    static let accent = NSColor(srgbRed: 0.62, green: 0.86, blue: 0.24, alpha: 1)      // verde lima
    static let accentDeep = NSColor(srgbRed: 0.35, green: 0.55, blue: 0.10, alpha: 1)
    static let selection = NSColor(srgbRed: 0.62, green: 0.86, blue: 0.24, alpha: 0.22)

    // Colores de los marcadores: los del original (manual de Fusion, tabla 1).
    static let volume = NSColor(srgbRed: 0.27, green: 0.66, blue: 1.00, alpha: 1)       // azul
    static let bass = NSColor(srgbRed: 0.96, green: 0.33, blue: 0.30, alpha: 1)         // rojo
    static let mid = NSColor(srgbRed: 0.72, green: 0.45, blue: 0.98, alpha: 1)          // morado
    static let treble = NSColor(srgbRed: 1.00, green: 0.82, blue: 0.25, alpha: 1)       // amarillo
    static let tempo = NSColor(srgbRed: 0.32, green: 0.88, blue: 0.52, alpha: 1)        // verde
    static let anchor = NSColor(srgbRed: 1.00, green: 0.55, blue: 0.20, alpha: 1)       // naranja
    static let label = NSColor(white: 0.95, alpha: 1)
    static let loop = NSColor(srgbRed: 0.98, green: 0.42, blue: 0.62, alpha: 1)
    static let clip = NSColor(srgbRed: 0.20, green: 0.215, blue: 0.24, alpha: 1)
    static let clipSelected = NSColor(srgbRed: 0.27, green: 0.34, blue: 0.20, alpha: 1)
    static let wave = NSColor(white: 0.78, alpha: 0.85)
    static let overlay = NSColor(srgbRed: 0.18, green: 0.24, blue: 0.32, alpha: 1)
    static let playhead = NSColor(srgbRed: 1.0, green: 0.30, blue: 0.25, alpha: 1)

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
