import AppKit

extension KeyClass {
    /// Nil for keys that shouldn't make a sound: shortcuts (⌘ or ⌃ held), arrows, function and
    /// navigation keys, and Escape.
    static func classify(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String?) -> KeyClass? {
        if !modifiers.intersection([.command, .control]).isEmpty { return nil }
        switch keyCode {
        case 49, 48: return .space          // space, tab
        case 36, 76: return .newline        // return, keypad enter
        case 51, 117: return .delete        // delete (backspace), forward delete
        case 53: return nil                 // escape
        default: break
        }
        guard let scalar = characters?.unicodeScalars.first else { return nil }
        // AppKit sends arrows, function and navigation keys as private-use characters.
        if (0xF700...0xF8FF).contains(scalar.value) || scalar.properties.generalCategory == .control { return nil }
        return .letter
    }

    init?(event: NSEvent) {
        guard let kind = Self.classify(
            keyCode: event.keyCode, modifiers: event.modifierFlags, characters: event.charactersIgnoringModifiers)
        else { return nil }
        self = kind
    }
}
