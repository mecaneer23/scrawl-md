import AppKit

// MARK: - Output View Controller

class OutputViewController: NSViewController {

    struct Section {
        let name: String
        let content: String
        let previews: [NSImage]
    }

    private let sections: [Section]
    private var currentIndex = 0

    private var documentPicker: NSPopUpButton!
    private var previewScrollView: NSScrollView!
    private var previewStack: NSStackView!
    private var outputScrollView: NSScrollView!
    private var outputView: NSTextView!
    private var outputModeControl: NSSegmentedControl!
    private var actionButton: NSButton!

    init(sections: [Section]) {
        self.sections = sections
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1100, height: 700))
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        showSection(at: 0)
    }

    private func buildUI() {
        let padding: CGFloat = 16
        let multiDoc = sections.count > 1

        // MARK: Left pane
        let leftPane = NSView()
        leftPane.translatesAutoresizingMaskIntoConstraints = false

        documentPicker = NSPopUpButton()
        for section in sections { documentPicker.addItem(withTitle: section.name) }
        documentPicker.target = self
        documentPicker.action = #selector(documentSelected)
        documentPicker.isHidden = !multiDoc
        documentPicker.translatesAutoresizingMaskIntoConstraints = false
        leftPane.addSubview(documentPicker)

        previewScrollView = NSScrollView()
        previewScrollView.hasVerticalScroller = true
        previewScrollView.hasHorizontalScroller = true
        previewScrollView.autohidesScrollers = true
        previewScrollView.borderType = .lineBorder
        previewScrollView.wantsLayer = true
        previewScrollView.layer?.cornerRadius = 8
        previewScrollView.translatesAutoresizingMaskIntoConstraints = false
        leftPane.addSubview(previewScrollView)

        previewStack = NSStackView()
        previewStack.orientation = .vertical
        previewStack.spacing = 8
        previewStack.alignment = .centerX
        previewStack.translatesAutoresizingMaskIntoConstraints = false
        previewScrollView.documentView = previewStack

        var leftConstraints: [NSLayoutConstraint] = [
            previewScrollView.leadingAnchor.constraint(equalTo: leftPane.leadingAnchor, constant: padding),
            previewScrollView.trailingAnchor.constraint(equalTo: leftPane.trailingAnchor, constant: -padding),
            previewScrollView.bottomAnchor.constraint(equalTo: leftPane.bottomAnchor, constant: -padding),
        ]
        if multiDoc {
            leftConstraints += [
                documentPicker.topAnchor.constraint(equalTo: leftPane.topAnchor, constant: padding),
                documentPicker.leadingAnchor.constraint(equalTo: leftPane.leadingAnchor, constant: padding),
                documentPicker.trailingAnchor.constraint(equalTo: leftPane.trailingAnchor, constant: -padding),
                previewScrollView.topAnchor.constraint(equalTo: documentPicker.bottomAnchor, constant: 8),
            ]
        } else {
            leftConstraints.append(previewScrollView.topAnchor.constraint(equalTo: leftPane.topAnchor, constant: padding))
        }
        NSLayoutConstraint.activate(leftConstraints)

        // MARK: Right pane
        let rightPane = NSView()
        rightPane.translatesAutoresizingMaskIntoConstraints = false

        outputScrollView = NSScrollView()
        outputScrollView.hasVerticalScroller = true
        outputScrollView.autohidesScrollers = true
        outputScrollView.borderType = .lineBorder
        outputScrollView.wantsLayer = true
        outputScrollView.layer?.cornerRadius = 8
        outputScrollView.translatesAutoresizingMaskIntoConstraints = false
        rightPane.addSubview(outputScrollView)

        outputView = NSTextView()
        outputView.isEditable = true
        outputView.isSelectable = true
        outputView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        outputView.textContainerInset = NSSize(width: 8, height: 8)
        outputView.isAutomaticSpellingCorrectionEnabled = false
        outputView.isAutomaticQuoteSubstitutionEnabled = false
        outputView.isVerticallyResizable = true
        outputView.isHorizontallyResizable = false
        outputView.autoresizingMask = [.width]
        outputView.minSize = .zero
        outputView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        outputView.textContainer?.widthTracksTextView = true
        outputView.textContainer?.heightTracksTextView = false
        outputScrollView.documentView = outputView

        NSLayoutConstraint.activate([
            outputScrollView.topAnchor.constraint(equalTo: rightPane.topAnchor, constant: padding),
            outputScrollView.leadingAnchor.constraint(equalTo: rightPane.leadingAnchor, constant: padding),
            outputScrollView.trailingAnchor.constraint(equalTo: rightPane.trailingAnchor, constant: -padding),
            outputScrollView.bottomAnchor.constraint(equalTo: rightPane.bottomAnchor, constant: -padding),
        ])

        // MARK: Split view
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.addArrangedSubview(leftPane)
        splitView.addArrangedSubview(rightPane)
        splitView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(splitView)

        // MARK: Bottom bar
        outputModeControl = NSSegmentedControl(
            labels: ["Copy", "Save to File"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(outputModeChanged)
        )
        outputModeControl.selectedSegment = 0
        outputModeControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(outputModeControl)

        actionButton = NSButton(title: "Copy All", target: self, action: #selector(copyOrSave))
        actionButton.bezelStyle = .rounded
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(actionButton)

        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: view.topAnchor),
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: outputModeControl.topAnchor, constant: -padding),

            outputModeControl.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -padding),
            outputModeControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            outputModeControl.centerYAnchor.constraint(equalTo: actionButton.centerYAnchor),

            actionButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -padding),
            actionButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            actionButton.widthAnchor.constraint(equalToConstant: 100),
        ])

        outputView.string = combinedText()
    }

    private func combinedText() -> String {
        if sections.count == 1 { return sections[0].content }
        return sections.map { "## \($0.name)\n\n\($0.content)" }.joined(separator: "\n\n---\n\n")
    }

    private func showSection(at index: Int) {
        guard index < sections.count else { return }
        currentIndex = index
        let section = sections[index]

        previewStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for img in section.previews {
            let iv = NSImageView()
            iv.image = img
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.translatesAutoresizingMaskIntoConstraints = false
            previewStack.addArrangedSubview(iv)
            // Render at 2x so natural display size = img.size / 2; show at 75% of that
            let displayWidth = img.size.width / 2.0 * 0.75
            let displayHeight = img.size.height / 2.0 * 0.75
            NSLayoutConstraint.activate([
                iv.widthAnchor.constraint(equalToConstant: displayWidth),
                iv.heightAnchor.constraint(equalToConstant: displayHeight),
            ])
        }
        DispatchQueue.main.async {
            self.previewScrollView.contentView.scroll(to: .zero)
            self.previewScrollView.reflectScrolledClipView(self.previewScrollView.contentView)
        }
    }

    @objc private func documentSelected() {
        showSection(at: documentPicker.indexOfSelectedItem)
    }

    @objc private func outputModeChanged() {
        actionButton.title = outputModeControl.selectedSegment == 0 ? "Copy All" : "Save…"
    }

    @objc private func copyOrSave() {
        outputModeControl.selectedSegment == 0 ? copyAll() : saveToFile()
    }

    private func copyAll() {
        let text = outputView.string
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        flash("Copied!", then: "Copy All")
    }

    private func saveToFile() {
        guard !outputView.string.isEmpty else { return }
        if sections.count > 1 {
            let alert = NSAlert()
            alert.messageText = "Save Output"
            alert.informativeText = "Save all files combined into one document, or save each file separately?"
            alert.addButton(withTitle: "Save Combined")
            alert.addButton(withTitle: "Save Separately")
            alert.addButton(withTitle: "Cancel")
            let response = alert.runModal()
            if response == .alertThirdButtonReturn { return }
            if response == .alertSecondButtonReturn { saveAllSeparately(); return }
        }
        let name = sections.count == 1 ? sections[0].name : "ScrawlMD Output"
        saveSingle(text: outputView.string, suggestedName: name)
    }

    private func saveSingle(text: String, suggestedName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.nameFieldStringValue = "\(suggestedName).md"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            log("saveSingle: saved \(url.lastPathComponent)")
            flash("Saved!", then: "Save…")
        } catch {
            log("saveSingle error: \(error.localizedDescription)")
        }
    }

    private func editedSectionContents() -> [String] {
        guard sections.count > 1 else { return [outputView.string] }
        let parts = outputView.string.components(separatedBy: "\n\n---\n\n")
        return sections.enumerated().map { i, s in
            guard i < parts.count else { return s.content }
            let part = parts[i]
            let prefix = "## \(s.name)\n\n"
            return part.hasPrefix(prefix) ? String(part.dropFirst(prefix.count)) : part
        }
    }

    private func saveAllSeparately() {
        let contents = editedSectionContents()
        func saveNext(_ i: Int) {
            guard i < sections.count else { flash("Saved!", then: "Save…"); return }
            let s = sections[i]
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.init(filenameExtension: "md")!]
            panel.nameFieldStringValue = "\(s.name).md"
            panel.canCreateDirectories = true
            panel.message = "Save file \(i + 1) of \(sections.count)"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try contents[i].write(to: url, atomically: true, encoding: .utf8)
                log("saveAllSeparately: saved \(url.lastPathComponent)")
            } catch { return }
            saveNext(i + 1)
        }
        saveNext(0)
    }

    private func flash(_ title: String, then restore: String) {
        actionButton.title = title
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.actionButton.title = restore
        }
    }
}
