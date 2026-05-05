# Blankr.

A minimal, native **macOS** notes app: open it, write, close. Nothing else in the way.

**Download the app:** visit **[Products on sabiq.dev](https://sabiq.dev/products)** for the latest macOS build (DMG and install notes). This repository holds **source code** for developers and for the upcoming Windows version.

---

## Why Blankr.

- **Browser-style tabs** — several documents at once; each tab keeps its own text and optional file association.
- **Auto-save** — when you close a tab or quit with unsaved content, a `.txt` is written to your **Desktop** with a timestamp (or back to an opened file when applicable).
- **Rename tabs** — double-click a tab title to give it a custom name; otherwise it stays **Untitled**.
- **Quiet formatting** — bold, italic, underline, size, alignment, and checklist lines from a slim side panel.
- **Copy line breaks** — optional checkbox in the panel: include real line breaks in copied text, or flatten to a single line for pasting elsewhere.
- **Privacy** — fully offline, no telemetry, opens `.txt` from Finder when you double-click.

Requires **macOS 13 (Ventura)** or later.

---

## Download (end users)

| Where | Link |
|--------|------|
| Product page (installers & context) | **[sabiq.dev/products](https://sabiq.dev/products)** |
| Source & issues | **[github.com/sabiqsabry/blankr](https://github.com/sabiqsabry/blankr)** |

Apple may show a **Gatekeeper** warning for builds that are not notarized by Apple. If that appears: **System Settings → Privacy & Security** and choose to open anyway, or right-click the app → **Open**.

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

## Windows

A **Windows** port is planned. This repo is the shared starting point: pull on your PC and evolve the UI and persistence there while keeping product behavior aligned with the macOS version.

---

## Project layout

| Path | Purpose |
|------|---------|
| `Blankr/` | Swift sources (SwiftUI + AppKit editor) |
| `Blankr.xcodeproj/` | Xcode project |
| `scripts/build-release-dmg.sh` | Optional release packaging |

---

## License & credits

**Blankr.** — [Sabiq Sabry](https://sabiq.dev) / novusian.

If you like the app, sharing **[sabiq.dev/products](https://sabiq.dev/products)** helps others find it.
