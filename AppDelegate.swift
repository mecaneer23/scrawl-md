import AppKit

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
        window.title = "ScrawlMD"
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
        let appMenu = NSMenu(title: "ScrawlMD")
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit ScrawlMD", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

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
