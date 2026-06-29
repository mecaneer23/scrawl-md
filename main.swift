import AppKit
import AVFoundation
import ApplicationServices
import Foundation

// MARK: - Logger

final class Logger {
    static let shared = Logger()
    private(set) var entries: [String] = []
    private let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static let didAddEntry = Notification.Name("LoggerDidAddEntry")

    func log(_ message: String) {
        let timestamp = df.string(from: Date())
        let entry = "[\(timestamp)] \(message)"
        entries.append(entry)
        NSLog("[NTM] %@", message)
        NotificationCenter.default.post(name: Logger.didAddEntry, object: entry)
    }

    var text: String { entries.joined(separator: "\n") }
}

private func log(_ msg: String) {
    Logger.shared.log(msg)
}

// MARK: - Continuity Camera

class ContinuityCameraSession: NSObject, AVCapturePhotoCaptureDelegate {
    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    var onCapture: ((NSImage) -> Void)?
    var onError: ((String) -> Void)?

    static func discover() -> AVCaptureDevice? {
        let allTypes: [AVCaptureDevice.DeviceType] = [.continuityCamera, .external, .builtInWideAngleCamera]
        let all = AVCaptureDevice.DiscoverySession(
            deviceTypes: allTypes,
            mediaType: .video,
            position: .unspecified
        ).devices
        log("discover: all video devices = \(all.map { "\($0.localizedName) [\($0.deviceType.rawValue)]" })")
        return all.first { $0.deviceType == .continuityCamera }
            ?? all.first { $0.deviceType == .external }
    }

    func prepare(device: AVCaptureDevice) throws {
        session.beginConfiguration()
        let input = try AVCaptureDeviceInput(device: device)
        session.addInput(input)
        session.addOutput(photoOutput)
        session.commitConfiguration()
    }

    func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspect
        return layer
    }

    func start() { session.startRunning() }
    func stop() { session.stopRunning() }

    func capturePhoto() {
        guard session.isRunning else { log("capturePhoto: session not running"); return }
        let settings = AVCapturePhotoSettings()
        log("capturePhoto: requesting photo")
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error {
            log("photoOutput error: \(error.localizedDescription)")
            DispatchQueue.main.async { self.onError?(error.localizedDescription) }
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let image = NSImage(data: data) else {
            log("photoOutput: failed to convert photo to NSImage")
            DispatchQueue.main.async { self.onError?("Failed to process captured photo.") }
            return
        }
        log("photoOutput: got image size=\(image.size)")
        DispatchQueue.main.async { self.onCapture?(image) }
    }
}

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
            return "No API key set. Click the ⚙ button to enter your Gemini API key."
        case .imageConversionFailed:
            return "Failed to process the image."
        case .invalidResponse:
            return "Unexpected response from Gemini API."
        case .apiError(let msg):
            return "API error: \(msg)"
        }
    }
}

// MARK: - Gemini API

struct GeminiAPI {
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
            "contents": [[
                "parts": [
                    ["inline_data": ["mime_type": "image/jpeg", "data": base64]],
                    ["text": prompt]
                ]
            ]]
        ]

        let urlStr = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)"
        var request = URLRequest(url: URL(string: urlStr)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw APIError.apiError(message)
        }

        guard let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
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
    private var desktopMonitor: DispatchSourceFileSystemObject?
    private var monitorStartTime: Date?
    private let desktopURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif", "png", "tiff", "tif"]

    private var apiKey: String {
        get {
            // Prefer environment variable, fall back to UserDefaults
            if let envKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !envKey.isEmpty {
                return envKey
            }
            return UserDefaults.standard.string(forKey: "geminiAPIKey") ?? ""
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
        importButton = NSButton(title: "📷  Take Photo", target: self, action: #selector(importFromPhone))
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
        log("imageWasSet: size=\(image.size), autoConvertNext=\(autoConvertNext)")
        capturedImage = image
        placeholderLabel.isHidden = true
        convertButton.isEnabled = true
        setStatus("")
        if autoConvertNext {
            log("imageWasSet: auto-triggering convert")
            autoConvertNext = false
            convert()
        }
    }

    @objc private func importFromPhone() {
        log("importFromPhone: button tapped")

        guard let finder = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.finder").first else {
            setStatus("Finder is not running.")
            return
        }

        // Probe AX directly rather than using AXIsProcessTrusted(), which breaks after
        // each re-sign because macOS keys the TCC entry to the binary's code signature.
        let probeEl = AXUIElementCreateApplication(finder.processIdentifier)
        var probeRef: CFTypeRef?
        let probeErr = AXUIElementCopyAttributeValue(probeEl, kAXTitleAttribute as CFString, &probeRef)
        log("importFromPhone: AX probe err=\(probeErr.rawValue) isTrusted=\(AXIsProcessTrusted())")

        if probeErr == .apiDisabled || probeErr == .notImplemented {
            let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
            setStatus("Enable Accessibility for Notes to Markdown in System Settings > Privacy, then click Take Photo again.")
            return
        }

        startDesktopMonitor()
        finder.activate(options: [])
        importButton.title = "⏳  Waiting… (click to cancel)"
        importButton.action = #selector(cancelDesktopMonitor)
        setStatus("Opening iPhone camera…")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.rightClickFinderDesktop(finderPID: finder.processIdentifier)
        }
    }
    private func rightClickFinderDesktop(finderPID: pid_t) {
        let finderApp = AXUIElementCreateApplication(finderPID)

        if let desktop = findFinderDesktop(in: finderApp) {
            log("rightClickFinderDesktop: found desktop \(axRole(desktop))/\(axSubrole(desktop))")
            let err = AXUIElementPerformAction(desktop, "AXShowMenu" as CFString)
            log("rightClickFinderDesktop: AXShowMenu err=\(err.rawValue)")
            if err == .success {
                pollForFinderContextMenu(finderPID: finderPID, attempt: 0)
                return
            }
            if let frame = axFrame(desktop) {
                log("rightClickFinderDesktop: clicking desktop frame \(frame)")
                postRightClick(at: CGPoint(x: frame.midX, y: frame.midY), finderPID: finderPID)
                return
            }
        }

        if let pt = safeDesktopPoint() {
            log("rightClickFinderDesktop: safeDesktopPoint \(pt)")
            postRightClick(at: pt, finderPID: finderPID)
        } else {
            log("rightClickFinderDesktop: no safe point found")
            setStatus("Could not find open desktop area. Right-click the desktop manually → Import from iPhone → Take a Picture")
        }
    }

    private func findFinderDesktop(in finderApp: AXUIElement) -> AXUIElement? {
        // The Finder desktop is an AXScrollArea (sometimes with subrole AXDesktopList).
        // It's a direct child of the Finder application element.
        let children = axChildren(finderApp)
        log("findFinderDesktop: Finder children = \(children.map { "\(axRole($0))/\(axSubrole($0)) '\(axTitle($0))'" })")
        let result = children.first {
            axRole($0) == "AXScrollArea"
            || axSubrole($0).localizedCaseInsensitiveContains("desktop")
            || axRole($0).localizedCaseInsensitiveContains("desktop")
        }
        log("findFinderDesktop: \(result == nil ? "not found" : "found \(axRole(result!))/\(axSubrole(result!))")")
        return result
    }

    private func safeDesktopPoint() -> CGPoint? {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let windowRects: [CGRect] = (CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] ?? [])
            .compactMap { info in
                guard let b = info[kCGWindowBounds as String] as? [String: CGFloat],
                      let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"]
                else { return nil }
                return CGRect(x: x, y: y, width: w, height: h)
            }
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        for screen in NSScreen.screens {
            let sf = screen.frame
            let cgRect = CGRect(x: sf.minX, y: primaryH - sf.maxY, width: sf.width, height: sf.height)
            let inset: CGFloat = 100
            for xf: CGFloat in [0.3, 0.5, 0.7, 0.2, 0.8] {
                for yf: CGFloat in [0.4, 0.6, 0.3, 0.7] {
                    let pt = CGPoint(x: cgRect.minX + cgRect.width * xf,
                                     y: cgRect.minY + inset + (cgRect.height - inset * 2) * yf)
                    if !windowRects.contains(where: { $0.contains(pt) }) { return pt }
                }
            }
        }
        return nil
    }

    private func postRightClick(at pt: CGPoint, finderPID: pid_t) {
        CGWarpMouseCursorPosition(pt)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown,
                                 mouseCursorPosition: pt, mouseButton: .right),
              let up   = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp,
                                 mouseCursorPosition: pt, mouseButton: .right) else {
            log("postRightClick: failed to create CGEvents"); return
        }
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
        log("postRightClick: posted at \(pt)")
        pollForFinderContextMenu(finderPID: finderPID, attempt: 0)
    }
    private func pollForFinderContextMenu(finderPID: pid_t, attempt: Int) {
        let finderApp = AXUIElementCreateApplication(finderPID)
        let topChildren = axChildren(finderApp)

        // Context menu may be a direct child of the app or a child of the desktop AXScrollArea.
        var candidates = topChildren
        for child in topChildren { candidates += axChildren(child) }
        log("pollForFinderContextMenu #\(attempt): searching \(candidates.count) elements, roles=\(candidates.map { axRole($0) }.filter { $0 == "AXMenu" })")

        if let menu = candidates.first(where: { axRole($0) == "AXMenu" }) {
            let items = axChildren(menu)
            log("pollForFinderContextMenu: found AXMenu items=\(axTitles(items))")
            clickImportFromiPhone(in: items)
            return
        }

        guard attempt < 10 else {
            log("pollForFinderContextMenu: gave up — falling back to manual")
            setStatus("Could not find context menu. Right-click your desktop manually → Import from iPhone → Take a Picture")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.pollForFinderContextMenu(finderPID: finderPID, attempt: attempt + 1)
        }
    }

    private func clickImportFromiPhone(in items: [AXUIElement]) {
        guard let importItem = items.first(where: {
            let t = axTitle($0)
            return t.localizedCaseInsensitiveContains("iPhone") || t.localizedCaseInsensitiveContains("Import")
        }) else {
            log("clickImportFromiPhone: not found in \(axTitles(items))")
            setStatus("Import from iPhone not found. Is your iPhone nearby?")
            return
        }
        log("clickImportFromiPhone: pressing '\(axTitle(importItem))'")
        AXUIElementPerformAction(importItem, kAXPressAction as CFString)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            // The submenu is a child of the menu item; its children are the actual items
            let submenuItems = self.axChildren(self.axChildren(importItem).first ?? importItem)
            log("clickImportFromiPhone: submenu items = \(self.axTitles(submenuItems))")
            self.clickTakeAPicture(in: submenuItems)
        }
    }

    private func clickTakeAPicture(in items: [AXUIElement]) {
        guard let item = items.first(where: {
            let t = axTitle($0)
            return t.localizedCaseInsensitiveContains("picture") || t.localizedCaseInsensitiveContains("photo")
        }) else {
            log("clickTakeAPicture: not found in \(axTitles(items))")
            setStatus("'Take a Picture' not found. Is your iPhone nearby?")
            return
        }
        log("clickTakeAPicture: clicking '\(axTitle(item))'")
        AXUIElementPerformAction(item, kAXPressAction as CFString)
        setStatus("Photo taken — importing…")
    }

    // MARK: - AX helpers
    private func axChildren(_ el: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &ref) == .success else { return [] }
        return (ref as? [AXUIElement]) ?? []
    }
    private func axTitle(_ el: AXUIElement) -> String {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &ref)
        return (ref as? String) ?? ""
    }
    private func axRole(_ el: AXUIElement) -> String {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &ref)
        return (ref as? String) ?? ""
    }
    private func axTitles(_ els: [AXUIElement]) -> [String] { els.map { axTitle($0) } }
    private func axSubrole(_ el: AXUIElement) -> String {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXSubroleAttribute as CFString, &ref)
        return (ref as? String) ?? ""
    }
    private func axFrame(_ el: AXUIElement) -> CGRect? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, "AXFrame" as CFString, &ref) == .success,
              let val = ref else { return nil }
        var rect = CGRect.zero
        AXValueGetValue(val as! AXValue, .cgRect, &rect)
        return rect.isEmpty ? nil : rect
    }

    @objc private func cancelDesktopMonitor() {
        log("cancelDesktopMonitor")
        stopDesktopMonitor()
        setStatus("")
        importButton.title = "📷  Take Photo"
        importButton.action = #selector(importFromPhone)
    }

    private func startDesktopMonitor() {
        stopDesktopMonitor()
        monitorStartTime = Date()
        log("startDesktopMonitor: watching \(desktopURL.path)")
        let fd = open(desktopURL.path, O_EVTONLY)
        guard fd >= 0 else { log("startDesktopMonitor: open() failed"); return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        src.setEventHandler { [weak self] in self?.checkDesktopForNewImage() }
        src.setCancelHandler { close(fd) }
        src.resume()
        desktopMonitor = src
    }

    private func stopDesktopMonitor() {
        desktopMonitor?.cancel()
        desktopMonitor = nil
        monitorStartTime = nil
    }

    private func checkDesktopForNewImage() {
        guard let startTime = monitorStartTime else { return }
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: desktopURL, includingPropertiesForKeys: keys, options: .skipsHiddenFiles
        ) else { return }

        for url in contents {
            guard Self.imageExtensions.contains(url.pathExtension.lowercased()) else { continue }
            guard let vals = try? url.resourceValues(forKeys: Set(keys)),
                  let created = vals.creationDate, created >= startTime else { continue }
            log("checkDesktopForNewImage: found \(url.lastPathComponent) created=\(created)")
            guard let image = NSImage(contentsOf: url) else { continue }

            stopDesktopMonitor()
            importButton.title = "📷  Take Photo"
            importButton.action = #selector(importFromPhone)

            try? FileManager.default.removeItem(at: url)
            log("checkDesktopForNewImage: deleted \(url.lastPathComponent)")

            NSApp.activate(ignoringOtherApps: true)
            view.window?.makeKeyAndOrderFront(nil)
            autoConvertNext = true
            imageWasSet(image)
            break
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
                let markdown = try await GeminiAPI.convert(image: image, mode: mode, apiKey: key)
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
        alert.messageText = "Gemini API Key"
        alert.informativeText = "Enter your Gemini API key. It will be stored in app preferences.\nYou can also set the GEMINI_API_KEY environment variable."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "AIza..."
        field.stringValue = UserDefaults.standard.string(forKey: "geminiAPIKey") ?? ""
        alert.accessoryView = field

        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            let value = field.stringValue.trimmingCharacters(in: .whitespaces)
            UserDefaults.standard.set(value, forKey: "geminiAPIKey")
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
        NSApp.registerServicesMenuSendTypes([], returnTypes: [.tiff, .png])
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
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(.separator())
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        editMenu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu

        let devMenuItem = NSMenuItem()
        menuBar.addItem(devMenuItem)
        let devMenu = NSMenu(title: "Dev")
        devMenuItem.submenu = devMenu
        devMenu.addItem(withTitle: "View Logs", action: #selector(viewLogs), keyEquivalent: "l")

        NSApp.mainMenu = menuBar
    }

    private var logPanel: NSPanel?
    private var logTextView: NSTextView?
    private var logObserver: Any?

    @objc private func viewLogs() {
        if let existing = logPanel, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 400),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Logs"
        panel.isFloatingPanel = true

        let scroll = NSScrollView(frame: panel.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true

        let tv = NSTextView(frame: scroll.bounds)
        tv.isEditable = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.string = Logger.shared.text.isEmpty ? "(no log entries yet)" : Logger.shared.text
        scroll.documentView = tv
        panel.contentView!.addSubview(scroll)
        tv.scrollToEndOfDocument(nil)

        logTextView = tv
        logPanel = panel

        logObserver = NotificationCenter.default.addObserver(
            forName: Logger.didAddEntry,
            object: nil,
            queue: .main
        ) { [weak tv] note in
            guard let tv, let entry = note.object as? String else { return }
            let atEnd = tv.string.isEmpty || tv.visibleRect.maxY >= tv.bounds.maxY - 20
            tv.textStorage?.append(NSAttributedString(
                string: (tv.string.isEmpty ? "" : "\n") + entry,
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)]
            ))
            if atEnd { tv.scrollToEndOfDocument(nil) }
        }

        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
