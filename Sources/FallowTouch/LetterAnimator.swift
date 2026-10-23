#if os(iOS)
import CoreText
import UIKit

/// Typed letters settle into place, as on the Mac: each one appears as a copy that fades in
/// and shrinks gently onto the spot where the real letter sits, and is swapped for the real one
/// when done.
///
/// While a letter animates, the real one is hidden with a TextKit 2 rendering attribute, which
/// changes how it's drawn but never the text, so a hidden letter can't be saved or undone.
/// Each animation shows its own letter again when its time is up, on a timer of its own, and
/// `finishAll()` ends every animation and shows every letter.
final class LetterAnimator {
    static var duration: CFTimeInterval = 0.28
    /// Room around each letter's box, so the settle animation's larger start isn't clipped.
    static let pad: CGFloat = 8

    private struct Running {
        let range: NSRange
        let layer: CALayer
        let timer: Timer
        /// Where the letter was when the animation began, to notice if the line reflowed.
        let rect: CGRect
    }

    private unowned let textView: UITextView
    /// Holds the letter copies above the text, in the text view's content coordinates.
    private let overlay = UIView()
    private var running: [Running] = []

    var runningCount: Int { running.count }

    init(textView: UITextView) {
        self.textView = textView
        overlay.isUserInteractionEnabled = false
        textView.addSubview(overlay)
    }

    /// Settles every letter before and after each undo and redo.
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
        let storage = textView.textStorage
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
        let string = storage.attributedSubstring(from: range)
        guard string.string.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted) != nil,
              let font = string.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        else { return }

        // A letter inserted before running ones moves them, and a word wrapping to the next
        // line moves its letters: those copies would land in the wrong place, so end them now.
        textView.layoutIfNeeded()
        for item in running where item.range.location >= range.location || moved(item) {
            finish(item)
        }
        guard let rect = characterRect(for: range), let baseline = baseline(at: range.location),
              let textRange = textRange(for: range)
        else { return }

        let layer = CALayer()
        let scale = textView.traitCollection.displayScale
        // Put the layer on whole pixels so its image isn't resampled, and draw the letter
        // inside it at its exact (fractional) position instead.
        let box = rect.insetBy(dx: -Self.pad, dy: -Self.pad)
        let origin = CGPoint(x: (box.minX * scale).rounded(.down) / scale, y: (box.minY * scale).rounded(.down) / scale)
        layer.frame = CGRect(origin: origin, size: CGSize(
            width: ((box.maxX - origin.x) * scale).rounded(.up) / scale,
            height: ((box.maxY - origin.y) * scale).rounded(.up) / scale))
        layer.contentsScale = scale
        layer.contents = Self.image(
            of: string.string, font: font, color: Palette.text.resolvedColor(with: textView.traitCollection).cgColor,
            size: layer.frame.size, origin: CGPoint(x: rect.minX - origin.x, y: baseline - origin.y), scale: scale)
        textView.bringSubviewToFront(overlay)
        overlay.layer.addSublayer(layer)

        // The real letter comes back when the copy's time is up, whatever Core Animation does.
        let timer = Timer(timeInterval: Self.duration, repeats: false) { [weak self, layer] _ in
            guard let self, let item = running.first(where: { $0.layer === layer }) else { return }
            finish(item)
        }
        RunLoop.main.add(timer, forMode: .common)
        running.append(Running(range: range, layer: layer, timer: timer, rect: rect))
        textView.textLayoutManager?.addRenderingAttribute(.foregroundColor, value: UIColor.clear, for: textRange)

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

    /// Ends every animation at once and shows every letter.
    func finishAll() {
        for item in running { finish(item) }
        if let layout = textView.textLayoutManager {
            show(layout.documentRange)
        }
    }

    private func finish(_ item: Running) {
        guard let index = running.firstIndex(where: { $0.layer === item.layer }) else { return }
        running.remove(at: index)
        item.timer.invalidate()
        item.layer.removeFromSuperlayer()
        // If edits have shifted the text, this may show other letters, which is harmless.
        if let range = textRange(for: NSIntersectionRange(item.range, NSRange(location: 0, length: textView.textStorage.length))) {
            show(range)
        }
    }

    /// Shows the letters in `range` again. Removing a rendering attribute doesn't redraw the
    /// text by itself, so this lays the range out again too.
    private func show(_ range: NSTextRange) {
        guard let layout = textView.textLayoutManager else { return }
        layout.removeRenderingAttribute(.foregroundColor, for: range)
        layout.invalidateLayout(for: range)
        textView.setNeedsLayout()
    }

    private func moved(_ item: Running) -> Bool {
        guard let rect = characterRect(for: item.range) else { return true }
        // Kerning nudges a letter by a fraction of a point as the next one arrives; a reflow
        // moves it much further.
        return abs(rect.minX - item.rect.minX) > 2 || abs(rect.minY - item.rect.minY) > 2
    }

    // MARK: Geometry, in the text view's content coordinates

    private func textRange(for range: NSRange) -> NSTextRange? {
        guard range.length > 0, let content = textView.textLayoutManager?.textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: range.location),
              let end = content.location(start, offsetBy: range.length)
        else { return nil }
        return NSTextRange(location: start, end: end)
    }

    private func characterRect(for range: NSRange) -> CGRect? {
        guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
              let end = textView.position(from: start, offset: range.length),
              let textRange = textView.textRange(from: start, to: end)
        else { return nil }
        let rect = textView.firstRect(for: textRange)
        return rect.isNull || rect.isInfinite || rect.isEmpty ? nil : rect
    }

    /// The baseline of the line holding the character at `index`.
    private func baseline(at index: Int) -> CGFloat? {
        guard let layout = textView.textLayoutManager, let content = layout.textContentManager,
              let location = content.location(content.documentRange.location, offsetBy: index),
              let fragment = layout.textLayoutFragment(for: location)
        else { return nil }
        let paragraphStart = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
        let offset = index - paragraphStart
        guard let line = fragment.textLineFragments.first(where: { NSLocationInRange(offset, $0.characterRange) })
                ?? fragment.textLineFragments.last
        else { return nil }
        return textView.textContainerInset.top + fragment.layoutFragmentFrame.minY + line.typographicBounds.minY + line.glyphOrigin.y
    }

    /// Draws `text` into an image `size` big, starting `origin.x` points from the left with its
    /// baseline `origin.y` points from the top.
    static func image(of text: String, font: UIFont, color: CGColor, size: CGSize, origin: CGPoint, scale: CGFloat) -> CGImage? {
        let width = Int((size.width * scale).rounded(.up)), height = Int((size.height * scale).rounded(.up))
        guard width > 0, height > 0, let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color,
        ]))
        // The context's y runs upward.
        context.textPosition = CGPoint(x: origin.x, y: size.height - origin.y)
        CTLineDraw(line, context)
        return context.makeImage()
    }
}
#endif
