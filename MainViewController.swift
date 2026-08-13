import AppKit
import ApplicationServices

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
    private var statusScrollView: NSScrollView!
    private var statusView: NSTextView!
    private var importButton: NSButton!

    private var capturedGroups: [InputGroup] = []
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
        dropZone.onGroupsSet = { [weak self] groups in
            self?.groupsWereSet(groups)
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

        // Status scroll view (single-line, horizontally scrollable)
        statusScrollView = NSScrollView()
        statusScrollView.hasHorizontalScroller = true
        statusScrollView.hasVerticalScroller = false
        statusScrollView.autohidesScrollers = true
        statusScrollView.borderType = .noBorder
        statusScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusScrollView)

        statusView = NSTextView()
        statusView.isEditable = false
        statusView.isSelectable = true
        statusView.font = NSFont.systemFont(ofSize: 11)
        statusView.textColor = .secondaryLabelColor
        statusView.backgroundColor = .clear
        statusView.textContainerInset = .zero
        statusView.textContainer?.lineFragmentPadding = 0
        statusView.textContainer?.widthTracksTextView = false
        statusView.textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        statusView.isHorizontallyResizable = true
        statusView.isVerticallyResizable = false
        statusScrollView.documentView = statusView

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
        resultView.isVerticallyResizable = true
        resultView.isHorizontallyResizable = false
        resultView.autoresizingMask = [.width]
        resultView.minSize = NSSize(width: 0, height: 0)
        resultView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        resultView.textContainer?.widthTracksTextView = true
        resultView.textContainer?.heightTracksTextView = false
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

            // Status scroll view
            statusScrollView.topAnchor.constraint(equalTo: convertButton.bottomAnchor, constant: 6),
            statusScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            statusScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            statusScrollView.heightAnchor.constraint(equalToConstant: 18),

            // Result scroll view
            resultScrollView.topAnchor.constraint(equalTo: statusScrollView.bottomAnchor, constant: 8),
            resultScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            resultScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            resultScrollView.bottomAnchor.constraint(equalTo: copyButton.topAnchor, constant: -10),

            // Copy button bottom-right
            copyButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -padding),
            copyButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            copyButton.widthAnchor.constraint(equalToConstant: 100),
        ])

    }

    private func groupsWereSet(_ groups: [InputGroup]) {
        log("groupsWereSet: \(groups.count) group(s), autoConvertNext=\(autoConvertNext)")
        capturedGroups = groups
        placeholderLabel.isHidden = true
        convertButton.isEnabled = true
        setStatus("")
        if autoConvertNext {
            log("groupsWereSet: auto-triggering convert")
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
            setStatus("Enable Accessibility for ScrawlMD in System Settings > Privacy, then click Take Photo again.")
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

        // Determine click target: prefer the desktop element's actual frame,
        // fall back to a window-free point found via CGWindowList.
        var clickPt: CGPoint?

        if let desktop = findFinderDesktop(in: finderApp), let frame = axFrame(desktop) {
            log("rightClickFinderDesktop: using desktop frame \(frame)")
            clickPt = CGPoint(x: frame.midX, y: frame.midY)
        }

        if clickPt == nil, let pt = safeDesktopPoint() {
            log("rightClickFinderDesktop: using safeDesktopPoint \(pt)")
            clickPt = pt
        }

        guard let pt = clickPt else {
            log("rightClickFinderDesktop: no clickable point found")
            setStatus("Could not find open desktop area. Right-click the desktop manually → Import from iPhone → Take a Picture")
            return
        }

        postRightClick(at: pt, finderPID: finderPID)
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
            groupsWereSet([InputGroup(name: "", inputs: [.image(image)])])
            break
        }
    }

    private func clearImage() {
        capturedGroups = []
        dropZone.image = nil
        placeholderLabel.isHidden = false
        convertButton.isEnabled = false
    }

    @objc private func convert() {
        guard !capturedGroups.isEmpty, !isProcessing else { return }

        let groups = capturedGroups
        let mode: ConversionMode = modeControl.selectedSegment == 0 ? .verbatim : .cleaned
        let key = apiKey
        let multiFile = groups.count > 1

        isProcessing = true
        convertButton.isEnabled = false
        spinner.isHidden = false
        spinner.startAnimation(nil)
        resultView.string = ""
        copyButton.isEnabled = false

        Task {
            var sections: [String] = []
            var failed = false
            for (i, group) in groups.enumerated() {
                let label = multiFile ? "\(i + 1) of \(groups.count): \(group.name)" : "1 of 1"
                await MainActor.run { setStatus("Converting \(label)…") }
                do {
                    let markdown = try await GeminiAPI.convert(inputs: group.inputs, mode: mode, apiKey: key)
                    if multiFile {
                        sections.append("## \(group.name)\n\n\(markdown)")
                    } else {
                        sections.append(markdown)
                    }
                } catch {
                    await MainActor.run { setStatus("Error on \(group.name): \(error.localizedDescription)") }
                    failed = true
                    break
                }
            }
            await MainActor.run {
                if !sections.isEmpty {
                    resultView.string = sections.joined(separator: "\n\n---\n\n")
                    copyButton.isEnabled = true
                    if !failed { setStatus("Done.") }
                    clearImage()
                }
                isProcessing = false
                convertButton.isEnabled = !capturedGroups.isEmpty
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
        statusView.string = msg
        if !msg.isEmpty { log("status: \(msg)") }
    }
}
