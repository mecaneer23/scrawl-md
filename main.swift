import AppKit
import Foundation

// MARK: - Enums

enum ConversionMode {
    case verbatim, cleaned
}

enum APIError: Error, LocalizedError {
    case noAPIKey
    case imageConversionFailed
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key set. Click the ⚙ button to enter your Anthropic API key."
        case .imageConversionFailed:
            return "Failed to process the image."
        case .invalidResponse:
            return "Unexpected response from Claude API."
        case .apiError(let msg):
            return "API error: \(msg)"
        }
    }
}

// MARK: - Claude API

struct ClaudeAPI {
    static func convert(image: NSImage, mode: ConversionMode, apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else { throw APIError.noAPIKey }

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            throw APIError.imageConversionFailed
        }
        let base64 = jpegData.base64EncodedString()

        let prompt: String
        switch mode {
        case .verbatim:
            prompt = """
            Transcribe this handwritten note or document into markdown as verbatim as possible. \
            Preserve the exact words, phrasing, and layout. Only use markdown formatting (headings, \
            bullets, bold) where clear visual structure exists in the original — don't add structure \
            that isn't there. Output only the markdown, no preamble or commentary.
            """
        case .cleaned:
            prompt = """
            Convert this handwritten note or document into clean, well-structured markdown. \
            Fix spelling and grammar errors, improve clarity and flow, organize content logically, \
            and use appropriate markdown formatting. Output only the polished markdown, no preamble \
            or commentary.
            """
        }

        let body: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "max_tokens": 4096,
            "messages": [[
                "role": "user",
                "content": [
                    [
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": base64
                        ]
                    ],
                    ["type": "text", "text": prompt]
                ]
            ]]
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw APIError.apiError(message)
        }

        guard let content = (json["content"] as? [[String: Any]])?.first,
              let text = content["text"] as? String else {
            throw APIError.invalidResponse
        }
        return text
    }
}

// MARK: - Image Drop Zone

class ImageDropZone: NSImageView {
    var onImageSet: ((NSImage) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isEditable = true
        imageScaling = .scaleProportionallyUpOrDown
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }

        func showImportMenu() {
        let location = NSPoint(x: bounds.midX, y: bounds.midY)
        guard let window else { return }
        let windowLocation = convert(location, to: nil)
        guard let event = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: windowLocation,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ), let menu = menu(for: event) else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    // Called when image is set via drag-drop OR Import from iPhone
    override var image: NSImage? {
        didSet {
            guard let img = image else { return }
            onImageSet?(img)
        }
    }
}

// MARK: - Main View Controller

class MainViewController: NSViewController {

    private var dropZone: ImageDropZone!
    private var placeholderLabel: NSTextField!
    private var modeControl: NSSegmentedControl!
    private var convertButton: NSButton!
    private var spinner: NSProgressIndicator!
    private var resultScrollView: NSScrollView!
    private var resultView: NSTextView!
    private var copyButton: NSButton!
    private var settingsButton: NSButton!
    private var statusLabel: NSTextField!
    private var importButton: NSButton!

    private var capturedImage: NSImage?
    private var isProcessing = false
    private var autoConvertNext = false

    private var apiKey: String {
        get {
            // Prefer environment variable, fall back to UserDefaults
            if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !envKey.isEmpty {
                return envKey
            }
            return UserDefaults.standard.string(forKey: "anthropicAPIKey") ?? ""
        }
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 620))
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    private func buildUI() {
        let padding: CGFloat = 20

        // Settings button (gear, top-right)
        settingsButton = NSButton(title: "⚙", target: self, action: #selector(openSettings))
        settingsButton.bezelStyle = .rounded
        settingsButton.font = NSFont.systemFont(ofSize: 16)
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(settingsButton)

        // Mode segmented control
        modeControl = NSSegmentedControl(labels: ["Verbatim", "Clean Up"], trackingMode: .selectOne, target: nil, action: nil)
        modeControl.selectedSegment = 0
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(modeControl)

        // Image drop zone
        dropZone = ImageDropZone(frame: .zero)
        dropZone.translatesAutoresizingMaskIntoConstraints = false
        dropZone.onImageSet = { [weak self] image in
            self?.imageWasSet(image)
        }
        view.addSubview(dropZone)

        // Import from iPhone button
        importButton = NSButton(title: "📷  Import from iPhone", target: self, action: #selector(importFromPhone))
        importButton.bezelStyle = .rounded
        importButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(importButton)

        // Placeholder label inside drop zone
        placeholderLabel = NSTextField(labelWithString: "Click \u{201C}Import from iPhone\u{201D} above\nor drag & drop an image here")
        placeholderLabel.alignment = .center
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.font = NSFont.systemFont(ofSize: 13)
        placeholderLabel.isSelectable = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholderLabel)

        // Convert button
        convertButton = NSButton(title: "Convert to Markdown", target: self, action: #selector(convert))
        convertButton.bezelStyle = .rounded
        convertButton.keyEquivalent = "\r"
        convertButton.isEnabled = false
        convertButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(convertButton)

        // Spinner
        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.isIndeterminate = true
        spinner.isHidden = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)

        // Status label
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        // Result text view in scroll view
        resultScrollView = NSScrollView()
        resultScrollView.hasVerticalScroller = true
        resultScrollView.hasHorizontalScroller = false
        resultScrollView.autohidesScrollers = true
        resultScrollView.borderType = .lineBorder
        resultScrollView.wantsLayer = true
        resultScrollView.layer?.cornerRadius = 8
        resultScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(resultScrollView)

        resultView = NSTextView()
        resultView.isEditable = true
        resultView.isSelectable = true
        resultView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        resultView.textContainerInset = NSSize(width: 8, height: 8)
        resultView.isAutomaticSpellingCorrectionEnabled = false
        resultView.isAutomaticQuoteSubstitutionEnabled = false
        resultScrollView.documentView = resultView

        // Copy button
        copyButton = NSButton(title: "Copy All", target: self, action: #selector(copyAll))
        copyButton.bezelStyle = .rounded
        copyButton.isEnabled = false
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(copyButton)

        // MARK: Constraints
        NSLayoutConstraint.activate([
            // Settings button top-right
            settingsButton.topAnchor.constraint(equalTo: view.topAnchor, constant: padding),
            settingsButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),

            // Mode control top-left
            modeControl.centerYAnchor.constraint(equalTo: settingsButton.centerYAnchor),
            modeControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),

            // Import button (below mode control, left side)
            importButton.centerYAnchor.constraint(equalTo: modeControl.centerYAnchor),
            importButton.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -8),

            // Drop zone
            dropZone.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 12),
            dropZone.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            dropZone.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            dropZone.heightAnchor.constraint(equalToConstant: 180),

            // Placeholder centered in drop zone
            placeholderLabel.centerXAnchor.constraint(equalTo: dropZone.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: dropZone.centerYAnchor),

            // Convert button
            convertButton.topAnchor.constraint(equalTo: dropZone.bottomAnchor, constant: 12),
            convertButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            convertButton.widthAnchor.constraint(equalToConstant: 180),

            // Spinner (next to button)
            spinner.centerYAnchor.constraint(equalTo: convertButton.centerYAnchor),
            spinner.leadingAnchor.constraint(equalTo: convertButton.trailingAnchor, constant: 8),
            spinner.widthAnchor.constraint(equalToConstant: 18),
            spinner.heightAnchor.constraint(equalToConstant: 18),

            // Status label
            statusLabel.topAnchor.constraint(equalTo: convertButton.bottomAnchor, constant: 6),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            // Result scroll view
            resultScrollView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            resultScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            resultScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            resultScrollView.bottomAnchor.constraint(equalTo: copyButton.topAnchor, constant: -10),

            // Copy button bottom-right
            copyButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -padding),
            copyButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            copyButton.widthAnchor.constraint(equalToConstant: 100),
        ])

        // Wire up result view width to scroll view
        resultView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            resultView.widthAnchor.constraint(equalTo: resultScrollView.widthAnchor)
        ])
    }

    private func imageWasSet(_ image: NSImage) {
        capturedImage = image
        placeholderLabel.isHidden = true
        convertButton.isEnabled = true
        setStatus("")
        if autoConvertNext {
            autoConvertNext = false
            convert()
        }
    }

    @objc private func importFromPhone() {
        autoConvertNext = true
        dropZone.showImportMenu()
        // If user dismissed without importing, cancel auto-convert
        DispatchQueue.main.async { [weak self] in
            guard let self, self.autoConvertNext else { return }
            if self.capturedImage == nil { self.autoConvertNext = false }
        }
    }

    private func clearImage() {
        capturedImage = nil
        dropZone.image = nil
        placeholderLabel.isHidden = false
        convertButton.isEnabled = false
    }

    @objc private func convert() {
        guard let image = capturedImage, !isProcessing else { return }

        let mode: ConversionMode = modeControl.selectedSegment == 0 ? .verbatim : .cleaned
        let key = apiKey

        isProcessing = true
        convertButton.isEnabled = false
        spinner.isHidden = false
        spinner.startAnimation(nil)
        setStatus("Sending to Claude...")
        resultView.string = ""
        copyButton.isEnabled = false

        Task {
            do {
                let markdown = try await ClaudeAPI.convert(image: image, mode: mode, apiKey: key)
                await MainActor.run {
                    resultView.string = markdown
                    copyButton.isEnabled = true
                    setStatus("Done.")
                    clearImage()
                }
            } catch {
                await MainActor.run {
                    setStatus("Error: \(error.localizedDescription)")
                }
            }
            await MainActor.run {
                isProcessing = false
                convertButton.isEnabled = capturedImage != nil
                spinner.stopAnimation(nil)
                spinner.isHidden = true
            }
        }
    }

    @objc private func copyAll() {
        let text = resultView.string
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copyButton.title = "Copied!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.copyButton.title = "Copy All"
        }
    }

    @objc private func openSettings() {
        let alert = NSAlert()
        alert.messageText = "Anthropic API Key"
        alert.informativeText = "Enter your API key. It will be stored in app preferences.\nYou can also set the ANTHROPIC_API_KEY environment variable."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "sk-ant-..."
        field.stringValue = UserDefaults.standard.string(forKey: "anthropicAPIKey") ?? ""
        alert.accessoryView = field

        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            let value = field.stringValue.trimmingCharacters(in: .whitespaces)
            UserDefaults.standard.set(value, forKey: "anthropicAPIKey")
        }
    }

    private func setStatus(_ msg: String) {
        statusLabel.stringValue = msg
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Notes to Markdown"
        window.minSize = NSSize(width: 500, height: 500)
        window.center()

        let vc = MainViewController()
        window.contentViewController = vc
        window.makeKeyAndOrderFront(nil)

        buildMenu()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    private func buildMenu() {
        let menuBar = NSMenu()

        let appMenuItem = NSMenuItem()
        menuBar.addItem(appMenuItem)
        let appMenu = NSMenu(title: "Notes to Markdown")
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit Notes to Markdown", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editMenuItem = NSMenuItem()
        menuBar.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        // These standard items enable Import from iPhone in the Edit menu
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")

        NSApp.mainMenu = menuBar
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
