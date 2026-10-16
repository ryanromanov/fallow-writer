# Fallow

A quiet place to write. Fallow is a native macOS app for distraction-free writing: just your words in a centered column on a soft background. The window's controls fade away while you type and come back when you move the mouse.

It's named after fallow ground, a field left to rest before it's planted again.

## Features
- Plain text and Markdown files (`.txt`, `.md`), with autosave and version history
- A centered writing column with typewriter scrolling, so the line you're typing stays in the middle of the window
- Serif, sans serif or monospaced type (the system's own fonts), adjustable size and line spacing
- Light and dark appearance, and native full screen (⌃⌘F)
- A live word count
- Sandboxed: Fallow can only open the files you choose

Coming later: ambient sound and keystroke sounds, more backgrounds, and export.

## Building
Fallow is a Swift package and needs no Xcode project. With the Command Line Tools installed (Swift 6 or later), on macOS 13 or later:

```sh
scripts/bundle.sh    # builds Fallow.app
open Fallow.app
scripts/test.sh      # runs the tests
```

## License
MIT. See [LICENSE](LICENSE). Fallow is not affiliated with OmmWriter.
