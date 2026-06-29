import AppKit

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
