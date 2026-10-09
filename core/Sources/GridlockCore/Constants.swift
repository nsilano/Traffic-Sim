// World geometry and tuning, matching game.js. Logical units: the board is 640 x 640.

public enum World {
    public static let width = 640.0
    public static let height = 640.0
    public static let cx = width / 2
    public static let cy = height / 2
    public static let half = width / 2
    public static let laneWidth = 26.0
    public static let sidewalk = 16.0
    public static let crosswalk = 18.0
    /// Space between the stop line and the crosswalk.
    public static let stopGap = 6.0
    /// Cars spawn this far off the board.
    public static let pad = 40.0
    /// Path centre lines closer than this inside the box can collide.
    public static let conflictDistance = 15.0
    /// Where a dropped lane starts to taper, past the box, and how long the taper is.
    public static let mergeStart = 40.0
    public static let mergeLength = 110.0
}

/// A point or a direction on the board.
public struct Vec: Equatable, Hashable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }

    public func distance(to o: Vec) -> Double { ((x - o.x) * (x - o.x) + (y - o.y) * (y - o.y)).squareRoot() }
}
