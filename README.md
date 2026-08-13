# ScrawlMD

Convert handwritten notes, typed documents, and scanned PDFs into clean, structured Markdown — powered by the Gemini API.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange)

---

## Features

- **Drag & drop** images (JPG, PNG, HEIC, TIFF) or PDFs directly onto the app
- **Multi-file support** — drop several files at once; each is converted separately with its own labeled output section
- **Multi-page PDFs** — every page is sent to the model and transcribed in order
- **iPhone camera import** — one-click trigger of macOS's built-in "Import from iPhone → Take a Picture" via Finder, with automatic import and conversion when the photo lands on the Desktop
- **Two conversion modes**
  - *Verbatim* — faithful transcription, preserving original wording and layout
  - *Clean Up* — grammar-corrected, restructured, well-formatted Markdown
- **Editable output** — result is a full text editor; tweak before copying
- **Copy All** — copies the complete Markdown to the clipboard in one click
- **Dev log panel** — real-time log viewer under Dev → View Logs

---

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon (arm64)
- A [Gemini API key](https://aistudio.google.com/app/apikey) (free tier available)
- Xcode command-line tools (`xcode-select --install`)

---

## Getting Started

### 1. Clone the repo

```bash
git clone https://github.com/mecaneer23/scrawl-md.git
cd scrawl-md
```

### 2. Build

```bash
bash build.sh
```

This compiles the app and produces `ScrawlMD.app` in the project directory.

### 3. Set your API key

Either pass it as an environment variable at launch:

```bash
GEMINI_API_KEY=AIza... open ScrawlMD.app
```

Or enter it in-app via the **⚙** button in the top-right corner. The key is stored in app preferences and persists across launches.

### 4. Run

```bash
open ScrawlMD.app
```

---

## Usage

### Converting an image or PDF

1. Drag one or more image files or PDFs onto the drop zone, **or** click **📷 Take Photo** to import directly from your iPhone.
2. Select a conversion mode: **Verbatim** or **Clean Up**.
3. Click **Convert to Markdown** (or press Return).
4. The result appears in the output box. Edit if needed, then click **Copy All**.

When multiple files are dropped, each is converted in sequence. The output is divided into sections:

```
## document-name

<converted markdown>

---

## another-document

<converted markdown>
```

### iPhone camera import

The **📷 Take Photo** button automates the macOS "Import from iPhone" workflow:

1. Click the button — the app activates Finder and right-clicks the Desktop to open the context menu.
2. It selects **Import from iPhone → Take a Picture** via the Accessibility API.
3. Take the photo on your iPhone.
4. The image lands on the Desktop, is automatically picked up, deleted, and sent for conversion.

> **First run:** macOS will prompt you to grant Accessibility access. Go to **System Settings → Privacy & Security → Accessibility** and enable ScrawlMD, then click the button again.

---

## Project Structure

| File | Purpose |
|------|---------|
| `main.swift` | App entry point |
| `AppDelegate.swift` | Window setup, menu bar, log panel |
| `MainViewController.swift` | Main UI, import flow, Desktop monitor, AX automation |
| `ImageDropZone.swift` | Drag-and-drop target; handles images and multi-page PDFs |
| `GeminiAPI.swift` | Gemini API client with retry/backoff |
| `Models.swift` | `ConversionMode`, `APIError`, `GeminiInput`, `InputGroup` |
| `Logger.swift` | Shared logger with `NotificationCenter`-based live updates |
| `build.sh` | Build script — compiles and bundles into `ScrawlMD.app` |

---

## Configuration

| Method | Details |
|--------|---------|
| Environment variable | `GEMINI_API_KEY=AIza... open ScrawlMD.app` |
| In-app settings | Click **⚙** → enter key → Save |

The environment variable takes precedence over the stored preference.

---

## License

MIT
