import GridlockCore
import GridlockRender
import SwiftUI
import UIKit

// MARK: - The board

/// Draws the board every display frame (and drives the simulation from the same clock).
/// Stops redrawing once nothing on it moves (paused, results) to save battery.
final class BoardUIView: UIView {
    weak var game: NativeGame?
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var stillDrawn: ObjectIdentifier?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        backgroundColor = UIColor(red: 22 / 255, green: 27 / 255, blue: 33 / 255, alpha: 1)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        link?.invalidate()
        link = nil
        guard let window = window else { return }
        // Like the web game: at most 2x, plenty for soft night light and pixel text.
        contentScaleFactor = min(window.screen.scale, 2)
        let l = CADisplayLink(target: self, selector: #selector(frameTick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
        last = 0
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        stillDrawn = nil
        setNeedsDisplay()
    }

    @objc private func frameTick(_ l: CADisplayLink) {
        let dt = last == 0 ? 1.0 / 60 : l.timestamp - last
        last = l.timestamp
        guard let game = game else { return }
        game.tick(dt, now: l.timestamp)
        guard let sim = game.sim else { return }
        let still = sim.mode != .running && (sim.mode == .paused || (sim.wrecks.isEmpty && sim.particles.isEmpty && sim.popups.isEmpty && sim.banners.isEmpty && sim.shake <= 0))
        if still && stillDrawn == ObjectIdentifier(sim) { return }
        stillDrawn = still ? ObjectIdentifier(sim) : nil
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let renderer = game?.renderer else { return }
        renderer.render(in: ctx, size: bounds.size, pixelScale: contentScaleFactor, clock: CACurrentMediaTime())
    }
}

struct BoardView: UIViewRepresentable {
    let game: NativeGame

    func makeUIView(context: Context) -> BoardUIView {
        let v = BoardUIView()
        v.game = game
        return v
    }

    func updateUIView(_ uiView: BoardUIView, context: Context) { uiView.game = game }
}

// MARK: - Fitting the board and the signal sets

/// How the board and its signal sets fit a space: the visible width of the board (map units),
/// the button size and whether sets stack in a column. A port of arrangeSignals() in game.js.
struct BoardFit: Equatable {
    var viewW: Double
    var button: CGFloat
    var column: Bool
    var boardSize: CGSize

    static func estimateSize(_ head: ControlLayout.Head, button: CGFloat, column: Bool) -> CGSize {
        let n = CGFloat(head.carGroups.count + head.walkGroups.count)
        let gap: CGFloat = 5, pad: CGFloat = 4 + 2
        let buttons = n * button + max(0, n - 1) * gap + pad * 2
        let label: CGFloat = column ? 70 : 110
        if column { return CGSize(width: max(button + pad * 2, label), height: buttons + 2 * 22 + 6) }
        return CGSize(width: max(buttons, label), height: button + pad * 2 + 2 * 22 + 6)
    }

    static func compute(available: CGSize, layout: ControlLayout, bigButtons: Bool) -> BoardFit {
        let W = World.width, H = World.height
        let availW = Double(available.width), availH = Double(available.height)
        guard availW > 0, availH > 0 else { return BoardFit(viewW: W, button: 44, column: false, boardSize: available) }
        let aspectView = min(W, W * availW / availH)
        let portrait = availH > availW
        var best: BoardFit?
        var size: CGFloat = bigButtons ? 56 : 44
        while size >= 30 && best == nil {
            for column in portrait ? [false, true] : [false] {
                // Board pixels across for a view v map units wide, filling the height when it can.
                func boardW(_ v: Double) -> Double { min(availW, availH * v / H) }
                var need = 0.0
                for head in layout.heads {
                    let w = Double(estimateSize(head, button: size, column: column).width)
                    let bw = boardW(aspectView)
                    let room = bw / 2 - w - 10
                    need = max(need, room > 0 ? abs(head.anchor.x - World.cx) * bw / room : .infinity)
                }
                let v = max(BoardRendererMinView.value, aspectView, need)
                if v > W + 0.5 { continue }
                let ppu = min(availW / v, availH / H)
                let tall = layout.heads.contains { head in
                    abs(head.anchor.y - World.cy) * ppu + Double(estimateSize(head, button: size, column: column).height) + 8 > (H / 2) * ppu
                }
                if tall { continue }
                if best == nil || v < best!.viewW - 1 {
                    best = BoardFit(viewW: v, button: size, column: column, boardSize: CGSize(width: v * ppu, height: H * ppu))
                }
            }
            size -= 2
        }
        if let best = best { return best }
        let ppu = min(availW / W, availH / H)
        return BoardFit(viewW: W, button: 30, column: false, boardSize: CGSize(width: W * ppu, height: H * ppu))
    }
}

enum BoardRendererMinView { static let value = 400.0 }

/// Places each signal set at its corner, hanging right/left and down/up from the anchor.
struct AnchorLayout: Layout {
    struct Anchor: LayoutValueKey {
        static let defaultValue = (point: CGPoint.zero, right: true, down: true)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for v in subviews {
            let a = v[Anchor.self]
            let size = v.sizeThatFits(.unspecified)
            let x = a.right ? a.point.x + 6 : a.point.x - size.width - 6
            let y = a.down ? a.point.y + 6 : a.point.y - size.height - 6
            v.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(size))
        }
    }
}

// MARK: - Signal buttons

/// The arrow glyphs on the buttons, from the web game's SVGs (20 × 20 box).
struct GlyphShape: Shape {
    let kind: String

    func path(in rect: CGRect) -> Path {
        let s = rect.width / 20
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        switch kind {
        case "L":
            path.move(to: p(14, 17)); path.addLine(to: p(14, 11))
            path.addQuadCurve(to: p(11, 8), control: p(14, 8))
            path.addLine(to: p(5, 8))
            path.move(to: p(8.5, 4.5)); path.addLine(to: p(5, 8)); path.addLine(to: p(8.5, 11.5))
        case "A":
            path.move(to: p(12, 17)); path.addLine(to: p(12, 4))
            path.move(to: p(8, 8)); path.addLine(to: p(12, 4)); path.addLine(to: p(16, 8))
            path.move(to: p(12, 13)); path.addLine(to: p(6, 13))
            path.move(to: p(8.5, 10.5)); path.addLine(to: p(6, 13)); path.addLine(to: p(8.5, 15.5))
        case "walk":
            path.move(to: p(10.5, 7.5)); path.addLine(to: p(9, 12.5)); path.addLine(to: p(6, 17.5))
            path.move(to: p(9, 12.5)); path.addLine(to: p(12.5, 14.5)); path.addLine(to: p(13.5, 18))
            path.move(to: p(6, 10.5)); path.addLine(to: p(10.5, 7.5)); path.addLine(to: p(13.5, 11)); path.addLine(to: p(16.5, 12))
        default:
            path.move(to: p(10, 17)); path.addLine(to: p(10, 4))
            path.move(to: p(5, 9)); path.addLine(to: p(10, 4)); path.addLine(to: p(15, 9))
        }
        return path
    }
}

struct SignalButton: View {
    @ObservedObject var game: NativeGame
    let group: Int
    let dir: Direction
    let size: CGFloat

    var body: some View {
        let sim = game.sim!
        let g = sim.groups[group]
        let walk = g.kind == .walk
        let live = sim.mode == .running && sim.failAt == nil
        let unsafe = live && g.light == .red && sim.isUnsafe(group)
        let count = game.setting("counts") ? (game.monitor.corners[dir]?.groups[group] ?? 0) : 0
        let emergency = game.monitor.emergencyGroups.contains(group) && game.monitor.corners[dir]?.emergency == true
        let fill: Color = g.light == .green ? Pixel.go : g.light == .yellow ? Pixel.yellow : Pixel.stop
        let rotations: [Direction: Double] = [.N: 0, .E: 90, .S: 180, .W: -90]
        let rotation = walk ? 0 : rotations[dir]!
        Button {
            game.toggle(group)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: walk ? 6 : size / 2)
                    .fill(fill)
                    .shadow(color: g.light == .red ? .clear : fill.opacity(0.75), radius: 7)
                RoundedRectangle(cornerRadius: walk ? 6 : size / 2)
                    .strokeBorder(Color(hex: 0x05040B), lineWidth: 3)
                ZStack {
                    GlyphShape(kind: walk ? "walk" : g.move)
                        .stroke(Color(hex: 0x05040B), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    if walk { Circle().fill(Color(hex: 0x05040B)).frame(width: size * 0.19, height: size * 0.19).offset(x: size * 0.075, y: -size * 0.32) }
                }
                .frame(width: size / 2, height: size / 2)
                .rotationEffect(.degrees(rotation))
                if game.setting("colorblind") { ColorBlindMark(light: g.light).frame(width: 9, height: 9).offset(x: size / 2 - 7, y: -size / 2 + 7) }
                if unsafe {
                    Text("!").font(Pixel.font(8)).foregroundColor(.white)
                        .frame(width: 16, height: 16).background(Pixel.stop).cornerRadius(2)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color(hex: 0x05040B), lineWidth: 1))
                        .offset(x: -size / 2 + 2, y: -size / 2 + 2)
                }
                if count > 0 {
                    Text("\(count)").font(Pixel.term(15)).foregroundColor(Color(hex: 0x05040B))
                        .frame(minWidth: 16, minHeight: 16).padding(.horizontal, 2).background(Pixel.text).cornerRadius(2)
                        .offset(x: size / 2 - 4, y: size / 2 - 4)
                }
            }
            .frame(width: size, height: size)
            .overlay(RoundedRectangle(cornerRadius: walk ? 9 : size / 2 + 3).stroke(Color.white, lineWidth: emergency ? 3 : 0).padding(-4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!live || g.light == .yellow)
        .accessibilityLabel(walk ? "Walk across \(g.label)" : "\(dir.name) \(g.move == "L" ? "left turn" : g.move == "A" ? "all lanes" : "straight and right")")
        .accessibilityValue(g.light == .green ? "Green" : g.light == .yellow ? "Yellow" : unsafe ? "Red, not safe yet" : "Red")
    }
}

/// Colour-blind setting: square on red, triangle on yellow, circle on green.
struct ColorBlindMark: View {
    let light: SignalGroup.Light

    var body: some View {
        switch light {
        case .red: Rectangle().fill(Color.white).overlay(Rectangle().stroke(Color.black, lineWidth: 1))
        case .yellow: Triangle().fill(Color.white).overlay(Triangle().stroke(Color.black, lineWidth: 1))
        case .green: Circle().fill(Color.white).overlay(Circle().stroke(Color.black, lineWidth: 1))
        }
    }
}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// One corner's set: the direction label (the busiest ★, the emergency flash), the buttons,
/// and the waiting monitor.
struct SignalSet: View {
    @ObservedObject var game: NativeGame
    let head: ControlLayout.Head
    let fit: BoardFit

    var body: some View {
        let corner = game.monitor.corners[head.dir] ?? CornerMonitor.Corner()
        let busiest = corner.busiest && game.setting("busiest")
        let emergency = corner.emergency
        let flash = Int(CACurrentMediaTime() * 2) % 2 == 0
        let arrows: [Direction: String] = [.N: "↑", .S: "↓", .E: "→", .W: "←"]
        let arrow = arrows[head.dir]!
        let name = fit.column ? head.dir.name.replacingOccurrences(of: "bound", with: "") : head.dir.name
        let label = HStack(spacing: 5) {
            Text("\(name.uppercased()) \(arrow)")
            if busiest {
                Text(fit.column ? "★" : "★ BUSIEST").padding(.horizontal, 3).background(Color(hex: 0x05040B)).foregroundColor(Pixel.yellow).cornerRadius(2)
            }
        }
        .font(Pixel.term(fit.column ? 15 : 17))
        .foregroundColor(emergency ? .white : busiest ? Color(hex: 0x05040B) : Pixel.yellow)
        .padding(.horizontal, 5).padding(.vertical, 1)
        .background(emergency ? Color(hex: 0xFF3B3B) : busiest ? Pixel.yellow : Color(hex: 0x0A0814).opacity(0.9))
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(emergency ? Color(hex: 0xFF3B3B) : busiest ? Pixel.yellow : Pixel.edge, lineWidth: 2))
        .cornerRadius(2)

        let groups = head.carGroups + head.walkGroups
        let buttons = Group {
            if fit.column {
                VStack(spacing: 5) { ForEach(groups, id: \.self) { SignalButton(game: game, group: $0, dir: head.dir, size: fit.button) } }
            } else {
                HStack(spacing: 5) { ForEach(groups, id: \.self) { SignalButton(game: game, group: $0, dir: head.dir, size: fit.button) } }
            }
        }
        .padding(4)
        .background(Color(hex: 0x0A0814).opacity(0.9))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(emergency ? (flash ? Color(hex: 0xFF3B3B) : Color(hex: 0x3B82FF)) : busiest ? Pixel.yellow : Pixel.edge, lineWidth: 2))
        .cornerRadius(4)
        .shadow(color: busiest ? Pixel.yellow.opacity(0.55) : .clear, radius: 8)

        let waitBg: Color = corner.level == "bad" ? Pixel.stop : corner.level == "warn" ? Pixel.yellow : Color(hex: 0x0A0814).opacity(0.9)
        let wait = Text("\(corner.total)\(corner.oldest >= 1 ? " · \(Int(corner.oldest))S" : "")")
            .font(Pixel.term(fit.column ? 15 : 17))
            .foregroundColor(corner.level == "bad" ? .white : corner.level == "warn" ? Color(hex: 0x05040B) : Pixel.text)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(waitBg)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(corner.level == "ok" ? Pixel.edge : waitBg, lineWidth: 2))
            .cornerRadius(2)
        let counts = game.setting("counts")

        VStack(alignment: head.extendsRight ? .leading : .trailing, spacing: 3) {
            if head.extendsDown {
                label
                buttons
                if counts { wait }
            } else {
                if counts { wait }
                buttons
                label
            }
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
    }
}

// MARK: - The game screen

struct NativeGameView: View {
    @ObservedObject var game: NativeGame
    @ObservedObject var session: BoardSession

    var body: some View {
        VStack(spacing: 0) {
            hud
            Rectangle().fill(Pixel.yellow.opacity(0.85)).frame(height: 3)
            GeometryReader { geo in
                if let layout = game.layout, game.sim != nil {
                    let fit = BoardFit.compute(available: geo.size, layout: layout, bigButtons: game.setting("bigButtons"))
                    let board = fit.boardSize
                    ZStack(alignment: .topLeading) {
                        BoardView(game: game)
                            .frame(width: board.width, height: board.height)
                        AnchorLayout {
                            ForEach(layout.heads, id: \.dir) { head in
                                let x = (head.anchor.x - (World.cx - fit.viewW / 2)) / fit.viewW * Double(board.width)
                                let y = head.anchor.y / World.height * Double(board.height)
                                SignalSet(game: game, head: head, fit: fit)
                                    .layoutValue(key: AnchorLayout.Anchor.self, value: (CGPoint(x: x, y: y), head.extendsRight, head.extendsDown))
                            }
                        }
                        .frame(width: board.width, height: board.height)
                        rushPill.frame(width: board.width, height: board.height, alignment: .bottom).padding(.bottom, 10)
                    }
                    .frame(width: board.width, height: board.height)
                    .clipped()
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            Rectangle().fill(Pixel.yellow.opacity(0.85)).frame(height: 3)
            dock
        }
        .background(Color(hex: 0x0A0814).ignoresSafeArea())
    }

    // MARK: HUD

    private var hud: some View {
        let sim = game.sim
        let fp = sim?.freeplay != nil
        return HStack(spacing: 10) {
            Button { game.togglePause() } label: {
                Image(systemName: sim?.mode == .paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundColor(Pixel.yellow)
                    .frame(width: 44, height: 44)
                    .background(Color(hex: 0x2A1840))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(sim?.mode != .running && sim?.mode != .paused)
            .accessibilityLabel(sim?.mode == .paused ? "Resume" : "Pause")
            VStack(alignment: .leading, spacing: 4) {
                Text(fp ? "FREEPLAY" : "\((sim?.levelIndex ?? 0) + 1). \((sim?.level.name ?? "").uppercased())")
                    .font(Pixel.font(8)).foregroundColor(Pixel.cyan).lineLimit(1).minimumScaleFactor(0.6)
                HStack(spacing: 6) {
                    Text(Self.format(sim?.score ?? 0)).font(Pixel.font(14)).foregroundColor(Pixel.yellow)
                        .shadow(color: Pixel.redShadow, radius: 0, x: 2, y: 2)
                    if let m = sim?.mult, m > 1 {
                        Text("×\(m == m.rounded() ? String(Int(m)) : String(m))").font(Pixel.font(8)).foregroundColor(Color(hex: 0x05040B))
                            .padding(.horizontal, 4).padding(.vertical, 3).background(Pixel.pink).cornerRadius(2)
                    }
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(fp ? "\(sim?.cleared ?? 0) CARS" : "\(min(sim?.cleared ?? 0, Int(sim?.level.goal ?? 0))) / \(Int(sim?.level.goal ?? 0))")
                    .font(Pixel.font(10)).foregroundColor(Pixel.cyan)
                Text(fp ? "CRASHES \(sim?.crashes ?? 0)" : "CRASHES \(sim?.crashes ?? 0) / \(Simulation.maxCrashes)")
                    .font(Pixel.term(17)).foregroundColor((sim?.crashes ?? 0) == 0 ? Pixel.dim : Pixel.stop)
                Text(NativeGame.time(sim?.t ?? 0)).font(Pixel.term(17)).foregroundColor(Pixel.dim)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(LinearGradient(colors: [Color(hex: 0x1A1438), Color(hex: 0x120F2A)], startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .top))
    }

    static func format(_ n: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: n.rounded())) ?? ""
    }

    @ViewBuilder private var rushPill: some View {
        if let sim = game.sim, let rush = sim.rush, sim.mode == .running {
            Text("RUSH: \(rush.dir.name.uppercased()) TRAFFIC")
                .font(Pixel.font(7)).foregroundColor(Color(hex: 0x05040B))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Pixel.pink).cornerRadius(2)
                .shadow(color: Pixel.pink.opacity(0.6), radius: 7)
                .allowsHitTesting(false)
        }
    }

    // MARK: Dock

    private var dock: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let sim = game.sim, let f = sim.freeplay {
                HStack {
                    Text("DENSITY").font(Pixel.font(7)).foregroundColor(Pixel.dim)
                    Slider(value: Binding(get: { Double(f.density) }, set: { game.setDensity(Int($0.rounded())) }), in: 1...10, step: 1)
                        .tint(Pixel.go)
                        .accessibilityLabel("Traffic density")
                        .accessibilityValue(PlayerData.densityName(f.density))
                    Text(PlayerData.densityName(f.density)).font(Pixel.term(18)).foregroundColor(Pixel.text).frame(minWidth: 90, alignment: .trailing)
                }
                Text("\(Simulation.flowStyles[f.flow]?.label ?? "Lively") flow · \(sim.flowLabel)".uppercased())
                    .font(Pixel.font(7)).foregroundColor(Pixel.cyan)
                let best = sim.bestKey.flatMap { game.store.bests[$0] } ?? PlayerData.Best(score: 0, cpm: 0)
                Text("\(sim.t < 30 ? "–" : String(format: "%.1f", sim.carsPerMinute))/min · best \(Self.format(best.score)) pts, \(String(format: "%.1f", best.cpm))/min")
                    .font(Pixel.term(18)).foregroundColor(Pixel.dim)
            } else if let sim = game.sim {
                bar(label: "GOAL", fraction: min(1, Double(sim.cleared) / sim.level.goal), color: Pixel.cyan, value: nil)
                let p = sim.patience
                bar(label: "PATIENCE", fraction: p / 100, color: p > 55 ? Pixel.go : p > 25 ? Pixel.yellow : Pixel.stop, value: "\(Int(p.rounded(.up)))%")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color(hex: 0x120F2A), Color(hex: 0x0A0814)], startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .bottom))
    }

    private func bar(label: String, fraction: Double, color: Color, value: String?) -> some View {
        HStack(spacing: 10) {
            Text(label).font(Pixel.font(7)).foregroundColor(Pixel.dim).frame(width: 74, alignment: .leading)
            GeometryReader { g in
                let segments = 24
                let filled = Int((Double(segments) * max(0, min(1, fraction))).rounded())
                HStack(spacing: 2) {
                    ForEach(0..<segments, id: \.self) { i in
                        Rectangle().fill(i < filled ? color : Color(hex: 0x24173A))
                    }
                }
                .frame(width: g.size.width, height: g.size.height)
            }
            .frame(height: 14)
            .padding(2)
            .overlay(Rectangle().stroke(Pixel.edge, lineWidth: 2))
            if let value = value { Text(value).font(Pixel.term(19)).foregroundColor(Pixel.text).frame(width: 44, alignment: .trailing) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.capitalized)
        .accessibilityValue(value ?? "\(Int(fraction * 100)) percent")
    }
}
