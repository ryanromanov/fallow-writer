import Foundation

public enum WordCounter {
    /// Words as the system's word breaker sees them, so "don't" is one word and punctuation isn't one.
    public static func words(in text: String) -> Int {
        var count = 0
        let string = text as NSString
        string.enumerateSubstrings(
            in: NSRange(location: 0, length: string.length),
            options: [.byWords, .substringNotRequired]
        ) { _, _, _, _ in count += 1 }
        return count
    }

    /// The status line under the text, such as "Untitled · 1,204 words".
    public static func status(name: String, words: Int) -> String {
        let number = NumberFormatter.localizedString(from: NSNumber(value: words), number: .decimal)
        return "\(name) · \(number) \(words == 1 ? "word" : "words")"
    }
}
