# ScrawlMD

Convert handwritten notes, typed documents, and scanned PDFs into clean, structured Markdown — powered by your choice of AI provider.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange)

---

## Features

- **Drag & drop** images (JPG, PNG, HEIC, TIFF) or PDFs directly onto the app, or click the drop zone to open a file picker
- **Multi-file support** — drop several files at once; each is converted separately with its own labeled output section
- **Multi-page PDFs** — every page is sent to the model and transcribed in order
- **iPhone camera import** — uses macOS Continuity Camera to capture photos directly from your iPhone; take multiple shots before converting
- **Two conversion modes**
  - *Verbatim* — faithful transcription, preserving original wording and layout
  - *Clean Up* — grammar-corrected, restructured, well-formatted Markdown
- **Side-by-side output window** — original document preview on the left, editable Markdown on the right; panes are independently resizable
- **Document picker** — when multiple files are converted, switch between them with a dropdown; the preview updates to match
- **Zoom controls** — scale the document preview from 10% to 400%
- **Editable output** — tweak the Markdown before saving
- **Save options** — copy to clipboard, save as a single combined `.md` file, or save each document separately
- **Progress bar** — advances proportionally to input size during conversion
- **Multiple AI providers** — switch between Gemini, Groq, and OpenRouter in Settings; all models are user-configurable
- **Dev log panel** — real-time log viewer under Dev → View Logs

---

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon (arm64)
- An API key for at least one supported provider (see [Configuration](#configuration))
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

Or enter it in-app via the **⚙** button in the top-right corner. Keys are stored in app preferences and persist across launches.

### 4. Run

```bash
open ScrawlMD.app
```

---

## Usage

### Converting an image or PDF

1. Drag one or more image files or PDFs onto the drop zone, click the drop zone to open a file picker, or click **📷 Take Photo** to import from your iPhone.
2. Select a conversion mode: **Verbatim** or **Clean Up**.
3. Click **Convert to Markdown** (or press Return).
4. An output window opens with the document preview on the left and Markdown on the right. Edit if needed, then copy or save.

When multiple files are converted, the output is divided into labeled sections:

```
## document-name

<converted markdown>

---

## another-document

<converted markdown>
```

### iPhone camera import

The **📷 Take Photo** button uses macOS Continuity Camera:

1. Click the button and select **Take a Picture** (or **Scan Documents**) from the menu that appears.
2. Your iPhone's camera opens — take as many photos as needed.
3. Each photo is added to the queue. The status bar shows the running count.
4. When done, click **Convert to Markdown**.

Your iPhone must be signed into the same Apple ID and be nearby with Wi-Fi and Bluetooth enabled.

---

## Project Structure

| File | Purpose |
|------|---------|
| `main.swift` | App entry point |
| `AppDelegate.swift` | Window setup, menu bar, log panel |
| `MainViewController.swift` | Main UI, Continuity Camera integration |
| `ImageDropZone.swift` | Drag-and-drop and file-picker target; handles images and multi-page PDFs |
| `GeminiAPI.swift` | Gemini API client (gemini-3.5-flash) with retry/backoff |
| `GroqAPI.swift` | Groq API client with image batching (3-image limit per request) |
| `OpenRouterAPI.swift` | OpenRouter API client |
| `OutputViewController.swift` | Side-by-side output window with preview, zoom, and save logic |
| `Models.swift` | Shared types: `LLMProvider`, `ConversionMode`, `APIError`, `GeminiInput`, `InputGroup` |
| `Logger.swift` | Shared logger with `NotificationCenter`-based live updates |
| `build.sh` | Build script — compiles and bundles into `ScrawlMD.app` |

---

## Configuration

Open **⚙ Settings** to configure providers and API keys.

| Provider | Key prefix | Default model | Free tier |
|----------|-----------|---------------|-----------|
| **Gemini** | `AIza…` | `gemini-3.5-flash` | ✅ Yes |
| **Groq** | `gsk_…` | `qwen/qwen3.6-27b` | ⚠️ Limited (8k TPM) |
| **OpenRouter** | `sk-or-…` | `dots-studio/dots-3-note-preview:free` | ⚠️ Limited |

All model IDs are editable in Settings — enter any model ID supported by the chosen provider.

Environment variables take precedence over stored keys:

```bash
GEMINI_API_KEY=AIza... open ScrawlMD.app
GROQ_API_KEY=gsk_... open ScrawlMD.app
OPENROUTER_API_KEY=sk-or-... open ScrawlMD.app
```

---

## License

MIT
