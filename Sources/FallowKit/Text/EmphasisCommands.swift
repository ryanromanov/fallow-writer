import AppKit

extension WriterTextView {
    @objc func toggleBold(_ sender: Any?) { toggle(.bold) }
    @objc func toggleItalic(_ sender: Any?) { toggle(.italic) }

    private func toggle(_ emphasis: Emphasis) {
        guard isEditable, let storage = textStorage else { return }
        letters.finishAll()
        let edit = emphasis.toggle(in: storage.string as NSString, selection: selectedRange())
        guard shouldChangeText(in: edit.range, replacementString: edit.text) else { return }
        storage.replaceCharacters(in: edit.range, with: edit.text)
        didChangeText()
        setSelectedRange(edit.selection)
        undoManager?.setActionName(emphasis.title)
    }
}
