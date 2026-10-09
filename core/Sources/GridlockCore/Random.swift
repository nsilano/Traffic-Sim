import Foundation

/// The simulation's dice: mulberry32, a small seeded generator. With the same seed the
/// Swift engine and the JavaScript game (when its Math.random is swapped for the same
/// generator in tests) draw exactly the same numbers in the same order.
public final class Random {
    private var a: UInt32

    public init(seed: UInt32) { a = seed }

    /// A seed from the system's own randomness, for normal play.
    public convenience init() { self.init(seed: UInt32.random(in: 0...UInt32.max)) }

    /// A number in [0, 1).
    public func next() -> Double {
        a = a &+ 0x6D2B_79F5
        var t = (a ^ (a >> 15)) &* (1 | a)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }

    /// a + random × (b − a).
    public func between(_ range: [Double]) -> Double { range[0] + next() * (range[1] - range[0]) }

    /// A random element.
    public func pick<T>(_ items: [T]) -> T { items[Int(next() * Double(items.count))] }

    /// An exponentially distributed wait with the given mean.
    public func exponential(mean: Double) -> Double { -log(1 - next()) * mean }
}
