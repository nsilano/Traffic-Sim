import SwiftUI

// The Pixel City palette and fonts, matching style.css.
enum Pixel {
    static func font(_ size: CGFloat) -> Font { .custom("PressStart2P-Regular", size: size) }
    static func term(_ size: CGFloat) -> Font { .custom("VT323-Regular", size: size) }

    static let sky1 = Color(hex: 0x0A1030)
    static let sky2 = Color(hex: 0x1A1650)
    static let sky3 = Color(hex: 0x3B1D5E)
    static let ground = Color(hex: 0x0A0814)
    static let text = Color(hex: 0xF4ECFF)
    static let dim = Color(hex: 0xA99ED6)
    static let item = Color(hex: 0xC9C0EE)
    static let yellow = Color(hex: 0xFFD23F)
    static let redShadow = Color(hex: 0xB3161C)
    static let go = Color(hex: 0x2FFF86)
    static let stop = Color(hex: 0xFF4F5E)
    static let cyan = Color(hex: 0x5EF2FF)
    static let wire = Color(hex: 0x05060F)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// The native main menu: a night street in pixel art, a traffic light swaying on its
/// wire, and an arcade-style list. Choices go to the game through the bridge.
struct MenuView: View {
    @ObservedObject var bridge: GameHost
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected = 0
    /// The native screen open over the menu, if any: levels, records, settings, help or freeplay.
    @State private var screen: String?

    private struct Item: Identifiable {
        let id: String
        let label: String
        let note: String
    }

    private var items: [Item] {
        let s = bridge.summary
        return [
            Item(id: "play", label: s.play, note: s.playNote),
            Item(id: "freeplay", label: "Freeplay", note: "Any map"),
            Item(id: "levels", label: "Levels", note: s.stars),
            Item(id: "records", label: "Records", note: s.best),
            Item(id: "settings", label: "Settings", note: ""),
            Item(id: "help", label: "How to play", note: ""),
        ]
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "\(v) · Build \(b)"
    }

    var body: some View {
        ZStack {
            // Sky, moon, stars and scanlines run edge to edge; the content keeps to the safe area.
            LinearGradient(stops: [.init(color: Pixel.sky1, location: 0), .init(color: Pixel.sky2, location: 0.55), .init(color: Pixel.sky3, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            GeometryReader { geo in NightSky(size: geo.size) }
                .ignoresSafeArea()
            GeometryReader { geo in
                let size = geo.size
                if size.width > size.height {
                    // On its side: title on the left, the list on the right.
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            topBar.padding(.top, 10)
                            Spacer(minLength: 8)
                            title(width: size.width * 0.5)
                            Spacer(minLength: 8)
                            Skyline().frame(height: 60)
                            Street(reduceMotion: reduceMotion).frame(height: 28)
                        }
                        .frame(width: size.width * 0.5)
                        list(compact: true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Pixel.ground.ignoresSafeArea())
                    }
                } else {
                    let short = size.height < 680
                    VStack(spacing: 0) {
                        topBar.padding(.top, 8)
                        HangingLight(reduceMotion: reduceMotion, lamp: short ? 22 : 30)
                        title(width: size.width).padding(.top, short ? 10 : 18)
                        Spacer(minLength: 10)
                        Skyline().frame(height: short ? 64 : min(size.height * 0.19, 300))
                        Street(reduceMotion: reduceMotion).frame(height: 28)
                        list(compact: short)
                            .padding(.vertical, 10)
                            .frame(maxWidth: 560)
                            .frame(maxWidth: .infinity)
                            .background(Pixel.ground.ignoresSafeArea(edges: .bottom))
                    }
                }
            }
            if let screen = screen {
                page(screen)
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }
            if bridge.summary.scanlines {
                Scanlines().ignoresSafeArea().allowsHitTesting(false).zIndex(2)
            }
        }
        // The game can ask for a screen (All levels or Change settings from a game card).
        .onAppear { takeOpenRequest() }
        .onChange(of: bridge.openRequest) { _ in takeOpenRequest() }
    }

    private func takeOpenRequest() {
        guard let name = bridge.openRequest else { return }
        bridge.openRequest = nil
        screen = name
    }

    private func open(_ name: String?) {
        bridge.feedback()
        withAnimation(.easeOut(duration: 0.22)) { screen = name }
    }

    @ViewBuilder
    private func page(_ name: String) -> some View {
        switch name {
        case "levels":
            LevelsScreen(bridge: bridge, onBack: { open(nil) }, onFreeplay: { open("freeplay") })
        case "records":
            RecordsScreen(bridge: bridge, onBack: { open(nil) })
        case "settings":
            SettingsScreen(bridge: bridge, version: version, onBack: { open(nil) })
        case "freeplay":
            FreeplayScreen(bridge: bridge, onBack: { open(nil) })
        default:
            HelpScreen(onBack: { open(nil) })
        }
    }

    private var topBar: some View {
        HStack {
            Text(version).font(Pixel.font(7)).foregroundColor(Pixel.dim)
            Spacer()
            Text(bridge.summary.stars).font(Pixel.font(7)).foregroundColor(Pixel.yellow)
                .accessibilityLabel(bridge.summary.stars.replacingOccurrences(of: "★", with: "Stars"))
        }
        .padding(.horizontal, 16)
    }

    private func title(width: CGFloat) -> some View {
        let size = min(width * 0.096, 64)
        return VStack(spacing: 12) {
            ZStack {
                Text("GRIDLOCK").font(Pixel.font(size)).foregroundColor(Pixel.redShadow).offset(x: 4, y: 4)
                Text("GRIDLOCK").font(Pixel.font(size)).foregroundColor(Pixel.yellow)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Gridlock")
            .accessibilityAddTraits(.isHeader)
            Text(bridge.summary.shift.uppercased()).font(Pixel.font(8)).foregroundColor(Pixel.dim)
        }
        .frame(maxWidth: .infinity)
    }

    private func list(compact: Bool) -> some View {
        // The ▶ cursor blinks, like an arcade cabinet waiting for a coin.
        TimelineView(.periodic(from: .now, by: 0.45)) { context in
            let blinkOn = reduceMotion || Int(context.date.timeIntervalSinceReferenceDate / 0.45) % 2 == 0
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button {
                        selected = index
                        if item.id == "play" {
                            bridge.command("play")
                        } else {
                            open(item.id)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            CursorArrow()
                                .fill(Pixel.go)
                                .frame(width: 10, height: 12)
                                .opacity(selected == index && blinkOn ? 1 : 0)
                            Text(item.label.uppercased())
                                .font(Pixel.font(index == 0 ? 14 : 11))
                                .foregroundColor(selected == index ? Pixel.yellow : Pixel.item)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(item.note.uppercased())
                                .font(Pixel.term(20))
                                .foregroundColor(Pixel.dim)
                                .lineLimit(1)
                        }
                        .frame(minHeight: compact ? 44 : 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.note.isEmpty ? item.label : "\(item.label), \(item.note)")
                }
            }
            .padding(.horizontal, 28)
        }
    }
}

/// The blinking ▶ next to the chosen item, drawn so it stays pixel-crisp.
private struct CursorArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Moon and a scatter of pixel stars.
private struct NightSky: View {
    let size: CGSize
    private let stars: [CGPoint] = [
        CGPoint(x: 0.10, y: 0.13), CGPoint(x: 0.28, y: 0.07), CGPoint(x: 0.56, y: 0.16),
        CGPoint(x: 0.92, y: 0.21), CGPoint(x: 0.72, y: 0.05), CGPoint(x: 0.40, y: 0.27),
        CGPoint(x: 0.05, y: 0.33), CGPoint(x: 0.84, y: 0.36),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(stars.indices, id: \.self) { i in
                Rectangle().fill(Color.white.opacity(i % 3 == 0 ? 0.5 : 0.9))
                    .frame(width: 3, height: 3)
                    .offset(x: stars[i].x * size.width, y: stars[i].y * size.height)
            }
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: 0xFFF3C4))
                .frame(width: 40, height: 40)
                .shadow(color: Color(hex: 0xFFF3C4).opacity(0.6), radius: 18)
                .offset(x: size.width - 90, y: min(size.height * 0.09, 90))
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

/// The traffic light on its wire, cycling green, amber, red and swaying a little.
private struct HangingLight: View {
    let reduceMotion: Bool
    let lamp: CGFloat
    @State private var lit = 0  // 0 green, 1 amber, 2 red
    @State private var swing = false

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(Pixel.wire).frame(height: 2).frame(maxWidth: .infinity).offset(y: 8)
            VStack(spacing: 0) {
                Rectangle().fill(Pixel.wire).frame(width: 4, height: 14)
                VStack(spacing: 5) {
                    lampView(on: lit == 2, color: Pixel.stop, dark: Color(hex: 0x4A1018))
                    lampView(on: lit == 1, color: Pixel.yellow, dark: Color(hex: 0x4A3A10))
                    lampView(on: lit == 0, color: Pixel.go, dark: Color(hex: 0x10351F))
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color(hex: 0x11131C))
                .overlay(Rectangle().stroke(Pixel.wire, lineWidth: 3))
            }
            .offset(y: 8)
            .rotationEffect(.degrees(swing ? 2 : -2), anchor: .top)
        }
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { swing = true }
        }
        .task {
            guard !reduceMotion else { return }
            let cycle: [(Int, UInt64)] = [(0, 1_600), (1, 650), (2, 1_400)]
            while !Task.isCancelled {
                for (light, ms) in cycle {
                    lit = light
                    try? await Task.sleep(nanoseconds: ms * 1_000_000)
                    if Task.isCancelled { return }
                }
            }
        }
    }

    private func lampView(on: Bool, color: Color, dark: Color) -> some View {
        Rectangle()
            .fill(on ? color : dark)
            .frame(width: lamp, height: lamp)
            .shadow(color: on ? color.opacity(0.6) : .clear, radius: 12)
    }
}

/// Pixel buildings with lit windows, the same every launch.
private struct Skyline: View {
    var body: some View {
        Canvas { ctx, size in
            // Distant towers first, then the near row.
            let farWidths: [CGFloat] = [52, 40, 64, 46]
            let farHeights: [CGFloat] = [0.95, 0.7, 1.0, 0.82]
            var x: CGFloat = -10
            var i = 0
            while x < size.width {
                let w = farWidths[i % 4]
                let h = size.height * farHeights[i % 4]
                ctx.fill(Path(CGRect(x: x, y: size.height - h, width: w, height: h)), with: .color(Color(hex: 0x1B1640)))
                x += w + 6
                i += 1
            }
            x = 0
            i = 0
            let widths: [CGFloat] = [48, 36, 60, 40, 54, 38, 70, 44]
            let heights: [CGFloat] = [0.8, 0.58, 0.98, 0.7, 0.88, 0.52, 0.82, 0.66]
            while x < size.width {
                let w = widths[i % widths.count]
                let h = size.height * heights[i % heights.count]
                let rect = CGRect(x: x, y: size.height - h, width: w, height: h)
                ctx.fill(Path(rect), with: .color(i % 2 == 0 ? Color(hex: 0x120F2A) : Color(hex: 0x0F0C22)))
                let window = i % 3 == 2 ? Color(hex: 0x7FD7FF) : Color(hex: 0xFFD96A)
                var wy = rect.minY + 8
                var n = i * 7
                while wy < rect.maxY - 6 {
                    var wx = rect.minX + 6
                    while wx < rect.maxX - 6 {
                        n = (n &* 1103515245 &+ 12345) & 0x7FFFFFFF
                        if n % 100 < 45 {
                            ctx.fill(Path(CGRect(x: wx, y: wy, width: 4, height: 4)), with: .color(window))
                        }
                        wx += 10
                    }
                    wy += 12
                }
                x += w
                i += 1
            }
        }
        .accessibilityHidden(true)
    }
}

/// The road along the bottom of the skyline, with two cars driving past.
private struct Street: View {
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Pixel.ground))
                var dx: CGFloat = 0
                while dx < size.width {
                    ctx.fill(Path(CGRect(x: dx, y: size.height / 2 - 2, width: 18, height: 4)), with: .color(Pixel.yellow))
                    dx += 32
                }
                let t = reduceMotion ? 2.0 : context.date.timeIntervalSinceReferenceDate
                let span = size.width + 120
                let east = CGFloat((t / 7).truncatingRemainder(dividingBy: 1)) * span - 60
                let west = size.width + 60 - CGFloat(((t + 2) / 9).truncatingRemainder(dividingBy: 1)) * span
                car(&ctx, x: east, y: size.height - 13, color: Pixel.stop, shade: Color(hex: 0x8A1822), lightAhead: 1)
                car(&ctx, x: west, y: 1, color: Pixel.cyan, shade: Color(hex: 0x1B6F80), lightAhead: -1)
            }
        }
        .accessibilityHidden(true)
    }

    private func car(_ ctx: inout GraphicsContext, x: CGFloat, y: CGFloat, color: Color, shade: Color, lightAhead: CGFloat) {
        let beam = CGRect(x: lightAhead > 0 ? x + 30 : x - 26, y: y + 1, width: 26, height: 10)
        ctx.fill(Path(ellipseIn: beam), with: .color(Color(hex: 0xFFF5C8).opacity(0.35)))
        ctx.fill(Path(CGRect(x: x, y: y + 3, width: 30, height: 12)), with: .color(shade))
        ctx.fill(Path(CGRect(x: x, y: y, width: 30, height: 12)), with: .color(color))
    }
}

/// Old-TV lines over the menu (Settings → Scanlines).
private struct Scanlines: View {
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.18)))
                y += 3
            }
        }
        .accessibilityHidden(true)
    }
}
