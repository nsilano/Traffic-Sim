import CoreGraphics
import CoreText
import Foundation

/// A thin layer over a Core Graphics context that speaks the HTML canvas API the game's
/// drawing code was written in (fillStyle, arc, arcTo, fillText…), so the drawing ports
/// over almost line for line. Coordinates are y-down, like the canvas.
final class Canvas {
    enum Paint {
        case color(CGColor)
        case radial(CGGradient, CGPoint, CGFloat, CGPoint, CGFloat)
    }

    struct Style {
        var fill: Paint = .color(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        var stroke: Paint = .color(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        var font: CTFont = Canvas.font("Archivo-ExtraBold", 10)
        var align = "start"
        var baseline = "alphabetic"
        var alpha: CGFloat = 1
        var lineWidth: CGFloat = 1
    }

    let ctx: CGContext
    private var style = Style()
    private var stack: [Style] = []
    /// The transform setTransform(1,0,0,1,0,0) returns to (device pixels, y down).
    let base: CGAffineTransform

    init(_ ctx: CGContext, base: CGAffineTransform) {
        self.ctx = ctx
        self.base = base
        ctx.setLineCap(.butt)
        ctx.setLineJoin(.miter)
    }

    // MARK: State

    var fillStyle: String {
        get { "" }
        set { style.fill = .color(Canvas.color(newValue)) }
    }

    var strokeStyle: String {
        get { "" }
        set { style.stroke = .color(Canvas.color(newValue)) }
    }

    func setFill(_ paint: Paint) { style.fill = paint }

    var lineWidth: CGFloat {
        get { style.lineWidth }
        set { style.lineWidth = newValue; ctx.setLineWidth(newValue) }
    }

    var globalAlpha: CGFloat {
        get { style.alpha }
        set { style.alpha = newValue; ctx.setAlpha(newValue) }
    }

    /// "source-over" or "destination-out".
    var globalCompositeOperation: String {
        get { "" }
        set { ctx.setBlendMode(newValue == "destination-out" ? .destinationOut : .normal) }
    }

    /// A font as the game names them: "800 12px Archivo", "10px \"Press Start 2P\"", "14px VT323".
    var font: String {
        get { "" }
        set { style.font = Canvas.parseFont(newValue) }
    }

    var textAlign: String {
        get { style.align }
        set { style.align = newValue }
    }

    var textBaseline: String {
        get { style.baseline }
        set { style.baseline = newValue }
    }

    func save() {
        stack.append(style)
        ctx.saveGState()
    }

    func restore() {
        if let s = stack.popLast() { style = s }
        ctx.restoreGState()
    }

    // MARK: Transforms

    func setTransform(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat, _ e: CGFloat, _ f: CGFloat) {
        let current = ctx.ctm
        ctx.concatenate(current.inverted())
        ctx.concatenate(CGAffineTransform(a: a, b: b, c: c, d: d, tx: e, ty: f).concatenating(base))
    }

    func transform(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat, _ e: CGFloat, _ f: CGFloat) {
        ctx.concatenate(CGAffineTransform(a: a, b: b, c: c, d: d, tx: e, ty: f))
    }

    func translate(_ x: CGFloat, _ y: CGFloat) { ctx.translateBy(x: x, y: y) }
    func rotate(_ angle: CGFloat) { ctx.rotate(by: angle) }
    func scale(_ x: CGFloat, _ y: CGFloat) { ctx.scaleBy(x: x, y: y) }

    // MARK: Paths

    func beginPath() { ctx.beginPath() }
    func closePath() { ctx.closePath() }
    func moveTo(_ x: CGFloat, _ y: CGFloat) { ctx.move(to: CGPoint(x: x, y: y)) }

    func lineTo(_ x: CGFloat, _ y: CGFloat) {
        if ctx.isPathEmpty { ctx.move(to: CGPoint(x: x, y: y)) } else { ctx.addLine(to: CGPoint(x: x, y: y)) }
    }

    func quadraticCurveTo(_ cx: CGFloat, _ cy: CGFloat, _ x: CGFloat, _ y: CGFloat) {
        ctx.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cx, y: cy))
    }

    /// Like canvas arc(): angles increase the way the canvas draws by default.
    func arc(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ a0: CGFloat, _ a1: CGFloat) {
        guard r > 0 else { return }
        let start = CGPoint(x: x + r * cos(a0), y: y + r * sin(a0))
        if ctx.isPathEmpty { ctx.move(to: start) } else { ctx.addLine(to: start) }
        ctx.addArc(center: CGPoint(x: x, y: y), radius: r, startAngle: a0, endAngle: a1, clockwise: false)
    }

    func arcTo(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ r: CGFloat) {
        ctx.addArc(tangent1End: CGPoint(x: x1, y: y1), tangent2End: CGPoint(x: x2, y: y2), radius: max(0, r))
    }

    func ellipse(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat) {
        ctx.addEllipse(in: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2))
    }

    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        ctx.addRect(CGRect(x: x, y: y, width: w, height: h))
    }

    /// The game's roundRect(): a rounded rectangle path.
    func roundRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) {
        beginPath()
        moveTo(x + r, y)
        arcTo(x + w, y, x + w, y + h, r)
        arcTo(x + w, y + h, x, y + h, r)
        arcTo(x, y + h, x, y, r)
        arcTo(x, y, x + w, y, r)
        closePath()
    }

    /// Fills the current path. Like the canvas (and unlike Core Graphics) the path stays,
    /// so the same shape can be stroked afterwards.
    func fill() {
        guard !ctx.isPathEmpty, let path = ctx.path else { return }
        switch style.fill {
        case .color(let c):
            ctx.setFillColor(c)
            ctx.fillPath()
        case let .radial(gradient, c0, r0, c1, r1):
            ctx.saveGState()
            ctx.clip()
            ctx.drawRadialGradient(gradient, startCenter: c0, startRadius: r0, endCenter: c1, endRadius: r1, options: [])
            ctx.restoreGState()
        }
        ctx.addPath(path)
    }

    func stroke() {
        guard !ctx.isPathEmpty else { return }
        if case .color(let c) = style.stroke { ctx.setStrokeColor(c) }
        // stroke() keeps the path in the canvas API; Core Graphics consumes it, so keep a copy.
        let path = ctx.path
        ctx.strokePath()
        if let path = path { ctx.addPath(path) }
    }

    func clip() { ctx.clip() }

    func fillRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        let r = CGRect(x: x, y: y, width: w, height: h)
        switch style.fill {
        case .color(let c):
            ctx.setFillColor(c)
            ctx.fill(r)
        case .radial:
            ctx.beginPath()
            ctx.addRect(r)
            fill()
        }
    }

    func strokeRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        if case .color(let c) = style.stroke { ctx.setStrokeColor(c) }
        ctx.stroke(CGRect(x: x, y: y, width: w, height: h))
    }

    func clearRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        ctx.clear(CGRect(x: x, y: y, width: w, height: h))
    }

    /// Draws an image the right way up in the y-down space.
    func drawImage(_ image: CGImage, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat? = nil, _ h: CGFloat? = nil) {
        let w = w ?? CGFloat(image.width), h = h ?? CGFloat(image.height)
        ctx.saveGState()
        ctx.translateBy(x: x, y: y + h)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.restoreGState()
    }

    // MARK: Text

    func measureText(_ text: String) -> CGFloat {
        let line = Canvas.line(text, style.font, CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    func fillText(_ text: String, _ x: CGFloat, _ y: CGFloat) {
        guard case .color(let c) = style.fill else { return }
        drawText(text, x, y, color: c, strokeWidth: nil)
    }

    func strokeText(_ text: String, _ x: CGFloat, _ y: CGFloat) {
        guard case .color(let c) = style.stroke else { return }
        drawText(text, x, y, color: c, strokeWidth: style.lineWidth)
    }

    private func drawText(_ text: String, _ x: CGFloat, _ y: CGFloat, color: CGColor, strokeWidth: CGFloat?) {
        let font = style.font
        let line = Canvas.line(text, font, color)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
        var dx: CGFloat = 0
        switch style.align {
        case "center": dx = -width / 2
        case "right", "end": dx = -width
        default: dx = 0
        }
        // Canvas "middle" sits on the em box centre; alphabetic on the baseline.
        var dy: CGFloat = 0
        switch style.baseline {
        case "middle": dy = (ascent - descent) / 2
        case "top": dy = ascent
        case "bottom": dy = -descent
        default: dy = 0
        }
        ctx.saveGState()
        ctx.translateBy(x: x + dx, y: y + dy)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        ctx.textPosition = .zero
        if let w = strokeWidth {
            ctx.setTextDrawingMode(.stroke)
            ctx.setLineWidth(w)
            ctx.setLineJoin(.round)
            ctx.setStrokeColor(color)
        } else {
            ctx.setTextDrawingMode(.fill)
        }
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    // MARK: Helpers

    private static var fontsLoaded = false

    /// Registers the bundled fonts (Archivo, Press Start 2P, VT323) once.
    static func loadFonts() {
        guard !fontsLoaded else { return }
        fontsLoaded = true
        for name in ["Archivo-Bold", "Archivo-ExtraBold", "PressStart2P-Regular", "VT323-Regular"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.module.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    private static var fontCache: [String: CTFont] = [:]

    static func font(_ postscript: String, _ size: CGFloat) -> CTFont {
        let key = "\(postscript)/\(size)"
        if let f = fontCache[key] { return f }
        loadFonts()
        let f = CTFontCreateWithName(postscript as CFString, size, nil)
        fontCache[key] = f
        return f
    }

    static func parseFont(_ spec: String) -> CTFont {
        // "[weight ]<size>px <family>"
        let parts = spec.split(separator: " ")
        var weight = 400
        var size: CGFloat = 10
        for p in parts {
            if p.hasSuffix("px"), let v = Double(p.dropLast(2)) { size = CGFloat(v) } else if let w = Int(p) { weight = w }
        }
        if spec.contains("Press Start") { return font("PressStart2P-Regular", size) }
        if spec.contains("VT323") { return font("VT323-Regular", size) }
        return font(weight >= 800 ? "ArchivoSemiBold-ExtraBold" : "ArchivoSemiBold-Bold", size)
    }

    private static var colorCache: [String: CGColor] = [:]

    /// "#rgb", "#rrggbb" or "rgba(r, g, b, a)".
    static func color(_ s: String) -> CGColor {
        if let c = colorCache[s] { return c }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") {
            let hex = String(t.dropFirst())
            let full = hex.count == 3 ? hex.map { "\($0)\($0)" }.joined() : hex
            if let v = UInt32(full, radix: 16) {
                r = CGFloat((v >> 16) & 0xFF) / 255
                g = CGFloat((v >> 8) & 0xFF) / 255
                b = CGFloat(v & 0xFF) / 255
            }
        } else if let open = t.firstIndex(of: "("), let close = t.lastIndex(of: ")") {
            let nums = t[t.index(after: open)..<close].split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
            if nums.count >= 3 {
                r = CGFloat(nums[0]) / 255
                g = CGFloat(nums[1]) / 255
                b = CGFloat(nums[2]) / 255
            }
            if nums.count >= 4 { a = CGFloat(nums[3]) }
        }
        let c = CGColor(red: r, green: g, blue: b, alpha: a)
        colorCache[s] = c
        return c
    }

    static func radialGradient(_ stops: [(CGFloat, String)]) -> CGGradient {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        return CGGradient(colorsSpace: space, colors: stops.map { color($0.1) } as CFArray, locations: stops.map { $0.0 })!
    }

    static func line(_ text: String, _ font: CTFont, _ color: CGColor) -> CTLine {
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color]
        let s = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!
        return CTLineCreateWithAttributedString(s)
    }

    /// A transparent bitmap context of the given pixel size.
    static func bitmap(_ width: Int, _ height: Int) -> CGContext {
        CGContext(data: nil, width: max(1, width), height: max(1, height), bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    /// A canvas over a fresh bitmap, set up y-down like an HTML canvas.
    static func offscreen(_ width: Int, _ height: Int) -> Canvas {
        let ctx = bitmap(width, height)
        let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(height))
        ctx.concatenate(flip)
        return Canvas(ctx, base: flip)
    }
}
