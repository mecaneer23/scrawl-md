import AppKit
import PDFKit

// MARK: - Image Drop Zone

class ImageDropZone: NSImageView {
    var onGroupsSet: (([InputGroup]) -> Void)?
    private var suppressCallback = false
    private var handledDragManually = false

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

    override var image: NSImage? {
        didSet {
            guard !suppressCallback, let img = image else { return }
            onGroupsSet?([InputGroup(name: "", inputs: [.image(img)])])
        }
    }

    override func mouseDown(with event: NSEvent) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .init(filenameExtension: "jpg")!, .init(filenameExtension: "jpeg")!,
            .init(filenameExtension: "png")!, .init(filenameExtension: "heic")!,
            .init(filenameExtension: "heif")!, .init(filenameExtension: "tiff")!,
            .init(filenameExtension: "tif")!,  .init(filenameExtension: "pdf")!,
        ]
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        var groups: [InputGroup] = []
        for url in panel.urls {
            let name = url.deletingPathExtension().lastPathComponent
            if url.pathExtension.lowercased() == "pdf", let doc = PDFDocument(url: url) {
                let pages = renderPDFPages(doc)
                if !pages.isEmpty { groups.append(InputGroup(name: name, inputs: pages.map { .image($0) })) }
            } else if let img = NSImage(contentsOf: url) {
                groups.append(InputGroup(name: name, inputs: [.image(img)]))
            }
        }
        guard !groups.isEmpty else { return }

        suppressCallback = true
        if case .image(let first) = groups.first?.inputs.first { image = first }
        suppressCallback = false
        let totalInputs = groups.reduce(0) { $0 + $1.inputs.count }
        log("mouseDown open panel: \(groups.count) group(s), \(totalInputs) input(s)")
        onGroupsSet?(groups)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !urls.isEmpty else {
            return super.performDragOperation(sender)
        }

        var groups: [InputGroup] = []
        for url in urls {
            let name = url.deletingPathExtension().lastPathComponent
            if url.pathExtension.lowercased() == "pdf",
               let doc = PDFDocument(url: url) {
                let pages = renderPDFPages(doc)
                log("performDragOperation: PDF \(url.lastPathComponent) \(pages.count) page(s)")
                if !pages.isEmpty { groups.append(InputGroup(name: name, inputs: pages.map { .image($0) })) }
            } else if let img = NSImage(contentsOf: url) {
                groups.append(InputGroup(name: name, inputs: [.image(img)]))
            }
        }

        guard !groups.isEmpty else { return super.performDragOperation(sender) }

        handledDragManually = true
        suppressCallback = true
        if case .image(let first) = groups.first?.inputs.first { image = first }
        suppressCallback = false
        let totalInputs = groups.reduce(0) { $0 + $1.inputs.count }
        log("performDragOperation: \(groups.count) group(s), \(totalInputs) input(s)")
        onGroupsSet?(groups)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        if handledDragManually {
            handledDragManually = false
            return
        }
        super.concludeDragOperation(sender)
    }

    private func renderPDFPages(_ doc: PDFDocument) -> [NSImage] {
        var images: [NSImage] = []
        let scale: CGFloat = 2.0
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let img = NSImage(size: size)
            img.lockFocus()
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.scaleBy(x: scale, y: scale)
                page.draw(with: .mediaBox, to: ctx)
            }
            img.unlockFocus()
            images.append(img)
        }
        return images
    }
}
