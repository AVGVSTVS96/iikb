/// Where the bar's parts go, on every screen from one rule: each button is one circle (`Toolbar.button`) centered in
/// a square cell the bar's height, or a key wide where keys are narrower (never narrower than itself), so it has as much room on its sides as above
/// and below. The cells are set out as the top row's keys are: the More button's and the tools' from the first key's
/// left edge and the mic's ending on the last key's right edge, a key gap apart, so the buttons keep one size and
/// spacing on every screen and the mic sits evenly in its corner. Between them the three suggestions share the bar, or
/// on a phone's bar wide enough take what they need and leave the rest to the word's emoji, beside them rather than in
/// the third one's place. Neither depends on the emoji, so the suggestions never move as you type, as Apple's don't.
/// While you dictate, the recording, a capsule the mic grows into, ends at the mic's right edge, or the last key's where
/// the mic sits in the bottom row, and runs back to where the button after the tools and cancel's would be, but no
/// further than `recordingWidth`, so a wide bar leaves the rest empty and a narrow one shortens the recording first.
/// The cancel button sits a pitch before it. Where the bar has room for the suggestions, two emoji and the writing style
/// too, the style sits at the suggestions' right end, before the mic, and the emoji between them.
public struct BarLayout: Hashable, Sendable {
    public var mic: Rect?
    public var tools: [Rect]
    public var more: Rect?
    /// The suggestions' span.
    public var minX, maxX: Double
    public var cancel: Rect
    public var recording: Rect
    public var slots: [Rect]
    /// The emoji's place: beside the suggestions where the bar has room for them, else the third suggestion's.
    public var emoji: Rect
    public var emojiBeside: Bool
    /// The writing style's place, where the bar has room for it.
    public var style: Rect?
    /// From one button's center to the next one's.
    public var pitch: Double

    /// The gap between the end buttons and the suggestions.
    public static let gap = 4.0
    /// A suggestion never needs more width than a third of an iPhone's bar in portrait.
    public static let slotWidth = 130.0
    public static let emojiPitch = 36.0
    /// The recording's longest, a little under what an iPhone's bar in portrait gives it.
    public static let recordingWidth = 220.0
    /// The writing style's place: as wide as its widest name, "very casual", needs.
    public static let styleWidth = 104.0

    /// `keys` are the top row's keys, left to right, as their edges. Where a suggestion is at most `maximumSlot` wide
    /// (Apple's iPad), the middle one is centered on the keys as Apple's is, or as near as the tools and mic leave room.
    public init(
        _ toolbar: Toolbar, keys: [(minX: Double, maxX: Double)], tools: Int, more: Bool = false, mic: Bool = true,
        style: Bool = false, maximumSlot: Double = .infinity
    ) {
        let row = (y: toolbar.top, height: toolbar.bar)
        let side = toolbar.button
        let left = keys.first?.minX ?? 0
        let right = keys.last?.maxX ?? 0
        let cell = max(min(keys.map { $0.maxX - $0.minX }.min() ?? row.height, row.height), side)
        let pitch = cell + (keys.count > 1 ? keys[1].minX - keys[0].maxX : 0)
        self.pitch = pitch
        let inset = (cell - side) / 2
        func button(at x: Double) -> Rect {
            Rect(x: x + inset, y: row.y + (row.height - side) / 2, width: side, height: side)
        }
        let leading = (0..<((more ? 1 : 0) + tools)).map { button(at: left + Double($0) * pitch) }
        self.more = more ? leading.first : nil
        self.tools = Array(leading.dropFirst(more ? 1 : 0))
        self.mic = mic ? button(at: right - cell) : nil
        minX = leading.last.map { $0.x + $0.width + inset + Self.gap } ?? left
        maxX = self.mic.map { $0.x - inset - Self.gap } ?? right
        let end = self.mic.map { $0.x + $0.width } ?? right
        let start = max(left + Double(leading.count + 1) * pitch + inset, end - Self.recordingWidth)
        cancel = Rect(x: start - pitch, y: row.y + (row.height - side) / 2, width: side, height: side)
        recording = Rect(x: start, y: cancel.y, width: end - start, height: side)
        let span = maxX - minX
        emojiBeside = maximumSlot == .infinity && span - 3 * Self.slotWidth >= 2 * Self.emojiPitch
        let slot = emojiBeside ? Self.slotWidth : min(span / 3, maximumSlot)
        let centered = min(max((left + right) / 2 - 1.5 * slot, minX), maxX - 3 * slot)
        let first = emojiBeside ? minX : centered
        slots = (0..<3).map { Rect(x: first + Double($0) * slot, y: row.y, width: slot, height: row.height) }
        let besideX = first + 3 * slot
        let styleRoom = Self.styleWidth + Self.gap + 2 * Self.emojiPitch
        let styled = style && emojiBeside && span - 3 * Self.slotWidth >= styleRoom
        self.style =
            styled ? Rect(x: maxX - Self.styleWidth, y: row.y, width: Self.styleWidth, height: row.height) : nil
        let emojiEnd = self.style.map { $0.x - Self.gap } ?? maxX
        self.emoji = emojiBeside ? Rect(x: besideX, y: row.y, width: emojiEnd - besideX, height: row.height) : slots[2]
    }
}
