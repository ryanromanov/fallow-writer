import Foundation

/// Bold and italic, written as Markdown's own marks: `**bold**` and `*italic*`. Fallow's text is
/// plain, so these are the marks themselves, and exports turn them into real bold and italics.
package enum Emphasis {
    case bold, italic

    package var mark: String { self == .bold ? "**" : "*" }
    package var title: String { self == .bold ? "Bold" : "Italic" }

    package struct Edit: Equatable {
        /// The text to replace, and what replaces it.
        package var range: NSRange
        package var text: String
        /// What's selected afterwards: the same words, inside or outside their new marks.
        package var selection: NSRange
    }

    /// Adds the marks around the selection, or takes them away if they're already there. With
    /// nothing selected, it puts a pair of marks at the insertion point to type between.
    package func toggle(in text: NSString, selection: NSRange) -> Edit {
        var range = Self.trimmed(selection, in: text)
        // Marks selected along with the words count as around them.
        let inside = min(Self.stars(in: text, from: range.location, step: 1, limit: NSMaxRange(range)),
                         Self.stars(in: text, from: NSMaxRange(range) - 1, step: -1, limit: range.location - 1))
        if inside * 2 < range.length { range = NSRange(location: range.location + inside, length: range.length - inside * 2) }

        // `*` is italic, `**` bold, `***` both.
        let around = min(Self.stars(in: text, from: range.location - 1, step: -1, limit: -1),
                         Self.stars(in: text, from: NSMaxRange(range), step: 1, limit: text.length))
        let isOn = self == .bold ? around >= 2 : around == 1 || around == 3
        let words = text.substring(with: range)
        let mark = (self.mark as NSString).length
        if isOn {
            return Edit(range: NSRange(location: range.location - mark, length: range.length + mark * 2), text: words,
                        selection: NSRange(location: range.location - mark, length: range.length))
        }
        return Edit(range: range, text: self.mark + words + self.mark,
                    selection: NSRange(location: range.location + mark, length: range.length))
    }

    /// The selection without spaces or line breaks at either end, which belong outside the marks.
    private static func trimmed(_ range: NSRange, in text: NSString) -> NSRange {
        var start = range.location, end = NSMaxRange(range)
        let blank = CharacterSet.whitespacesAndNewlines
        func isBlank(_ index: Int) -> Bool { UnicodeScalar(text.character(at: index)).map(blank.contains) ?? false }
        while start < end, isBlank(start) { start += 1 }
        while end > start, isBlank(end - 1) { end -= 1 }
        return start == end ? NSRange(location: range.location, length: 0) : NSRange(location: start, length: end - start)
    }

    /// How many `*` run from `index` in the direction of `step`, up to three, stopping at `limit`.
    private static func stars(in text: NSString, from index: Int, step: Int, limit: Int) -> Int {
        var count = 0, index = index
        while count < 3, index != limit, index >= 0, index < text.length, text.character(at: index) == 42 {
            count += 1
            index += step
        }
        return count
    }
}
