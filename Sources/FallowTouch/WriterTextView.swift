#if os(iOS)
import UIKit

/// The writing surface. Bold and italic (⌘B and ⌘I, and the edit menu's Format items) write
/// Markdown's marks, as on the Mac, since Fallow's text is plain; the other text styles are off.
final class WriterTextView: UITextView {
    override func toggleBoldface(_ sender: Any?) { toggle(.bold) }
    override func toggleItalics(_ sender: Any?) { toggle(.italic) }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        switch action {
        case #selector(toggleBoldface(_:)), #selector(toggleItalics(_:)): return isEditable
        case #selector(toggleUnderline(_:)): return false
        default: return super.canPerformAction(action, withSender: sender)
        }
    }

    /// Adds or removes the marks as one edit, so it's one step to undo.
    private func toggle(_ emphasis: Emphasis) {
        let edit = emphasis.toggle(in: text as NSString, selection: selectedRange)
        guard let start = position(from: beginningOfDocument, offset: edit.range.location),
              let end = position(from: start, offset: edit.range.length),
              let range = textRange(from: start, to: end),
              delegate?.textView?(self, shouldChangeTextIn: edit.range, replacementText: edit.text) ?? true
        else { return }
        replace(range, withText: edit.text)
        selectedRange = edit.selection
        undoManager?.setActionName(emphasis.title)
    }
}
#endif
