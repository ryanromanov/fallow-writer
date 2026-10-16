import AppKit
import CoreText

/// Typed letters settle into place: each one appears as a copy that fades in and shrinks
/// gently onto the spot where the real letter sits, and is swapped for the real one when done.
///
/// While a letter animates, the real one is made transparent in the text storage. (TextKit 2's
/// rendering attributes would be cleaner, but NSTextView ignores them on current macOS.) That
/// changes no text, adds no undo step and doesn't mark the document edited, but a letter left
/// transparent would look like lost text, so every exit path restores color:
/// - each animation restores its own letter when its time is up, on a timer of its own (Core
///   Animation's completion callbacks aren't guaranteed to fire)
/// - `finishAll()` ends every animation and sweeps the whole text for transparent letters; it
///   runs before deletes, before and after undo and redo, on paste, marked text, settings and
///   appearance changes, resizing and losing focus
/// - a sweep also runs whenever the last animation ends
/// - `WriterTextView` never lets the transparent color into the typing attributes
final class LetterAnimator {
    static let duration: CFTimeInterval = 0.28
    /// Room around each letter's box, so the settle animation's larger start isn't clipped.
    static let pad: CGFloat = 8
    /// Transparent, and recognizably Fallow's own: any color with zero alpha counts as hidden.
    static let hiddenColor = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)

    private struct Running {
        var range: NSRange
        let layer: CALayer
        let timer: Timer?
        /// Where the letter was when the animation began, to notice if the line reflowed.
        let rect: NSRect
    }

    private unowned let textView: WriterTextView
    private let overlay: OverlayView
    private var running: [Running] = []
    /// Tests freeze animations at their final frame, drawn red over the visible real letter,
    /// to check alignment.
    var freezeForAlignmentCheck = false

    var runningCount: Int { running.count }

    init(textView: WriterTextView) {
        self.textView = textView
        overlay = OverlayView(frame: textView.bounds)
        overlay.autoresizingMask = [.width, .height]
        textView.addSubview(overlay)
    }

    /// Settles every letter before and after each undo and redo, which change the text without
    /// going through `didChangeText`. Before, so a transparent letter can't be saved into the
    /// undo history; after, in case one comes back anyway.
    func watch(_ undoManager: UndoManager) {
        for name in [
            Notification.Name.NSUndoManagerWillUndoChange, .NSUndoManagerDidUndoChange,
            .NSUndoManagerWillRedoChange, .NSUndoManagerDidRedoChange,
        ] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(undoManagerChanged), name: name, object: undoManager)
        }
    }

    @objc private func undoManagerChanged(_ notification: Notification) { finishAll() }

    /// Animates the character just typed at `range`, if it's a visible character.
    func animate(_ range: NSRange) {
        guard range.length > 0, let storage = textView.textStorage, NSMaxRange(range) <= storage.length else { return }
        let string = storage.attributedSubstring(from: range)
        guard string.string.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted) != nil,
              let font = string.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        else { return }

        // A letter inserted before running ones moves them, and a word wrapping to the next
        // line moves its letters: those copies would land in the wrong place, so end them now.
        textView.layoutSubtreeIfNeeded()
        for item in running where item.range.location >= range.location || moved(item) {
            finish(item, sweep: false)
        }
        guard let geometry = glyphGeometry(for: range, font: font) else { return }

        let layer = CALayer()
        let scale = textView.window?.backingScaleFactor ?? 2
        // Put the layer on whole pixels so its image isn't resampled, and draw the letter
        // inside it at its exact (fractional) position instead.
        let box = geometry.rect.insetBy(dx: -Self.pad, dy: -Self.pad)
        let origin = NSPoint(x: (box.minX * scale).rounded(.down) / scale, y: (box.minY * scale).rounded(.down) / scale)
        layer.frame = NSRect(origin: origin, size: NSSize(
            width: ((box.maxX - origin.x) * scale).rounded(.up) / scale,
            height: ((box.maxY - origin.y) * scale).rounded(.up) / scale))
        layer.contentsScale = scale
        let color = freezeForAlignmentCheck ? NSColor.systemRed : Palette.text
        layer.contents = Self.image(
            of: string.string, font: font, color: color, appearance: textView.effectiveAppearance,
            size: layer.frame.size, origin: NSPoint(x: geometry.rect.minX - origin.x, y: geometry.baseline - origin.y),
            scale: scale)
        overlay.layer?.addSublayer(layer)
        var item = Running(range: range, layer: layer, timer: nil, rect: geometry.rect)
        if freezeForAlignmentCheck {
            running.append(item)
            return
        }
        // The real letter comes back when the copy's time is up, whatever Core Animation does.
        // A run loop timer, in common modes, also fires during window resizing and menu tracking.
        let timer = Timer(timeInterval: Self.duration, repeats: false) { [weak self, layer] _ in
            guard let self, let item = running.first(where: { $0.layer === layer }) else { return }
            finish(item, sweep: true)
        }
        RunLoop.main.add(timer, forMode: .common)
        item = Running(range: range, layer: layer, timer: timer, rect: geometry.rect)
        running.append(item)
        storage.addAttribute(.foregroundColor, value: Self.hiddenColor, range: range)

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        let settle = CABasicAnimation(keyPath: "transform")
        settle.fromValue = CATransform3DConcat(
            CATransform3DMakeScale(1.35, 1.35, 1), CATransform3DMakeTranslation(0, -font.pointSize * 0.12, 0))
        settle.toValue = CATransform3DIdentity
        let group = CAAnimationGroup()
        group.animations = [fade, settle]
        group.duration = Self.duration
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.3, 1)
        layer.add(group, forKey: "settle")
    }

    /// Ends every animation at once and makes sure no letter is left transparent.
    func finishAll() {
        for item in running { finish(item, sweep: false) }
        sweep()
    }

    private func finish(_ item: Running, sweep shouldSweep: Bool) {
        guard let index = running.firstIndex(where: { $0.layer === item.layer }) else { return }
        running.remove(at: index)
        item.timer?.invalidate()
        item.layer.removeFromSuperlayer()
        restore(item.range)
        if shouldSweep, running.isEmpty { sweep() }
    }

    /// Restores the normal color over `range`. If edits have shifted the text, this may land
    /// on other letters, which is harmless: all of Fallow's text shares one color.
    private func restore(_ range: NSRange) {
        guard let storage = textView.textStorage else { return }
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
        guard clamped.length > 0 else { return }
        storage.addAttribute(.foregroundColor, value: Palette.text, range: clamped)
    }

    /// Finds any transparent letters left anywhere and restores them.
    private func sweep() {
        for range in hiddenRanges() { restore(range) }
    }

    func hiddenRanges() -> [NSRange] {
        guard let storage = textView.textStorage else { return [] }
        var ranges: [NSRange] = []
        storage.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if let color = value as? NSColor, color.alphaComponent == 0 { ranges.append(range) }
        }
        return ranges
    }

    private func moved(_ item: Running) -> Bool {
        guard let rect = textView.characterRect(for: item.range) else { return true }
        // Kerning nudges a letter by a fraction of a point as the next one arrives; a reflow
        // moves it much further.
        return abs(rect.minX - item.rect.minX) > 2 || abs(rect.minY - item.rect.minY) > 2
    }

    /// The letter's box and baseline in text view coordinates. The box's horizontal extent
    /// comes from the text view; the baseline from TextKit's line fragment.
    private func glyphGeometry(for range: NSRange, font: NSFont) -> (rect: NSRect, baseline: CGFloat)? {
        guard let rect = textView.characterRect(for: range), let baseline = textView.baseline(at: range.location)
        else { return nil }
        return (rect, baseline)
    }

    /// Draws `text` into an image `size` big, starting `origin.x` points from the left with its
    /// baseline `origin.y` points from the top.
    static func image(
        of text: String, font: NSFont, color: NSColor, appearance: NSAppearance,
        size: NSSize, origin: NSPoint, scale: CGFloat
    ) -> CGImage? {
        var cgColor = CGColor(gray: 0, alpha: 1)
        appearance.performAsCurrentDrawingAppearance { cgColor = color.cgColor }
        let width = Int((size.width * scale).rounded(.up)), height = Int((size.height * scale).rounded(.up))
        guard width > 0, height > 0, let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: cgColor,
        ]))
        // The context's y runs upward.
        context.textPosition = CGPoint(x: origin.x, y: size.height - origin.y)
        CTLineDraw(line, context)
        return context.makeImage()
    }
}

/// Holds the letter copies above the text. It never takes clicks.
final class OverlayView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
