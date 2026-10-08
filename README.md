# Blankr.

A minimal, native **macOS** notes app: open it, write, close. Nothing else in the way.

**Download the app:** grab the latest DMG from **[GitHub Releases](https://github.com/sabiqsabry/blankr/releases/latest)** or **[Products on sabiq.dev](https://sabiq.dev/products)**. This repository holds **source code** for developers and for the upcoming Windows version.

---

## Why Blankr.

- **Browser-style tabs** — several documents at once; each tab keeps its own text, formatting, and optional file association.
- **Auto-save** — when you close a tab, quit, or shut down, every tab with content is saved: back to the file it was opened from, or to your **Desktop** as `<tab title>.txt` (or a timestamp when untitled). Notes with formatting are saved as `.rtf` so it isn't lost. Existing files are never overwritten — a clash becomes `Notes 2.txt`.
- **Picks up where you left off** — open tabs come back on the next launch.
- **Rename tabs** — double-click a tab title to give it a custom name; a note Blankr. saved for you is renamed on disk to match.
- **Markdown viewer** — `.md` files open fully rendered (headings, tables, task lists, highlighted code blocks, images, links); flip to the source with the pencil.
- **Code viewer** — 80+ languages detected from the file (JS/TS, Python, Swift, Java, Go, Rust, C/C++, HTML/CSS, JSON, YAML, SQL, shell…) and shown with syntax highlighting and line numbers, structure untouched. Read-only by default; unlock to edit. ⌘F to find.
- **Zoom that fits your display** — a comfortable default is picked from each monitor's size and resolution (and re-picked when you move to another screen); ⌘= / ⌘- / ⌘0 adjust on top of it, text stays sharp.
- **Quiet formatting** — bold, italic, underline, size, alignment, checklists and numbered lists (Enter continues the list, Enter on an empty item ends it) from a slim side panel.
- **Line numbers** — optional for every tab (notes too); off by default, toggle from the panel (#) or ⌥⌘L.
- **Copy line breaks** — optional checkbox in the panel: include real line breaks in copied text, or flatten to a single line for pasting elsewhere.
- **Privacy** — fully offline, no telemetry, opens text, Markdown and code from Finder (*Open With*) or ⌘O. Markdown previews run with JavaScript disabled; they do load images a document links to.

Requires **macOS 13 (Ventura)** or later.

---

## Download (end users)

| Where | Link |
|--------|------|
| Latest release (DMG) | **[GitHub Releases](https://github.com/sabiqsabry/blankr/releases/latest)** |
| Product page (installers & context) | **[sabiq.dev/products](https://sabiq.dev/products)** |
| Source & issues | **[github.com/sabiqsabry/blankr](https://github.com/sabiqsabry/blankr)** |

Builds aren't notarized by Apple yet, so the first launch shows a **Gatekeeper** warning. Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to Blankr (once).

---

## Build from source (macOS)

1. Clone this repository:

   ```bash
   git clone https://github.com/sabiqsabry/blankr.git
   cd blankr
   ```

2. Open `Blankr.xcodeproj` in **Xcode** and run the **Blankr** scheme, or from Terminal:

   ```bash
   xcodebuild -scheme Blankr -configuration Release -destination 'platform=macOS' build
   ```

3. The built app is under Xcode’s Derived Data output, or use the helper script to produce a **DMG** locally:

   ```bash
   ./scripts/build-release-dmg.sh
   ```

   Output: `dist/Blankr-<version>-macOS.dmg` (drag **Blankr.** into **Applications** in the disk image).

---

## Publishing a release (maintainers)

1. Run `./scripts/build-release-dmg.sh` — output is `dist/Blankr-<version>-macOS.dmg`.
2. Upload that DMG to **[sabiq.dev/products](https://sabiq.dev/products)** (or your CDN) so visitors can install.
3. Optionally attach the same file to **[GitHub Releases](https://github.com/sabiqsabry/blankr/releases)** for direct downloads from the repo.

---

## Windows

The **`BlankrWindows/`** solution is a starter for the WinUI port. This repo is the shared starting point: pull on your PC and evolve the UI and persistence there while keeping product behavior aligned with the macOS version.

---

## Project layout

| Path | Purpose |
|------|---------|
| `Blankr/` | Swift sources (SwiftUI + AppKit editor) |
| `Blankr/Viewer/` | Markdown rendering, language detection, syntax highlighting |
| `Blankr/Resources/ThirdParty/` | Bundled [highlight.js](https://highlightjs.org) 11.9.0 (BSD-3) and [marked](https://marked.js.org) 12.0.2 (MIT), with licenses |
| `Blankr.xcodeproj/` | Xcode project |
| `BlankrWindows/` | WinUI starter for the Windows port |
| `scripts/build-release-dmg.sh` | Optional release packaging |

---

## License & credits

**Blankr.** — [Sabiq Sabry](https://sabiq.dev) / novusian.

If you like the app, sharing **[sabiq.dev/products](https://sabiq.dev/products)** helps others find it.
