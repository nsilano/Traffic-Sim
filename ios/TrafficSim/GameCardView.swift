import SwiftUI

/// A game card (level intro, pause, results) drawn natively over the live board.
/// Its buttons press the matching button on the game's own card.
struct GameCardView: View {
    @ObservedObject var bridge: GameHost
    let card: GameCard

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(card.eyebrow.uppercased())
                        .font(Pixel.font(8))
                        .foregroundColor(Pixel.cyan)
                        .fixedSize(horizontal: false, vertical: true)
                    if let stars = card.stars {
                        HStack(spacing: 10) {
                            ForEach(0..<3, id: \.self) { i in
                                Text("★")
                                    .font(.system(size: 40, weight: .heavy))
                                    .foregroundColor(i < stars.count && stars[i] ? Pixel.yellow : Pixel.starOff)
                                    .shadow(color: i < stars.count && stars[i] ? Pixel.yellow.opacity(0.6) : .clear, radius: 10)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(stars.filter { $0 }.count) of 3 stars")
                    }
                    Text(card.title.uppercased())
                        .font(Pixel.font(16))
                        .foregroundColor(Pixel.yellow)
                        .shadow(color: Pixel.redShadow, radius: 0, x: 3, y: 3)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let score = card.score {
                        HStack(spacing: 10) {
                            Text(score).font(Pixel.term(30)).foregroundColor(Pixel.text)
                            if let note = card.scoreNote {
                                Text(note.uppercased())
                                    .font(Pixel.font(7))
                                    .foregroundColor(note.hasPrefix("New") ? Color(hex: 0x06301A) : Pixel.dim)
                                    .padding(.horizontal, note.hasPrefix("New") ? 6 : 0)
                                    .padding(.vertical, 4)
                                    .background(note.hasPrefix("New") ? Pixel.go : Color.clear)
                                    .cornerRadius(2)
                            }
                        }
                    }
                    ForEach(Array((card.lines ?? []).enumerated()), id: \.offset) { i, line in
                        Text(line)
                            .font(Pixel.term(i == 0 ? 22 : 19))
                            .foregroundColor(i == 0 ? Pixel.text : Pixel.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let goals = card.goals, !goals.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(goals.enumerated()), id: \.offset) { _, goal in
                                HStack(spacing: 8) {
                                    Text("★").font(.system(size: 15, weight: .bold))
                                        .foregroundColor(goal.on ? Pixel.yellow : Pixel.starOff)
                                    Text(goal.text).font(Pixel.term(20)).foregroundColor(Pixel.text)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityValue(goal.on ? "Earned" : "Not earned yet")
                            }
                        }
                    }
                    VStack(spacing: 12) {
                        ForEach(card.actions, id: \.id) { action in
                            if action.primary == true {
                                PixelButton(title: action.label) { bridge.command("card", key: action.id) }
                            } else {
                                PixelButton(title: action.label, color: Pixel.panel, textColor: Pixel.text, shade: Pixel.deep) {
                                    bridge.command("card", key: action.id)
                                }
                            }
                        }
                    }
                    .padding(.top, 6)
                }
                .padding(20)
                .background(Color(hex: 0x120F2A))
                .overlay(Rectangle().fill(Pixel.pink).frame(height: 4), alignment: .top)
                .overlay(Rectangle().stroke(Pixel.edge, lineWidth: 2))
                .shadow(color: Pixel.deep, radius: 0, x: 0, y: 6)
                .frame(maxWidth: 460)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
        }
    }
}
