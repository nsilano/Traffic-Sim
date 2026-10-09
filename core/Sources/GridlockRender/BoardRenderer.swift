import CoreGraphics
import Foundation
import GridlockCore

/// Draws the board for a simulation: roads and city, traffic, people, signals, night
/// lighting, effects, popups and banners. A port of render() and friends in game.js,
/// drawing through `Canvas` so it reads almost line for line like the original.
public final class BoardRenderer {
    public struct Options {
        /// Settings → Turn signals.
        public var turnSignals = true
        public init() {}
    }

    public private(set) var sim: Simulation
    public var options = Options()

    /// The visible slice of the 640 × 640 board: tall screens trim the far ends of the side
    /// roads so everything draws bigger.
    public private(set) var viewX0 = 0.0
    public private(set) var viewW = World.width

    private var background: (key: String, image: CGImage)?
    private var overlay: (key: String, image: CGImage)?
    private var shakeRandom = SystemRandomNumberGenerator()

    public init(simulation: Simulation) {
        sim = simulation
        Canvas.loadFonts()
    }

    /// Starts drawing a different shift (the cached city and decor are redrawn).
    public func setSimulation(_ simulation: Simulation) {
        sim = simulation
        background = nil
        overlay = nil
    }

    static let minViewWidth = 400.0

    /// The board's visible width for a view of this size (points), and its left edge.
    public static func viewSlice(width: Double, height: Double) -> (x0: Double, w: Double) {
        let w = min(World.width, World.width * width / height)
        return (World.cx - w / 2, w)
    }

    /// Board coordinates of a point in the view, for taps.
    public func boardPoint(viewX: Double, viewY: Double, height: Double) -> Vec {
        let scale = height / World.height
        return Vec(viewX / scale + viewX0, viewY / scale)
    }

    /// Draws one frame into `ctx`, whose current transform maps points with y down.
    /// `pixelScale` is the screen scale (for the cached layers), `clock` the wall clock (overpass traffic).
    public func render(in ctx: CGContext, size: CGSize, pixelScale: CGFloat, clock: Double) {
        let slice = Self.viewSlice(width: Double(size.width), height: Double(size.height))
        viewX0 = slice.x0
        viewW = slice.w
        let scale = CGFloat(Double(size.height) / World.height)
        let g = Canvas(ctx, base: ctx.ctm)

        g.setTransform(1, 0, 0, 1, 0, 0)
        g.fillStyle = "#161b21"
        g.fillRect(0, 0, size.width, size.height)
        var sx: CGFloat = 0, sy: CGFloat = 0
        if sim.shake > 0 {
            let amp = 7 * (sim.shake / 0.5)
            sx = CGFloat((Double.random(in: 0..<1, using: &shakeRandom) - 0.5) * amp) * scale
            sy = CGFloat((Double.random(in: 0..<1, using: &shakeRandom) - 0.5) * amp) * scale
        }
        let pw = Int((size.width * pixelScale).rounded()), ph = Int((size.height * pixelScale).rounded())
        let key = "\(sim.levelIndex)-\(sim.level.name)-\(pw)x\(ph)"
        if background?.key != key {
            let bg = Canvas.offscreen(pw, ph)
            drawBackground(bg, scale: scale * pixelScale)
            background = bg.ctx.makeImage().map { (key, $0) }
            let ov = Canvas.offscreen(pw, ph)
            drawOverlay(ov, scale: scale * pixelScale)
            overlay = ov.ctx.makeImage().map { (key, $0) }
        }
        if let image = background?.image { g.drawImage(image, sx, sy, size.width, size.height) }
        toView(g, scale, sx, sy)

        drawLamps(g)
        drawPeds(g)
        for c in sim.cars {
            let at = c.path.point(at: c.s - c.len / 2)
            drawCarBody(g, at.position.x, at.position.y, at.angle, body(c), false)
        }
        for w in sim.wrecks {
            g.globalAlpha = w.t > 5 - 0.8 ? CGFloat((5 - w.t) / 0.8) : 1
            drawCarBody(g, w.x, w.y, w.angle, CarLook(len: w.len, wid: w.wid, color: w.color, truck: w.truck, emergency: nil, slow: false), true)
            g.globalAlpha = 1
        }
        drawEffects(g)
        if let image = overlay?.image {
            g.save()
            g.setTransform(1, 0, 0, 1, sx, sy)
            g.drawImage(image, 0, 0, size.width, size.height)
            g.restore()
        }
        if hasDecor("overpass") { drawOverpassTraffic(g, clock) }
        if sim.level.night == true { drawNight(g, scale: scale, pixelScale: pixelScale, size: size, clock: clock) }
        for c in sim.cars { drawDriverMarks(g, c) }
        for c in sim.cars { drawWaitRing(g, c) }
        drawWalkSignals(g)
        drawBacklog(g)
        drawEmergencyWarning(g)
        drawStreetSigns(g)
        drawScorePopups(g)
    }

    // MARK: Helpers

    private var geo: Geometry { sim.geometry }
    private let W = CGFloat(World.width), H = CGFloat(World.height)
    private let CX = CGFloat(World.cx), CY = CGFloat(World.cy)
    private let laneW = CGFloat(World.laneWidth), crosswalk = CGFloat(World.crosswalk)
    private let sidewalk = CGFloat(World.sidewalk), stopGap = CGFloat(World.stopGap)
    private let overpassY: CGFloat = 512, overpassH: CGFloat = 46

    private func toView(_ g: Canvas, _ s: CGFloat, _ sx: CGFloat = 0, _ sy: CGFloat = 0) {
        g.setTransform(s, 0, 0, s, -CGFloat(viewX0) * s + sx, sy)
    }

    private func hasDecor(_ name: String) -> Bool { (sim.level.decor ?? []).contains(name) }

    private func underOverpass(_ x: Double, _ y: Double) -> Bool {
        hasDecor("overpass") && CGFloat(y) > overpassY && CGFloat(y) < overpassY + overpassH
    }

    /// game.js seeded(): a small repeatable generator for the city's layout.
    private final class Seeded {
        private var seed: Int64
        init(_ seed: Int64) { self.seed = seed }
        func next() -> CGFloat {
            seed = (seed * 16807) % 2147483647
            return CGFloat(Double(seed - 1) / 2147483646)
        }
    }

    /// Local frame for one approach: +u is the direction of travel, +v the driver's right.
    private func approachFrame(_ g: Canvas, _ k: Direction) {
        let d = k.heading, r = k.right
        g.transform(d.x, d.y, r.x, r.y, CX, CY)
    }

    private struct CarLook {
        let len, wid: Double
        let color: String
        let truck: Bool
        let emergency: EmergencyKind?
        /// Below half its top speed: brake lights on.
        let slow: Bool
    }

    private func body(_ c: Car) -> CarLook {
        CarLook(len: c.len, wid: c.wid, color: c.color, truck: c.truck, emergency: c.emergency, slow: c.v < c.topSpeed * 0.5)
    }

    // MARK: City and roads (drawn once)

    private func drawBackground(_ g: Canvas, scale: CGFloat) {
        toView(g, scale)
        let rnd = Seeded(Int64(7 + sim.levelIndex * 13))
        let b = geo.box
        let x0 = CGFloat(b.x0), x1 = CGFloat(b.x1), y0 = CGFloat(b.y0), y1 = CGFloat(b.y1)

        g.fillStyle = "#9da5ad"
        g.fillRect(0, 0, W, H)

        let left = x0 - sidewalk, right = x1 + sidewalk
        let top = y0 - sidewalk, bottom = y1 + sidewalk
        drawBuildings(g, 0, 0, left, top, rnd)
        drawBuildings(g, right, 0, W - right, top, rnd)
        drawPark(g, 0, bottom, left, H - bottom, rnd)
        drawBuildings(g, right, bottom, W - right, H - bottom, rnd)
        if !geo.hasLeg(.E) { drawBuildings(g, 0, top, left, bottom - top, rnd) }
        if !geo.hasLeg(.W) { drawBuildings(g, right, top, W - right, bottom - top, rnd) }
        if !geo.hasLeg(.S) { drawBuildings(g, left, 0, right - left, top, rnd) }
        if !geo.hasLeg(.N) { drawBuildings(g, left, bottom, right - left, H - bottom, rnd) }
        if hasDecor("harbor") { drawHarbor(g, left - 4, rnd) }
        drawCompass(g, CGFloat(viewX0) + 26, H - 30)

        g.fillStyle = "#3a4048"
        g.fillRect(x0, y0, x1 - x0, y1 - y0)
        for k in Direction.allCases where geo.hasLeg(k) {
            g.save()
            approachFrame(g, k)
            legShape(g, k)
            g.fill()
            g.restore()
        }

        g.strokeStyle = "#c7ccd1"
        g.lineWidth = 2
        for k in Direction.allCases {
            g.save()
            approachFrame(g, k)
            let e = geo.ext(k)
            if geo.hasLeg(k) {
                let l = geo.legDims(k)
                g.beginPath(); g.moveTo(l.near, l.R + 1); g.lineTo(l.far, l.R + 1); g.stroke()
                g.beginPath(); g.moveTo(l.far, -l.L1 - 1); g.lineTo(l.m1, -l.L1 - 1); g.lineTo(l.m0, -l.L0 - 1); g.lineTo(l.near, -l.L0 - 1); g.stroke()
            } else {
                g.beginPath(); g.moveTo(-e.near - 1, -e.left); g.lineTo(-e.near - 1, e.right); g.stroke()
            }
            g.restore()
        }

        for k in Direction.allCases where geo.hasLeg(k) {
            g.save()
            approachFrame(g, k)
            drawLegMarkings(g, k)
            g.restore()
        }
        if hasDecor("works") { drawRoadWorks(g, Seeded(91)) }
    }

    private func drawHarbor(_ g: Canvas, _ edge: CGFloat, _ rnd: Seeded) {
        g.fillStyle = "#1e4a63"
        g.fillRect(0, 0, edge, H)
        g.strokeStyle = "rgba(160, 205, 225, 0.22)"
        g.lineWidth = 1.5
        var y: CGFloat = 14
        while y < H {
            var x = 8 + (y / 22).truncatingRemainder(dividingBy: 2) * 14
            while x < edge - 16 {
                g.beginPath(); g.moveTo(x, y); g.quadraticCurveTo(x + 6, y - 4, x + 12, y); g.stroke()
                x += 34
            }
            y += 22
        }
        g.fillStyle = "#6f7479"
        g.fillRect(edge - 8, 0, 8, H)
        for y in [70, 210, 470, 560] as [CGFloat] {
            let len = 90 + rnd.next() * 60
            g.fillStyle = "#6b4f35"
            g.fillRect(edge - 8 - len, y, len, 16)
            g.strokeStyle = "rgba(0, 0, 0, 0.25)"; g.lineWidth = 1
            var x = edge - 8 - len
            while x < edge - 8 { g.beginPath(); g.moveTo(x, y); g.lineTo(x, y + 16); g.stroke(); x += 7 }
            let bx = edge - 8 - len + 10 + rnd.next() * (len - 60), by = y + (rnd.next() < 0.5 ? -20 : 22)
            g.fillStyle = "rgba(0, 0, 0, 0.25)"
            g.roundRect(bx + 3, by + 3, 46, 14, 7); g.fill()
            g.fillStyle = ["#e8eef3", "#c45a4a", "#d6a12b", "#3d6fb0"][Int(floor(rnd.next() * 4))]
            g.roundRect(bx, by, 46, 14, 7); g.fill()
            g.fillStyle = "rgba(255, 255, 255, 0.7)"
            g.roundRect(bx + 12, by + 3, 18, 8, 3); g.fill()
        }
    }

    private func drawRoadWorks(_ g: Canvas, _ rnd: Seeded) {
        let b = geo.box
        for k in Direction.allCases where geo.hasLeg(k) {
            g.save(); approachFrame(g, k)
            let l = geo.legDims(k)
            let far = CGFloat(l.far), near = CGFloat(l.near), R = CGFloat(l.R), L0 = CGFloat(l.L0)
            for _ in 0..<2 {
                let u = far + 40 + rnd.next() * (near - far - 160), v = -L0 + rnd.next() * (L0 + R - 30)
                g.fillStyle = "rgba(20, 22, 26, 0.45)"
                let w = 34 + rnd.next() * 30
                let h = 18 + rnd.next() * 10
                g.fillRect(u, v, w, h)
            }
            let u = far + 60 + rnd.next() * (near - far - 200), v = -L0 + 4 + rnd.next() * (L0 + R - 40)
            g.fillStyle = "#6d747b"
            g.fillRect(u, v, 30, 26)
            g.fillStyle = "rgba(255, 255, 255, 0.25)"
            var x = u + 3
            while x < u + 30 {
                var y = v + 3
                while y < v + 26 { g.fillRect(x, y, 2, 2); y += 6 }
                x += 6
            }
            g.restore()
        }
        func cone(_ x: CGFloat, _ y: CGFloat) {
            g.fillStyle = "#f26b1d"
            g.beginPath(); g.moveTo(x, y - 6); g.lineTo(x + 5, y + 5); g.lineTo(x - 5, y + 5); g.closePath(); g.fill()
            g.fillStyle = "#ffffff"; g.fillRect(x - 3, y, 6, 2)
        }
        var x: CGFloat = 12
        while x < CGFloat(b.x0) - 20 { cone(x, CGFloat(b.y0) - 6); x += 22 }
        var y = CGFloat(b.y1) + 24
        while y < H - 10 { cone(CGFloat(b.x1) + 8, y); y += 22 }
        for (bx, by) in [(CGFloat(b.x0) - 9, CGFloat(b.y1) + 9), (CGFloat(b.x1) + 9, CGFloat(b.y0) - 9)] {
            g.fillStyle = "#f26b1d"; g.beginPath(); g.arc(bx, by, 6, 0, .pi * 2); g.fill()
            g.strokeStyle = "#ffffff"; g.lineWidth = 1.5; g.beginPath(); g.arc(bx, by, 3.5, 0, .pi * 2); g.stroke()
        }
        let sx = CGFloat(viewX0 + viewW) - 34, sy = H - 34
        g.save(); g.translate(sx, sy); g.rotate(.pi / 4)
        g.fillStyle = "#f26b1d"; g.fillRect(-11, -11, 22, 22)
        g.strokeStyle = "#141414"; g.lineWidth = 1.5; g.strokeRect(-9, -9, 18, 18)
        g.restore()
        g.fillStyle = "#141414"; g.font = "800 6px Archivo"
        g.textAlign = "center"; g.textBaseline = "middle"
        g.fillText("ROAD", sx, sy - 3); g.fillText("WORK", sx, sy + 4)
    }

    /// Static decor drawn over traffic: tree canopies, building shadows, an overpass.
    private func drawOverlay(_ g: Canvas, scale: CGFloat) {
        toView(g, scale)
        let b = geo.box
        if hasDecor("shadows") {
            g.fillStyle = "rgba(8, 12, 20, 0.3)"
            let left = CGFloat(b.x0) - sidewalk, right = CGFloat(b.x1) + sidewalk
            let top = CGFloat(b.y0) - sidewalk, bottom = CGFloat(b.y1) + sidewalk
            for (x, y, w, h) in [(0, 0, left, top), (right, 0, W - right, top), (right, bottom, W - right, H - bottom)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
                let dx: CGFloat = 70, dy: CGFloat = 95
                g.beginPath()
                g.moveTo(x + w, y); g.lineTo(x + w + dx, y + dy); g.lineTo(x + w + dx, y + h + dy)
                g.lineTo(x + dx, y + h + dy); g.lineTo(x, y + h); g.lineTo(x + w, y + h); g.closePath()
                g.fill()
            }
        }
        if hasDecor("trees") {
            let rnd = Seeded(Int64(57 + sim.levelIndex))
            for k in Direction.allCases where geo.hasLeg(k) {
                g.save(); approachFrame(g, k)
                let l = geo.legDims(k)
                for side in [CGFloat(l.R) + sidewalk / 2, -CGFloat(l.L0) - sidewalk / 2] {
                    var u = CGFloat(l.near) - 70 - rnd.next() * 20
                    while u > CGFloat(l.far) + 30 {
                        let r = 17 + rnd.next() * 9, v = side + (rnd.next() - 0.5) * 8
                        g.fillStyle = "rgba(16, 26, 14, 0.35)"
                        g.beginPath(); g.arc(u + 4, v + 4, r, 0, .pi * 2); g.fill()
                        g.fillStyle = rnd.next() < 0.5 ? "#35603a" : "#42703f"
                        g.beginPath(); g.arc(u, v, r, 0, .pi * 2); g.fill()
                        g.fillStyle = "rgba(160, 200, 120, 0.18)"
                        g.beginPath(); g.arc(u - r * 0.3, v - r * 0.3, r * 0.55, 0, .pi * 2); g.fill()
                        u -= 58 + rnd.next() * 30
                    }
                }
                g.restore()
            }
        }
        if hasDecor("overpass") {
            let y0 = overpassY
            g.fillStyle = "rgba(0, 0, 0, 0.4)"
            g.fillRect(0, y0 + 10, W, overpassH)
            g.fillStyle = "#8e959c"
            g.fillRect(0, y0, W, overpassH)
            g.fillStyle = "#4e555c"
            g.fillRect(0, y0 + 5, W, overpassH - 10)
            g.fillStyle = "#c9cdd1"
            g.fillRect(0, y0, W, 3); g.fillRect(0, y0 + overpassH - 3, W, 3)
            g.fillStyle = "#e3b23c"
            g.fillRect(0, y0 + overpassH / 2 - 1, W, 2)
        }
    }

    private func legShape(_ g: Canvas, _ k: Direction) {
        let l = geo.legDims(k)
        g.beginPath()
        g.moveTo(l.near + 1, l.R); g.lineTo(l.far, l.R); g.lineTo(l.far, -l.L1)
        g.lineTo(l.m1, -l.L1); g.lineTo(l.m0, -l.L0); g.lineTo(l.near + 1, -l.L0)
        g.closePath()
    }

    private func drawLegMarkings(_ g: Canvas, _ k: Direction) {
        let l = geo.legDims(k)
        let far = CGFloat(l.far), near = CGFloat(l.near), R = CGFloat(l.R), L0 = CGFloat(l.L0)
        let m0 = CGFloat(l.m0), m1 = CGFloat(l.m1), mh = CGFloat(l.mh)
        let spec = geo.lanes[k]!
        let uStop = near - crosswalk - stopGap
        let outOpp = geo.out[k.opposite]!
        let exitLanes = Int(((L0 - mh) / laneW).rounded())

        if R > 0 && L0 > 0 && mh > 0 {
            let end = near - crosswalk - 10
            g.fillStyle = "#c7ccd1"
            g.roundRect(far, -mh, end - far, mh * 2, mh); g.fill()
            g.fillStyle = "#5d7d4f"
            g.roundRect(far, -mh + 2, end - far - 2, mh * 2 - 4, mh - 2); g.fill()
            let rnd = Seeded(Int64(31 + Int(k.rawValue.unicodeScalars.first!.value)))
            var u = end - 24
            while u > far + 10 {
                let r = mh * (0.55 + rnd.next() * 0.3)
                g.fillStyle = "rgba(20, 30, 18, 0.3)"
                g.beginPath(); g.arc(u + 2, 2, r, 0, .pi * 2); g.fill()
                g.fillStyle = rnd.next() < 0.5 ? "#3f6a3a" : "#4b7a43"
                g.beginPath(); g.arc(u, 0, r, 0, .pi * 2); g.fill()
                u -= 30 + rnd.next() * 16
            }
            g.fillStyle = "#e3b23c"
            g.fillRect(far, mh + 1, uStop + 4 - far, 1.6)
            g.fillRect(far, -mh - 2.6, end - far, 1.6)
        } else if R > 0 && L0 > 0 {
            let end = spec.isEmpty ? near - crosswalk - 2 : uStop + 4
            g.fillStyle = "#e3b23c"
            g.fillRect(far, -2.5, end - far, 1.6)
            g.fillRect(far, 0.9, end - far, 1.6)
        }

        g.fillStyle = "#eef0ea"
        if spec.count > 1 {
            for j in 1..<spec.count {
                let v = mh + laneW * CGFloat(j) - 1
                let turnLane = spec[j - 1] == "L"
                if turnLane { g.fillRect(uStop - 150, v, 150, 2) }
                var u = far
                while u < (turnLane ? uStop - 150 : uStop) { g.fillRect(u, v, 12, 2); u += 24 }
            }
        }
        if exitLanes > 1 {
            for j in 1..<exitLanes {
                let start = j < outOpp ? far : m1 + CGFloat(geo.mergeLength) * 0.35
                var u = start
                while u < near - crosswalk - 2 { g.fillRect(u, -mh - laneW * CGFloat(j) - 1, 12, 2); u += 24 }
            }
        }
        g.strokeStyle = "rgba(238, 240, 234, 0.85)"
        g.lineWidth = 2.5
        var j = max(outOpp, 1)
        while j < exitLanes {
            let v = -mh - laneW * (CGFloat(j) + 0.5), u0 = m0 + 4
            g.beginPath(); g.moveTo(u0, v); g.lineTo(u0 - 16, v); g.lineTo(u0 - 32, v + 10); g.stroke()
            g.beginPath(); g.moveTo(u0 - 37, v + 13); g.lineTo(u0 - 26, v + 12.5); g.lineTo(u0 - 31, v + 5); g.closePath(); g.fill()
            j += 1
        }

        if !spec.isEmpty { g.fillRect(uStop + 1, mh + 2, 4, R - mh - 2) }
        var v = -L0 + 3
        while v < R - 3 { g.fillRect(near - crosswalk + 2, v, crosswalk - 4, 4); v += 8 }

        g.fillStyle = "rgba(238, 240, 234, 0.85)"
        for (i, laneSpec) in spec.enumerated() { drawLaneArrow(g, uStop - 46, CGFloat(geo.laneOff(k, i)), laneSpec) }
    }

    private func drawLaneArrow(_ g: Canvas, _ u: CGFloat, _ v: CGFloat, _ spec: String) {
        func head(_ x: CGFloat, _ y: CGFloat, _ dx: CGFloat, _ dy: CGFloat) {
            g.beginPath()
            g.moveTo(x + dx * 6, y + dy * 6)
            g.lineTo(x - dy * 4, y + dx * 4)
            g.lineTo(x + dy * 4, y - dx * 4)
            g.closePath(); g.fill()
        }
        let L = spec.contains("L"), T = spec.contains("T"), R = spec.contains("R")
        let branch = T ? u - 2 : u + 4
        g.beginPath(); g.moveTo(u - 12, v); g.lineTo(T ? u + 8 : branch, v); g.stroke()
        if T { head(u + 8, v, 1, 0) }
        if L { g.beginPath(); g.moveTo(branch, v); g.lineTo(branch, v - 6); g.stroke(); head(branch, v - 6, 0, -1) }
        if R { g.beginPath(); g.moveTo(branch, v); g.lineTo(branch, v + 6); g.stroke(); head(branch, v + 6, 0, 1) }
    }

    private func drawBuildings(_ g: Canvas, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ rnd: Seeded) {
        g.fillStyle = "#7d858d"
        g.fillRect(x, y, w, h)
        let roofs = ["#5b6670", "#6f6a63", "#4f5a52", "#73665f", "#56606b"]
        let split = 0.4 + rnd.next() * 0.2
        var cx = x
        for cw in [w * split, w * (1 - split)] {
            let rows = 1 + Int(floor(rnd.next() * 2))
            var cy = y
            for r in 0..<rows {
                let ch = rows == 1 ? h : r == 0 ? h * (0.4 + rnd.next() * 0.2) : h - (cy - y)
                let bx = cx + 4, by = cy + 4, bw = cw - 8, bh = ch - 8
                if bw > 8 && bh > 8 {
                    g.fillStyle = roofs[Int(floor(rnd.next() * CGFloat(roofs.count)))]
                    g.fillRect(bx, by, bw, bh)
                    g.strokeStyle = "rgba(255, 255, 255, 0.12)"
                    g.lineWidth = 2
                    g.strokeRect(bx + 3, by + 3, bw - 6, bh - 6)
                    let units = 1 + Int(floor(rnd.next() * 3))
                    for _ in 0..<units {
                        let uw = min(bw - 12, 12 + rnd.next() * 18), uh = min(bh - 12, 10 + rnd.next() * 14)
                        if uw < 4 || uh < 4 { continue }
                        let ux = bx + 6 + rnd.next() * max(1, bw - uw - 12)
                        let uy = by + 6 + rnd.next() * max(1, bh - uh - 12)
                        g.fillStyle = "rgba(20, 24, 28, 0.25)"
                        g.fillRect(ux + 3, uy + 3, uw, uh)
                        g.fillStyle = "#a9b0b6"
                        g.fillRect(ux, uy, uw, uh)
                    }
                }
                cy += ch
            }
            cx += cw
        }
    }

    private func drawPark(_ g: Canvas, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ rnd: Seeded) {
        g.fillStyle = "#5d7d4f"
        g.fillRect(x, y, w, h)
        g.strokeStyle = "#b8b09c"
        g.lineWidth = 8
        g.beginPath()
        g.moveTo(x + w, y + 10)
        g.quadraticCurveTo(x + w * 0.45, y + h * 0.4, x + 10, y + h)
        g.stroke()
        let trees = Int(((w * h) / 2000).rounded())
        for _ in 0..<max(0, trees) {
            let tx = x + 12 + rnd.next() * max(1, w - 24), ty = y + 12 + rnd.next() * max(1, h - 24)
            let r = 7 + rnd.next() * 9
            g.fillStyle = "rgba(20, 30, 18, 0.3)"
            g.beginPath(); g.arc(tx + 3, ty + 3, r, 0, .pi * 2); g.fill()
            g.fillStyle = rnd.next() < 0.5 ? "#3f6a3a" : "#4b7a43"
            g.beginPath(); g.arc(tx, ty, r, 0, .pi * 2); g.fill()
        }
    }

    private func drawCompass(_ g: Canvas, _ x: CGFloat, _ y: CGFloat) {
        g.fillStyle = "rgba(22, 27, 33, 0.75)"
        g.beginPath(); g.arc(x, y, 16, 0, .pi * 2); g.fill()
        g.fillStyle = "#e5484d"
        g.beginPath(); g.moveTo(x, y - 11); g.lineTo(x + 5, y + 1); g.lineTo(x - 5, y + 1); g.closePath(); g.fill()
        g.fillStyle = "#e8edf2"
        g.beginPath(); g.moveTo(x, y + 11); g.lineTo(x + 5, y + 1); g.lineTo(x - 5, y + 1); g.closePath(); g.fill()
        g.font = "800 11px Archivo"
        g.textAlign = "center"; g.textBaseline = "middle"
        g.fillStyle = "#e8edf2"
        g.fillText("N", x, y - 23)
    }

    // MARK: Signals, people, cars

    private static let lightColor: [SignalGroup.Light: String] = [.red: "#e5484d", .yellow: "#f2a91f", .green: "#30c070"]

    private func drawLamps(_ g: Canvas) {
        for lamp in geo.lamps {
            let color = Self.lightColor[sim.groups[lamp.group].light]!
            g.save()
            approachFrame(g, lamp.dir)
            let u = CGFloat(lamp.u), v = CGFloat(lamp.v)
            g.fillStyle = "#15181c"
            g.beginPath(); g.arc(u, v, 6.5, 0, .pi * 2); g.fill()
            g.fillStyle = color
            if lamp.kind == "L" {
                g.beginPath()
                g.moveTo(u, v - 5)
                g.lineTo(u + 4.5, v - 0.5)
                g.lineTo(u - 4.5, v - 0.5)
                g.closePath(); g.fill()
                g.fillRect(u - 1.6, v - 1, 3.2, 5)
            } else {
                g.beginPath(); g.arc(u, v, 4.2, 0, .pi * 2); g.fill()
            }
            g.restore()
        }
    }

    private func drawWalkSignals(_ g: Canvas) {
        for cw in geo.crosswalks {
            let st = sim.groups[cw.group].light
            for v in [cw.road0 - 8, cw.road1 + 8] {
                let at = cw.point(v, -(World.crosswalk / 2 + 9))
                if underOverpass(at.x, at.y) { continue }
                let x = CGFloat(at.x), y = CGFloat(at.y)
                g.fillStyle = "#15181c"
                g.roundRect(x - 6.5, y - 6.5, 13, 13, 3); g.fill()
                g.strokeStyle = "rgba(255, 255, 255, 0.25)"; g.lineWidth = 0.8
                g.roundRect(x - 6.5, y - 6.5, 13, 13, 3); g.stroke()
                if st == .green {
                    g.strokeStyle = "#f2f6f3"; g.fillStyle = "#f2f6f3"; g.lineWidth = 1.4
                    g.beginPath(); g.arc(x + 0.5, y - 3.3, 1.3, 0, .pi * 2); g.fill()
                    g.beginPath()
                    g.moveTo(x, y - 1.5); g.lineTo(x - 0.6, y + 1.5)
                    g.lineTo(x - 2.4, y + 4.2); g.moveTo(x - 0.6, y + 1.5); g.lineTo(x + 1.6, y + 4.2)
                    g.moveTo(x - 2.6, y + 0.2); g.lineTo(x, y - 1.2); g.lineTo(x + 2.6, y + 0.6)
                    g.stroke()
                } else if st == .red || sin(sim.pulse * 9) > 0 {
                    g.fillStyle = "rgba(229, 72, 77, 0.35)"
                    g.beginPath(); g.arc(x, y, 6, 0, .pi * 2); g.fill()
                    g.fillStyle = "#ff4d52"
                    g.roundRect(x - 2.9, y - 3.4, 5.8, 6.8, 2); g.fill()
                }
            }
        }
    }

    private func drawPeds(_ g: Canvas) {
        let showAngry = sim.freeplay == nil
        for ped in sim.peds {
            let crossing = ped.state == .crossing
            let arriving = ped.state == .arriving || ped.state == .leaving
            let cw = geo.crosswalks[ped.crosswalk]
            let at: Vec
            let ang: Double
            if arriving {
                let walk = ped.route.point(at: ped.routeAt)
                at = walk.position
                ang = walk.angle
            } else {
                at = crossing ? cw.point(ped.v, ped.du) : cw.point(ped.waitV, ped.du * 0.7)
                let r = cw.leg.right
                ang = atan2(r.y * ped.dir, r.x * ped.dir)
            }
            g.save()
            g.translate(at.x, at.y)
            g.rotate(ang)
            if crossing || arriving {
                let swing = CGFloat(sin(ped.phase) * 2.2)
                g.strokeStyle = "#2a2622"; g.lineWidth = 2
                g.beginPath(); g.moveTo(0, -1.8); g.lineTo(swing * 1.3, -1.8); g.moveTo(0, 1.8); g.lineTo(-swing * 1.3, 1.8); g.stroke()
            }
            g.fillStyle = "rgba(0, 0, 0, 0.3)"
            g.beginPath(); g.ellipse(1, 1, 3.3, 5); g.fill()
            g.fillStyle = ped.color
            g.beginPath(); g.ellipse(0, 0, 3.3, 5); g.fill()
            g.fillStyle = "#3a2e26"
            g.beginPath(); g.arc(0.3, 0, 2.4, 0, .pi * 2); g.fill()
            g.restore()
            if showAngry && ped.state == .waiting && ped.wait > sim.level.angry && sin(sim.pulse * 10) > -0.3 {
                g.fillStyle = "#ff4d4f"
                g.font = "800 10px Archivo"
                g.textAlign = "center"; g.textBaseline = "middle"
                g.fillText("!", at.x, at.y - 8)
            }
        }
    }

    private func drawCarBody(_ g: Canvas, _ x: Double, _ y: Double, _ angle: Double, _ c: CarLook, _ wrecked: Bool) {
        g.save()
        g.translate(x, y)
        g.rotate(angle)
        let L = CGFloat(c.len), Wd = CGFloat(c.wid)
        g.fillStyle = "rgba(0, 0, 0, 0.3)"
        g.roundRect(-L / 2 + 2, -Wd / 2 + 2, L, Wd, 4); g.fill()
        g.fillStyle = c.color
        g.roundRect(-L / 2, -Wd / 2, L, Wd, c.truck ? 2 : 5); g.fill()
        if c.truck {
            g.fillStyle = "rgba(0, 0, 0, 0.18)"
            g.fillRect(-L / 2 + 2, -Wd / 2 + 2, L - 14, Wd - 4)
            g.fillStyle = "#2a3a4a"
            g.fillRect(L / 2 - 8, -Wd / 2 + 2, 4, Wd - 4)
        } else {
            g.fillStyle = "#26323e"
            g.fillRect(L * 0.1, -Wd / 2 + 2, L * 0.18, Wd - 4)
            g.fillRect(-L * 0.36, -Wd / 2 + 2.5, L * 0.12, Wd - 5)
        }
        if let em = c.emergency, !wrecked {
            g.fillStyle = em.stripe
            g.fillRect(-L / 2 + 3, -Wd / 2 + 0.5, L - 6, 2.2)
            g.fillRect(-L / 2 + 3, Wd / 2 - 2.7, L - 6, 2.2)
            let on = sin(sim.pulse * 16) > 0
            g.fillStyle = on ? "#ff3b3b" : "#5a1414"
            g.fillRect(-2.5, -Wd / 2 + 2, 5, Wd / 2 - 2)
            g.fillStyle = on ? "#1e3a8a" : "#3b82ff"
            g.fillRect(-2.5, 0, 5, Wd / 2 - 2)
        }
        if wrecked {
            g.fillStyle = "rgba(20, 20, 20, 0.45)"
            g.roundRect(-L / 2, -Wd / 2, L, Wd, 4); g.fill()
            g.strokeStyle = "rgba(255, 255, 255, 0.5)"
            g.lineWidth = 1.2
            g.beginPath()
            g.moveTo(L / 2 - 6, -Wd / 2 + 1); g.lineTo(L / 2 - 2, -2); g.lineTo(L / 2 - 7, 2); g.lineTo(L / 2 - 3, Wd / 2 - 1)
            g.stroke()
        } else if c.slow {
            g.fillStyle = "#ff3b3b"
            g.fillRect(-L / 2, -Wd / 2 + 1, 2, 3)
            g.fillRect(-L / 2, Wd / 2 - 4, 2, 3)
        }
        g.restore()
    }

    private lazy var sharedLanes: (level: String, lanes: Set<String>) = (sim.level.name, geo.sharedLanes)

    private func sharedLane(_ laneKey: String) -> Bool {
        if sharedLanes.level != "\(sim.levelIndex)/\(sim.level.name)" {
            sharedLanes = ("\(sim.levelIndex)/\(sim.level.name)", geo.sharedLanes)
        }
        return sharedLanes.lanes.contains(laneKey)
    }

    private func drawDriverMarks(_ g: Canvas, _ c: Car) {
        let p = c.path
        let pose = p.point(at: c.s - c.len / 2)
        let at = pose.position
        let fwd = Vec(cos(pose.angle), sin(pose.angle))
        let side = Vec(-fwd.y, fwd.x)
        if underOverpass(at.x, at.y) { return }

        if c.emergency != nil {
            let k = (sim.pulse * 1.6).truncatingRemainder(dividingBy: 1)
            g.strokeStyle = Int(floor(sim.pulse * 3.2)) % 2 != 0 ? "rgba(59, 130, 255, \(1 - k))" : "rgba(255, 59, 59, \(1 - k))"
            g.lineWidth = 2
            g.beginPath(); g.arc(at.x, at.y, c.len / 2 + 4 + k * 22, 0, .pi * 2); g.stroke()
            if let em = sim.pendingEmergency, em.car === c, let limit = em.limit {
                let left = max(0, 1 - em.held / limit)
                g.lineWidth = 3
                g.strokeStyle = "rgba(0, 0, 0, 0.5)"
                g.beginPath(); g.arc(at.x, at.y, c.len / 2 + 3, 0, .pi * 2); g.stroke()
                g.strokeStyle = left > 0.4 ? "#f2f6f3" : left > 0 ? "#f2a91f" : "#ff4d4f"
                g.beginPath(); g.arc(at.x, at.y, c.len / 2 + 3, -.pi / 2, -.pi / 2 + (left != 0 ? left : 1) * .pi * 2); g.stroke()
            }
        }

        let nearLine = c.s < p.A && p.stopS - c.s < 170
        let turnSide: Double = (p.move == "L" || p.move == "R") && nearLine && sharedLane(p.laneKey) ? (p.move == "L" ? -1 : 1)
            : p.merges && c.s > p.exitStart - 30 && c.s < p.mergeAt + 30 ? Double(p.mergeSide) : 0
        if turnSide != 0 && options.turnSignals {
            let b = 0.5 + 0.5 * sin((sim.pulse + Double(c.id) * 0.37) * 6.3)
            if b > 0.35 {
                for f in [1.0, -1.0] {
                    let x = at.x + fwd.x * f * (c.len / 2 - 1.5) + side.x * turnSide * (c.wid / 2 - 0.5)
                    let y = at.y + fwd.y * f * (c.len / 2 - 1.5) + side.y * turnSide * (c.wid / 2 - 0.5)
                    g.fillStyle = "rgba(255, 170, 40, \(0.25 * b))"
                    g.beginPath(); g.arc(x, y, 5, 0, .pi * 2); g.fill()
                    g.fillStyle = "rgba(255, 178, 46, \(0.55 + 0.45 * b))"
                    g.beginPath(); g.arc(x, y, 2.6, 0, .pi * 2); g.fill()
                }
            }
        }

        if c.beater && c.s < p.exitStart + c.len {
            if c.racing {
                g.strokeStyle = "rgba(242, 169, 31, 0.8)"
                g.lineWidth = 1.6
                for o in [-5.0, 0, 5] {
                    let bx = at.x - fwd.x * (c.len / 2 + 3) + side.x * o, by = at.y - fwd.y * (c.len / 2 + 3) + side.y * o
                    let ln = 8 + Double.random(in: 0..<1, using: &shakeRandom) * 8
                    g.beginPath(); g.moveTo(bx, by); g.lineTo(bx - fwd.x * ln, by - fwd.y * ln); g.stroke()
                }
            }
            let pulse = c.racing ? 1 : 0.7 + 0.3 * sin(sim.pulse * 6)
            g.save()
            g.translate(at.x, at.y); g.rotate(pose.angle)
            g.strokeStyle = "rgba(242, 169, 31, \(pulse))"
            g.lineWidth = 2
            g.roundRect(-c.len / 2 - 3, -c.wid / 2 - 3, c.len + 6, c.wid + 6, 6); g.stroke()
            g.restore()
            let bx = at.x + side.x * -(c.wid / 2 + 10), by = at.y + side.y * -(c.wid / 2 + 10)
            g.fillStyle = "#161b21"
            g.beginPath(); g.arc(bx, by, 8.5, 0, .pi * 2); g.fill()
            g.strokeStyle = "rgba(242, 169, 31, \(pulse))"
            g.lineWidth = 1.5
            g.stroke()
            g.fillStyle = "rgba(242, 169, 31, \(pulse))"
            g.beginPath()
            g.moveTo(bx + 1.4, by - 6); g.lineTo(bx - 3.6, by + 0.7); g.lineTo(bx - 0.3, by + 0.7)
            g.lineTo(bx - 1.4, by + 6); g.lineTo(bx + 3.6, by - 0.7); g.lineTo(bx + 0.3, by - 0.7)
            g.closePath(); g.fill()
        }

        if c.hold <= 0 { return }
        if c.holdKind == "distracted" {
            let x = at.x + side.x * -(c.wid / 2 + 12), y = at.y + side.y * -(c.wid / 2 + 12) - 4
            g.fillStyle = "rgba(0, 0, 0, 0.35)"
            g.roundRect(x - 11, y - 6, 24, 15, 7); g.fill()
            g.fillStyle = "#e8edf2"
            g.roundRect(x - 12, y - 8, 24, 15, 7); g.fill()
            g.beginPath(); g.arc(x - 6, y + 9, 2.2, 0, .pi * 2); g.fill()
            g.fillStyle = "#161b21"
            for dx in [-5.0, 0, 5] { g.beginPath(); g.arc(x + dx, y - 0.5, 1.7, 0, .pi * 2); g.fill() }
        } else if (c.holdKind == "stall" || c.holdKind == "bump" || c.holdKind == "hit") && sin(sim.pulse * 12) > 0 {
            g.fillStyle = "#ffb02e"
            for f in [-1.0, 1] {
                for sd in [-1.0, 1] {
                    let x = at.x + fwd.x * f * (c.len / 2 - 1) + side.x * sd * (c.wid / 2 - 1)
                    let y = at.y + fwd.y * f * (c.len / 2 - 1) + side.y * sd * (c.wid / 2 - 1)
                    g.beginPath(); g.arc(x, y, 3.2, 0, .pi * 2); g.fill()
                }
            }
        }
    }

    private func drawWaitRing(_ g: Canvas, _ c: Car) {
        if sim.freeplay != nil { return }
        let angryAfter = sim.level.angry
        if c.lightWait <= angryAfter * 0.3 || c.s > c.path.stopS + 1 { return }
        let at = c.path.point(at: c.s - c.len / 2).position
        if underOverpass(at.x, at.y) { return }
        let frac = min(1, c.lightWait / angryAfter)
        g.lineWidth = 2.5
        g.strokeStyle = "rgba(0, 0, 0, 0.45)"
        g.beginPath(); g.arc(at.x, at.y, 8, 0, .pi * 2); g.stroke()
        g.strokeStyle = frac >= 1 ? "#ff4d4f" : frac > 0.6 ? "#f2a91f" : "#e8edf2"
        g.beginPath(); g.arc(at.x, at.y, 8, -.pi / 2, -.pi / 2 + frac * .pi * 2); g.stroke()
        if frac >= 1 && sin(sim.pulse * 10) > -0.3 {
            g.fillStyle = "#ff4d4f"
            g.font = "700 12px Archivo"
            g.textAlign = "center"; g.textBaseline = "middle"
            g.fillText("!", at.x, at.y + 1)
        }
    }

    // MARK: Effects and messages

    private func drawEffects(_ g: Canvas) {
        for p in sim.particles {
            let k = 1 - p.life / p.max
            switch p.kind {
            case .smoke:
                let r = 5 + (p.life / p.max) * 16
                g.fillStyle = "rgba(60, 64, 70, \(0.45 * k))"
                g.beginPath(); g.arc(p.x, p.y, r, 0, .pi * 2); g.fill()
            case .spark:
                g.strokeStyle = "rgba(255, \(190 + Int((60 * k).rounded())), 90, \(k))"
                g.lineWidth = 1.6
                g.beginPath(); g.moveTo(p.x, p.y); g.lineTo(p.x - p.velocity.x * 0.04, p.y - p.velocity.y * 0.04); g.stroke()
            case .debris:
                g.save()
                g.globalAlpha = min(1, k * 2)
                g.translate(p.x, p.y); g.rotate(p.rot ?? 0)
                g.fillStyle = p.color
                g.fillRect(-p.size / 2, -p.size / 2, p.size, p.size)
                g.restore()
            }
        }
        for fl in sim.flashes {
            let isBump = fl.kind == "bump"
            let label = fl.kind == "hit" ? "PEDESTRIAN HIT" : isBump ? "BUMP" : "CRASH"
            if !isBump && fl.t < 0.3 {
                let k = fl.t / 0.3
                g.fillStyle = "rgba(255, 244, 214, \(0.85 * (1 - k)))"
                g.beginPath(); g.arc(fl.x, fl.y, 10 + k * 40, 0, .pi * 2); g.fill()
            }
            let pop = min(1, fl.t / 0.15)
            let alpha = fl.t > 1 ? 1 - (fl.t - 1) / 0.4 : 1
            g.save()
            g.globalAlpha = CGFloat(max(0, alpha))
            g.translate(fl.x, fl.y - 30 - fl.t * 10)
            g.scale(0.6 + 0.4 * pop, 0.6 + 0.4 * pop)
            g.font = "800 \(label == "CRASH" ? 22 : label == "BUMP" ? 10 : 15)px Archivo"
            g.textAlign = "center"; g.textBaseline = "middle"
            g.lineWidth = 4
            g.strokeStyle = "#161b21"
            g.strokeText(label, 0, 0)
            g.fillStyle = isBump ? "#f2a91f" : "#e5484d"
            g.fillText(label, 0, 0)
            g.restore()
        }
    }

    private func drawEmergencyWarning(_ g: Canvas) {
        guard let em = sim.emergency, em.phase == .warn else { return }
        let k = em.dir, d = k.heading, r = k.right
        let u = -(d.x != 0 ? viewW / 2 : World.half) + 62, v = geo.legRight(k) / 2
        let x = World.cx + d.x * u + r.x * v, y = World.cy + d.y * u + r.y * v
        let red = Int(floor(sim.pulse * 4)) % 2 == 0
        g.save()
        g.translate(x, y)
        g.fillStyle = "rgba(14, 16, 20, 0.88)"
        g.roundRect(-38, -27, 76, 54, 10); g.fill()
        g.strokeStyle = red ? "#ff3b3b" : "#3b82ff"; g.lineWidth = 3
        g.roundRect(-38, -27, 76, 54, 10); g.stroke()
        g.save()
        g.rotate(atan2(d.y, d.x))
        g.fillStyle = red ? "#ff3b3b" : "#3b82ff"
        g.beginPath(); g.moveTo(14, 0); g.lineTo(2, -9); g.lineTo(2, -4); g.lineTo(-12, -4); g.lineTo(-12, 4); g.lineTo(2, 4); g.lineTo(2, 9); g.closePath(); g.fill()
        g.restore()
        g.fillStyle = "#f2f6f3"
        g.font = "7px \"Press Start 2P\""
        g.textAlign = "center"; g.textBaseline = "middle"
        g.fillText(em.kind.name.uppercased(), 0, -17)
        g.font = "14px VT323"
        g.fillText("\(max(0, Int(ceil(em.spawnAt - sim.t))))s", 0, 18)
        g.restore()
    }

    private func drawBacklog(_ g: Canvas) {
        for k in Direction.allCases {
            let backlog = sim.backlog(k)
            if !backlog.blocked || backlog.waiting == 0 { continue }
            let d = k.heading, r = k.right
            let u = -(d.x != 0 ? viewW / 2 : World.half) + 44, v = geo.legRight(k) / 2
            let x = CGFloat(World.cx + d.x * u + r.x * v), y = CGFloat(World.cy + d.y * u + r.y * v)
            g.globalAlpha = CGFloat(0.55 + 0.45 * sin(sim.pulse * 8))
            g.fillStyle = "#e5484d"
            g.roundRect(x - 15, y - 9, 30, 18, 4); g.fill()
            g.globalAlpha = 1
            g.fillStyle = "#fff"
            g.font = "15px VT323"
            g.textAlign = "center"; g.textBaseline = "middle"
            g.fillText("+\(backlog.waiting)", x, y + 1)
        }
    }

    private func drawScorePopups(_ g: Canvas) {
        g.textAlign = "center"; g.textBaseline = "middle"
        for p in sim.popups {
            let life = p.big ? 1.4 : 0.9
            let k = p.t / life
            g.globalAlpha = CGFloat(k < 0.7 ? 1 : 1 - (k - 0.7) / 0.3)
            g.font = "\(p.big ? 11 : 8)px \"Press Start 2P\""
            let y = p.y - 6 - k * 22
            g.lineWidth = 3; g.strokeStyle = "rgba(22, 27, 33, 0.9)"
            g.strokeText(p.text, p.x, y)
            g.fillStyle = p.color
            g.fillText(p.text, p.x, y)
        }
        g.globalAlpha = 1
        guard let b = sim.banners.first else { return }
        let pop = min(1, b.t / 0.18)
        let alpha = b.t > 1.4 ? 1 - (b.t - 1.4) / 0.4 : 1
        g.save()
        g.globalAlpha = CGFloat(max(0, alpha))
        g.translate(CX, CY)
        g.scale(0.7 + 0.3 * pop, 0.7 + 0.3 * pop)
        g.font = "10px \"Press Start 2P\""
        var w = g.measureText(b.text) + 28
        g.fillStyle = "rgba(22, 27, 33, 0.88)"
        g.strokeStyle = b.color; g.lineWidth = 2
        if w > CGFloat(viewW) - 24, let cut = b.text.range(of: " · ") {
            let head = String(b.text[..<cut.lowerBound]), rest = String(b.text[cut.upperBound...])
            let hw = g.measureText(head)
            g.font = "17px VT323"
            w = max(hw, g.measureText(rest)) + 32
            g.roundRect(-w / 2, -24, w, 48, 14); g.fill()
            g.roundRect(-w / 2, -24, w, 48, 14); g.stroke()
            g.fillStyle = b.color
            g.fillText(rest, 0, 11)
            g.font = "10px \"Press Start 2P\""
            g.fillText(head, 0, -9)
        } else {
            g.roundRect(-w / 2, -16, w, 32, 16); g.fill()
            g.roundRect(-w / 2, -16, w, 32, 16); g.stroke()
            g.fillStyle = b.color
            g.fillText(b.text, 0, 1)
        }
        g.restore()
    }

    private func drawStreetSigns(_ g: Canvas) {
        let parts = sim.level.street.components(separatedBy: " & ")
        let ns = (parts.first ?? "").uppercased(), ew = (parts.count > 1 ? parts[1] : "").uppercased()
        g.font = "800 12px Archivo"
        func plate(_ text: String, _ x: CGFloat, _ y: CGFloat, _ anchor: String) {
            let w = g.measureText(text) + 16, h: CGFloat = 20
            let x0 = anchor == "left" ? x : anchor == "right" ? x - w : x - w / 2, y0 = y - h / 2
            let mid = x0 + w / 2
            g.fillStyle = "rgba(0, 0, 0, 0.35)"
            g.roundRect(x0 + 2, y0 + 2, w, h, 3); g.fill()
            g.fillStyle = "#1d6b46"
            g.roundRect(x0, y0, w, h, 3); g.fill()
            g.strokeStyle = "rgba(232, 241, 234, 0.8)"
            g.lineWidth = 1
            g.roundRect(x0 + 2, y0 + 2, w - 4, h - 4, 2); g.stroke()
            g.fillStyle = "#f2f6f3"
            g.textAlign = "center"; g.textBaseline = "middle"
            g.fillText(text, mid, y + 1)
        }
        let b = geo.box
        plate(ns, CGFloat(b.x0 + b.x1) / 2, geo.hasLeg(.S) ? 16 : H - 16, "center")
        if geo.hasLeg(.E) {
            plate(ew, CGFloat(viewX0) + 8, CGFloat(b.y0 + b.y1) / 2, "left")
        } else {
            plate(ew, CGFloat(viewX0 + viewW) - 8, CGFloat(b.y0 + b.y1) / 2, "right")
        }
    }

    // MARK: Overpass and night

    private struct OverpassCar { let x, y, angle: Double; let color: String }

    private func overpassCars(_ clock: Double) -> [OverpassCar] {
        let lanes: [(east: Bool, speed: Double, offsets: [Double])] = [
            (true, 84, [0, 150, 330, 455, 640]),
            (false, 74, [60, 250, 370, 560, 700]),
        ]
        let span = World.width + 160
        let colors = ["#e8eef3", "#2c3e57", "#b8372f", "#d6a12b", "#4c7a5a", "#8a96a3", "#1f2328", "#3d6fb0", "#c96b2c"]
        var cars: [OverpassCar] = []
        for (li, lane) in lanes.enumerated() {
            for (i, off) in lane.offsets.enumerated() {
                var x = (clock * lane.speed + off).truncatingRemainder(dividingBy: span) - 80
                if !lane.east { x = World.width - x }
                let y = Double(overpassY) + (lane.east ? Double(overpassH) * 0.72 : Double(overpassH) * 0.28)
                cars.append(OverpassCar(x: x, y: y, angle: lane.east ? 0 : .pi, color: colors[(li * 5 + i * 3) % colors.count]))
            }
        }
        return cars
    }

    private func drawOverpassTraffic(_ g: Canvas, _ clock: Double) {
        for c in overpassCars(clock) {
            drawCarBody(g, c.x, c.y, c.angle, CarLook(len: 24, wid: 13, color: c.color, truck: false, emergency: nil, slow: false), false)
        }
    }

    /// A headlight cone pointing along +x from (8, 48), and a round glow, drawn once.
    private lazy var lightSprites: (cone: CGImage, glow: CGImage) = {
        let cone = Canvas.offscreen(96, 96)
        cone.setFill(.radial(Canvas.radialGradient([(0, "rgba(0,0,0,0.85)"), (1, "rgba(0,0,0,0)")]), CGPoint(x: 8, y: 48), 2, CGPoint(x: 8, y: 48), 86))
        cone.beginPath(); cone.moveTo(8, 48); cone.arc(8, 48, 86, -0.42, 0.42); cone.closePath(); cone.fill()
        cone.setFill(.radial(Canvas.radialGradient([(0, "rgba(0,0,0,0.6)"), (1, "rgba(0,0,0,0)")]), CGPoint(x: 8, y: 48), 0, CGPoint(x: 8, y: 48), 14))
        cone.beginPath(); cone.arc(8, 48, 14, 0, .pi * 2); cone.fill()
        let glow = Canvas.offscreen(64, 64)
        glow.setFill(.radial(Canvas.radialGradient([(0, "rgba(0,0,0,1)"), (1, "rgba(0,0,0,0)")]), CGPoint(x: 32, y: 32), 0, CGPoint(x: 32, y: 32), 32))
        glow.fillRect(0, 0, 64, 64)
        return (cone.ctx.makeImage()!, glow.ctx.makeImage()!)
    }()

    private static let nightRes: CGFloat = 3

    /// Night: darken the map, then cut out light from streetlights, signals and headlights.
    private func drawNight(_ g: Canvas, scale: CGFloat, pixelScale: CGFloat, size: CGSize, clock: Double) {
        let dw = Int(ceil(size.width * pixelScale / Self.nightRes)), dh = Int(ceil(size.height * pixelScale / Self.nightRes))
        let n = Canvas.offscreen(dw, dh)
        n.fillStyle = "rgba(5, 9, 20, 0.82)"
        n.fillRect(0, 0, CGFloat(dw), CGFloat(dh))
        let s = scale * pixelScale / Self.nightRes
        n.setTransform(s, 0, 0, s, -CGFloat(viewX0) * s, 0)
        n.globalCompositeOperation = "destination-out"
        let sprites = lightSprites
        func glow(_ x: Double, _ y: Double, _ r: Double, _ a: Double) {
            n.globalAlpha = CGFloat(a)
            n.drawImage(sprites.glow, x - r, y - r, r * 2, r * 2)
            n.globalAlpha = 1
        }
        let b = geo.box
        for (x, y) in [(b.x0 - 10, b.y0 - 10), (b.x1 + 10, b.y0 - 10), (b.x0 - 10, b.y1 + 10), (b.x1 + 10, b.y1 + 10)] { glow(x, y, 85, 0.85) }
        for lamp in geo.lamps { glow(lamp.position.x, lamp.position.y, 16, 0.9) }
        for c in sim.cars where c.emergency != nil {
            let at = c.path.point(at: c.s - c.len / 2).position
            if !underOverpass(at.x, at.y) { glow(at.x, at.y, 46, 0.55 + 0.3 * sin(sim.pulse * 16)) }
        }
        for c in sim.cars {
            let pose = c.path.point(at: c.s - c.len / 2)
            let fx = pose.position.x + cos(pose.angle) * c.len / 2, fy = pose.position.y + sin(pose.angle) * c.len / 2
            if underOverpass(fx, fy) { continue }
            n.save()
            n.translate(fx, fy)
            n.rotate(pose.angle)
            n.drawImage(sprites.cone, -8, -48)
            n.restore()
        }
        if hasDecor("overpass") {
            n.globalCompositeOperation = "source-over"
            n.clearRect(0, overpassY, W, overpassH)
            n.fillStyle = "rgba(5, 9, 20, 0.82)"
            n.fillRect(0, overpassY, W, overpassH)
            n.globalCompositeOperation = "destination-out"
            n.save()
            n.beginPath(); n.rect(0, overpassY, W, overpassH); n.clip()
            for c in overpassCars(clock) {
                n.save()
                n.translate(c.x + cos(c.angle) * 12, c.y)
                n.rotate(c.angle)
                n.drawImage(sprites.cone, -8, -48)
                n.restore()
            }
            n.restore()
        }
        if let image = n.ctx.makeImage() {
            g.save()
            g.setTransform(1, 0, 0, 1, 0, 0)
            g.ctx.interpolationQuality = .high
            g.drawImage(image, 0, 0, size.width, size.height)
            g.restore()
        }
        for c in sim.cars {
            let pose = c.path.point(at: c.s - c.len / 2)
            let fx = cos(pose.angle), fy = sin(pose.angle), sx = -fy, sy = fx
            for side in [-1.0, 1] {
                let hx = pose.position.x + fx * c.len / 2 + sx * side * (c.wid / 2 - 3)
                let hy = pose.position.y + fy * c.len / 2 + sy * side * (c.wid / 2 - 3)
                let tx = pose.position.x - fx * c.len / 2 + sx * side * (c.wid / 2 - 3)
                let ty = pose.position.y - fy * c.len / 2 + sy * side * (c.wid / 2 - 3)
                if !underOverpass(hx, hy) {
                    g.fillStyle = "#fff6d6"
                    g.beginPath(); g.arc(hx, hy, 1.8, 0, .pi * 2); g.fill()
                }
                if !underOverpass(tx, ty) {
                    g.fillStyle = c.v < c.topSpeed * 0.5 ? "#ff3b3b" : "#a32020"
                    g.beginPath(); g.arc(tx, ty, 1.6, 0, .pi * 2); g.fill()
                }
            }
        }
    }
}
