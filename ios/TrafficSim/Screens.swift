import SwiftUI

extension Pixel {
    static let pink = Color(hex: 0xFF3CAC)
    static let edge = Color(hex: 0x3D2A5C)
    static let edgeDim = Color(hex: 0x24173A)
    static let panel = Color(hex: 0x2A1840)
    static let starOff = Color(hex: 0x75659F)
    static let deep = Color(hex: 0x0B0716)
}

// MARK: - Building blocks

/// A full-screen page in the Pixel City style: a back button, a neon title and scrolling content.
struct PixelScreen<Content: View>: View {
    let title: String
    let onBack: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundColor(Pixel.yellow)
                        .frame(width: 44, height: 44)
                        .background(Pixel.panel)
                        .cornerRadius(6)
                        .shadow(color: Pixel.deep, radius: 0, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Text(title.uppercased())
                    .font(Pixel.font(15))
                    .foregroundColor(Pixel.cyan)
                    .shadow(color: Color(hex: 0x19A7FF), radius: 6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Rectangle().fill(Pixel.pink).frame(height: 3).shadow(color: Pixel.pink.opacity(0.6), radius: 8, y: 4)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) { content }
                    .padding(16)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(LinearGradient(colors: [Pixel.deep, Color(hex: 0x160A2B)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }
}

/// A labelled box of rows, like the settings groups in the concept.
struct PixelSection<Content: View>: View {
    let title: String
    let color: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(Pixel.font(9))
                .foregroundColor(color)
                .shadow(color: color.opacity(0.7), radius: 6)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { content }
                .background(Color(hex: 0x07040F).opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Pixel.edge, lineWidth: 2))
                .cornerRadius(4)
        }
    }
}

/// A thin divider between rows in a section.
struct RowDivider: View {
    var body: some View { Rectangle().fill(Pixel.edgeDim).frame(height: 2) }
}

/// The chunky ON/OFF switch from the settings concept.
struct PixelSwitch: View {
    let on: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(on ? "ON" : "OFF")
                .font(Pixel.font(10))
                .foregroundColor(on ? Color(hex: 0x06301A) : Pixel.dim)
                .frame(width: 72, height: 44)
                .background(on ? Pixel.go : Pixel.panel)
                .cornerRadius(4)
                .shadow(color: on ? Pixel.go.opacity(0.5) : .clear, radius: 10)
                .shadow(color: on ? Color(hex: 0x0D6A36) : Pixel.deep, radius: 0, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}

/// Three stars, lit for each one earned.
struct StarRow: View {
    let stars: [Bool]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Text("★")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(i < stars.count && stars[i] ? Pixel.yellow : Pixel.starOff)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stars.filter { $0 }.count) of 3 stars")
    }
}

/// A big neon action button.
struct PixelButton: View {
    let title: String
    var color: Color = Pixel.go
    var textColor: Color = Color(hex: 0x06301A)
    var shade: Color = Color(hex: 0x0D6A36)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(Pixel.font(11))
                .foregroundColor(textColor)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(color)
                .cornerRadius(6)
                .shadow(color: shade, radius: 0, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

private func formatted(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    return f.string(from: NSNumber(value: n)) ?? String(n)
}

// MARK: - Levels

struct LevelsScreen: View {
    @ObservedObject var bridge: GameBridge
    let onBack: () -> Void
    let onFreeplay: () -> Void

    var body: some View {
        PixelScreen(title: "Choose a shift", onBack: onBack) {
            Text("Finish a level to unlock the next one. Freeplay is always open.")
                .font(Pixel.term(21)).foregroundColor(Pixel.dim)
            PixelSection(title: "Campaign", color: Pixel.cyan) {
                ForEach(Array(bridge.data.levels.enumerated()), id: \.offset) { i, level in
                    if i > 0 { RowDivider() }
                    Button {
                        bridge.command("pick", level: i)
                    } label: {
                        HStack(spacing: 12) {
                            Text(String(i + 1))
                                .font(Pixel.font(12))
                                .foregroundColor(level.locked ? Pixel.starOff : Pixel.yellow)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.name).font(Pixel.term(25)).foregroundColor(level.locked ? Pixel.dim : Pixel.text)
                                Text(level.desc).font(Pixel.term(18)).foregroundColor(Pixel.dim)
                            }
                            Spacer(minLength: 6)
                            if level.locked {
                                Text("LOCKED").font(Pixel.font(7)).foregroundColor(Pixel.starOff)
                            } else if let stars = level.stars {
                                VStack(alignment: .trailing, spacing: 2) {
                                    StarRow(stars: stars)
                                    Text(formatted(level.score)).font(Pixel.term(19)).foregroundColor(Pixel.cyan)
                                }
                            } else {
                                Text("OPEN").font(Pixel.font(7)).foregroundColor(Pixel.go)
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 62)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(level.locked)
                }
            }
            PixelSection(title: "Anytime", color: Pixel.yellow) {
                Button(action: onFreeplay) {
                    HStack(spacing: 12) {
                        Text("∞").font(.system(size: 20, weight: .heavy)).foregroundColor(Pixel.yellow).frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Freeplay").font(Pixel.term(25)).foregroundColor(Pixel.text)
                            Text("Any map, your traffic density, no goal").font(Pixel.term(18)).foregroundColor(Pixel.dim)
                        }
                        Spacer()
                        Text("OPEN").font(Pixel.font(7)).foregroundColor(Pixel.go)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 62)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Records

struct RecordsScreen: View {
    @ObservedObject var bridge: GameBridge
    let onBack: () -> Void

    var body: some View {
        PixelScreen(title: "Records", onBack: onBack) {
            Text("\(bridge.data.totalStars) of \(bridge.data.levels.count * 3) stars")
                .font(Pixel.font(12)).foregroundColor(Pixel.yellow)
                .shadow(color: Pixel.redShadow, radius: 0, x: 2, y: 2)
            PixelSection(title: "Campaign", color: Pixel.cyan) {
                ForEach(Array(bridge.data.levels.enumerated()), id: \.offset) { i, level in
                    if i > 0 { RowDivider() }
                    HStack(spacing: 10) {
                        Text(String(i + 1)).font(Pixel.font(10)).foregroundColor(Pixel.yellow).frame(width: 22)
                        Text(level.name).font(Pixel.term(23)).foregroundColor(Pixel.text).lineLimit(1)
                        Spacer(minLength: 6)
                        StarRow(stars: level.stars ?? [false, false, false])
                        Text(level.score > 0 ? formatted(level.score) : "—")
                            .font(Pixel.term(21)).foregroundColor(Pixel.cyan)
                            .frame(minWidth: 64, alignment: .trailing)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 48)
                    .accessibilityElement(children: .combine)
                }
            }
            if bridge.data.bests.isEmpty {
                Text("Play freeplay to set bests for each map and density.")
                    .font(Pixel.term(21)).foregroundColor(Pixel.dim)
            } else {
                PixelSection(title: "Freeplay bests", color: Pixel.pink) {
                    ForEach(Array(bridge.data.bests.enumerated()), id: \.offset) { i, best in
                        if i > 0 { RowDivider() }
                        HStack(spacing: 10) {
                            Text(best.label).font(Pixel.term(20)).foregroundColor(Pixel.text)
                            Spacer(minLength: 6)
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(formatted(best.score)).font(Pixel.term(21)).foregroundColor(Pixel.cyan)
                                Text(String(format: "%.1f/min", best.cpm)).font(Pixel.term(17)).foregroundColor(Pixel.dim)
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 50)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

// MARK: - Settings

struct SettingsScreen: View {
    @ObservedObject var bridge: GameBridge
    let version: String
    let onBack: () -> Void
    @State private var confirmBests = false
    @State private var confirmAll = false

    private struct Group: Identifiable {
        let name: String
        let rows: [GameData.Setting]
        var id: String { name }
    }

    /// Settings in their groups, in the order the game lists them.
    private var groups: [Group] {
        var order: [String] = []
        var rows: [String: [GameData.Setting]] = [:]
        for s in bridge.data.settings {
            if rows[s.group] == nil { order.append(s.group) }
            rows[s.group, default: []].append(s)
        }
        return order.map { Group(name: $0, rows: rows[$0] ?? []) }
    }

    private func color(_ group: String) -> Color {
        switch group {
        case "Gameplay": return Pixel.cyan
        case "Display": return Pixel.yellow
        default: return Pixel.pink
        }
    }

    var body: some View {
        PixelScreen(title: "Settings", onBack: onBack) {
            ForEach(groups) { group in
                PixelSection(title: group.name, color: color(group.name)) {
                    ForEach(Array(group.rows.enumerated()), id: \.element.key) { i, row in
                        if i > 0 { RowDivider() }
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name).font(Pixel.term(24)).foregroundColor(Pixel.text)
                                Text(row.hint).font(Pixel.term(18)).foregroundColor(Pixel.dim)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            PixelSwitch(on: row.on, label: row.name) {
                                bridge.command("setting", key: row.key)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(minHeight: 62)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("DANGER ZONE").font(Pixel.font(9)).foregroundColor(Pixel.stop).shadow(color: Pixel.stop.opacity(0.7), radius: 6)
                PixelButton(title: "Reset freeplay bests", color: Color(hex: 0x1A1030), textColor: Pixel.text, shade: Pixel.deep) {
                    confirmBests = true
                }
                PixelButton(title: "Reset all progress", color: Color(hex: 0xB3161C), textColor: .white, shade: Color(hex: 0x5C0F15)) {
                    confirmAll = true
                }
            }
            Text("GRIDLOCK · \(version.uppercased())")
                .font(Pixel.font(7)).foregroundColor(Color(hex: 0x6F6290))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .confirmationDialog("Erase every freeplay best?", isPresented: $confirmBests, titleVisibility: .visible) {
            Button("Erase bests", role: .destructive) { bridge.command("reset-bests") }
            Button("Keep them", role: .cancel) {}
        }
        .alert("Erase all progress?", isPresented: $confirmAll) {
            Button("Erase all", role: .destructive) { bridge.command("reset-all") }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Every star, score, unlocked level and freeplay best will be erased.")
        }
    }
}

// MARK: - Freeplay setup

struct FreeplayScreen: View {
    @ObservedObject var bridge: GameBridge
    let onBack: () -> Void
    @State private var config = FreeplayConfig()
    @State private var loaded = false

    private func densityName(_ d: Int) -> String {
        let names = bridge.data.densityNames
        let name = d >= 1 && d <= names.count ? names[d - 1] : ""
        return "\(name) (\(d))"
    }

    var body: some View {
        PixelScreen(title: "Freeplay", onBack: onBack) {
            PixelSection(title: "Map", color: Pixel.cyan) {
                ForEach(Array(bridge.data.levels.enumerated()), id: \.offset) { i, level in
                    if i > 0 { RowDivider() }
                    Button {
                        config.map = i
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .strokeBorder(config.map == i ? Pixel.go : Pixel.edge, lineWidth: 3)
                                .background(Circle().fill(config.map == i ? Pixel.go : .clear).padding(6))
                                .frame(width: 22, height: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.name).font(Pixel.term(24)).foregroundColor(Pixel.text)
                                Text(level.layout).font(Pixel.term(18)).foregroundColor(Pixel.dim)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(config.map == i ? .isSelected : [])
                }
            }
            PixelSection(title: "Traffic density", color: Pixel.yellow) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(densityName(config.density)).font(Pixel.term(24)).foregroundColor(Pixel.text)
                    Slider(value: Binding(get: { Double(config.density) }, set: { config.density = Int($0.rounded()) }), in: 1...10, step: 1)
                        .tint(Pixel.go)
                        .accessibilityLabel("Traffic density")
                        .accessibilityValue(densityName(config.density))
                    Text("Density sets how busy it gets on average; 5 matches the map's level at its busiest.")
                        .font(Pixel.term(18)).foregroundColor(Pixel.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
            }
            PixelSection(title: "Traffic flow", color: Pixel.pink) {
                ForEach(Array(bridge.data.flows.enumerated()), id: \.element.key) { i, flow in
                    if i > 0 { RowDivider() }
                    Button {
                        config.flow = flow.key
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .strokeBorder(config.flow == flow.key ? Pixel.go : Pixel.edge, lineWidth: 3)
                                .background(Circle().fill(config.flow == flow.key ? Pixel.go : .clear).padding(6))
                                .frame(width: 22, height: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(flow.label).font(Pixel.term(24)).foregroundColor(Pixel.text)
                                Text(flow.desc).font(Pixel.term(18)).foregroundColor(Pixel.dim)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(config.flow == flow.key ? .isSelected : [])
                }
            }
            PixelSection(title: "Extras", color: Pixel.cyan) {
                toggleRow("Rush-hour surges", on: config.rush) { config.rush.toggle() }
                RowDivider()
                toggleRow("Pedestrians", on: config.peds) { config.peds.toggle() }
                RowDivider()
                toggleRow("Night", on: config.night) { config.night.toggle() }
                RowDivider()
                toggleRow("Emergency vehicles", on: config.emergency) { config.emergency.toggle() }
            }
            Text("Streets start empty and fill up over the first minute. No goal, no patience meter, and crashes never end the game.")
                .font(Pixel.term(19)).foregroundColor(Pixel.dim)
                .fixedSize(horizontal: false, vertical: true)
            PixelButton(title: "Start freeplay") {
                bridge.command("freeplay-start", freeplay: config)
            }
        }
        .onAppear {
            if !loaded {
                config = bridge.data.freeplay
                loaded = true
            }
        }
    }

    private func toggleRow(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(Pixel.term(24)).foregroundColor(Pixel.text)
            Spacer()
            PixelSwitch(on: on, label: title, action: action)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - How to play

struct HelpScreen: View {
    let onBack: () -> Void

    var body: some View {
        PixelScreen(title: "How to play", onBack: onBack) {
            PixelSection(title: "Run the signals", color: Pixel.cyan) {
                bullet("The buttons beside each waiting line control those cars. Tap one to turn it green; tap again to send it through yellow to red.")
                RowDivider()
                bullet("Arrows show where those cars go: straight (with right turns) or left. Walking-figure buttons give people a Walk signal.")
                RowDivider()
                bullet("Two conflicting greens cause crashes. Each driver decides for themselves whether to run a yellow, so let the box clear before switching the cross street.")
            }
            PixelSection(title: "Reading the map", color: Pixel.yellow) {
                key(AnyView(Text("N ★").font(Pixel.term(20)).foregroundColor(Pixel.deep).padding(.horizontal, 5).background(Pixel.yellow)),
                    "Busiest corner. Its set of buttons gets a yellow outline and a ★: most people are waiting there, so it probably needs a green next.")
                RowDivider()
                key(AnyView(Text("15 · 31S").font(Pixel.term(20)).foregroundColor(.white).padding(.horizontal, 5).background(Pixel.stop)),
                    "Beside each set of buttons: how many are waiting and the longest wait. It turns yellow, then red, as drivers lose patience.")
                RowDivider()
                key(AnyView(Text("7").font(Pixel.term(20)).foregroundColor(Pixel.deep).frame(minWidth: 20).background(Pixel.text)),
                    "The number on a button: how many are waiting for that signal.")
                RowDivider()
                key(AnyView(Text("!").font(Pixel.font(11)).foregroundColor(.white).frame(width: 22, height: 22).background(Pixel.stop)),
                    "Not safe yet. Turning it green now would cross moving traffic. Wait for it to clear.")
                RowDivider()
                key(AnyView(Image(systemName: "bolt.fill").foregroundColor(Pixel.yellow).frame(width: 22, height: 22).background(Pixel.deep)),
                    "A driver speeding up to beat a yellow. Watch for them before you switch.")
                RowDivider()
                key(AnyView(Circle().stroke(Color(hex: 0xFF3B3B), lineWidth: 3).frame(width: 20, height: 20).overlay(Circle().stroke(Color(hex: 0x3B82FF), lineWidth: 3).frame(width: 27, height: 27))),
                    "Sirens. An emergency vehicle is coming; its buttons flash red and blue. Give its lane a green. The ring around it only runs down while it's stopped at a red; let it run out and you lose points.")
            }
            PixelSection(title: "Score and streaks", color: Pixel.pink) {
                bullet("Every car through scores points. Clear cars in a row to build a streak and a combo up to ×3; clear a whole queue in one green for a Green Wave bonus.")
                RowDivider()
                bullet("You lose the streak when a driver or someone at a crossing waits too long (they honk), when cars crash, or when an emergency vehicle is held up. The message tells you which.")
                RowDivider()
                bullet("Streets start empty and fill up over the first minute, then traffic comes in waves.")
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle().fill(Pixel.pink).frame(width: 6, height: 6).padding(.top, 8)
            Text(text).font(Pixel.term(21)).foregroundColor(Pixel.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private func key(_ mark: AnyView, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            mark.frame(width: 76, alignment: .center).padding(.top, 2)
            Text(text).font(Pixel.term(20)).foregroundColor(Pixel.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .accessibilityElement(children: .combine)
    }
}
