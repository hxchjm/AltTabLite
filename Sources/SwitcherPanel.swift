import AppKit

enum PanelSize: String, CaseIterable {
    case small, medium, large

    var label: String {
        switch self {
        case .small: return "小"
        case .medium: return "中"
        case .large: return "大"
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .small: return 30
        case .medium: return 36
        case .large: return 44
        }
    }

    var fontSize: CGFloat {
        switch self {
        case .small: return 14
        case .medium: return 16
        case .large: return 19
        }
    }
}

final class SwitcherPanel {
    var onPick: ((Int) -> Void)?

    private let panel: NSPanel
    private let effectView: NSVisualEffectView
    private var rows: [RowView] = []
    private var currentKeys: [String] = []

    var size: PanelSize = .medium

    private let padding: CGFloat = 14
    private let gap: CGFloat = 1
    private let iconGap: CGFloat = 14
    private let cornerRadius: CGFloat = 20

    private var iconSize: CGFloat { size.iconSize }
    private var fontSize: CGFloat { size.fontSize }
    private var rowHeight: CGFloat { iconSize + 14 }

    init() {
        let initialRect = NSRect(x: 0, y: 0, width: 480, height: 300)

        panel = NSPanel(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = NSAppearance(named: .aqua)
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let container = NSView(frame: initialRect)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.layer?.cornerRadius = cornerRadius
        container.layer?.masksToBounds = true

        effectView = NSVisualEffectView(frame: initialRect)
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.maskImage = Self.roundedMask(radius: cornerRadius)
        effectView.autoresizingMask = [.width, .height]

        container.addSubview(effectView)
        panel.contentView = container
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    func show(entries: [SwitchEntry], selectedIndex: Int) {
        let keys = entries.map { $0.key }
        if keys != currentKeys {
            rebuildRows(entries)
            currentKeys = keys
        }
        for (index, row) in rows.enumerated() where index < entries.count {
            row.titleLabel.stringValue = entries[index].title
        }
        relayout(count: entries.count, selectedIndex: selectedIndex)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func rebuildRows(_ entries: [SwitchEntry]) {
        for row in rows {
            row.removeFromSuperview()
        }
        rows = entries.enumerated().map { index, entry in
            let row = RowView()
            row.imageView.image = entry.app.icon ?? NSImage(named: NSImage.applicationIconName)
            row.titleLabel.stringValue = entry.title
            row.onDown = { [weak self] in self?.rowClicked(at: index) }
            effectView.addSubview(row)
            return row
        }
    }

    private func rowClicked(at index: Int) {
        onPick?(index)
    }

    private func relayout(count: Int, selectedIndex: Int) {
        guard let screen = activeScreen() else { return }
        let visible = screen.visibleFrame
        let itemCount = max(count, 1)

        let titleFont = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let widestTitle = rows.reduce(CGFloat(0)) { width, row in
            let measured = (row.titleLabel.stringValue as NSString).size(withAttributes: [.font: titleFont]).width
            return max(width, measured)
        }
        let contentWidth = padding * 2 + 10 + iconSize + iconGap + widestTitle + 10
        let panelWidth = min(max(contentWidth, 360), visible.width * 0.6)

        let maxPanelHeight = visible.height * 0.85
        let rowsThatFit = max(1, Int((maxPanelHeight - padding * 2 + gap) / (rowHeight + gap)))
        let visibleRows = min(itemCount, rowsThatFit)
        let panelHeight = padding * 2 + CGFloat(visibleRows) * rowHeight + CGFloat(visibleRows - 1) * gap

        let top = visibleRows < itemCount
            ? max(0, min(selectedIndex - visibleRows / 2, itemCount - visibleRows))
            : 0

        let originX = visible.midX - panelWidth / 2
        let originY = visible.midY - panelHeight / 2
        panel.setFrame(NSRect(x: originX, y: originY, width: panelWidth, height: panelHeight), display: true)

        for (index, row) in rows.enumerated() {
            let position = index - top
            if position < 0 || position >= visibleRows {
                row.isHidden = true
                row.isSelected = false
                continue
            }
            row.isHidden = false
            let rowY = panelHeight - padding - CGFloat(position + 1) * rowHeight - CGFloat(position) * gap
            row.frame = NSRect(x: padding, y: rowY, width: panelWidth - padding * 2, height: rowHeight)
            row.applyLayout(iconSize: iconSize, fontSize: fontSize)
            row.isSelected = (index == selectedIndex)
        }
    }

    private func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}

private final class RowView: NSView {
    let imageView = NSImageView()
    let titleLabel = NSTextField(labelWithString: "")
    var onDown: (() -> Void)?

    var isSelected = false {
        didSet {
            if isSelected != oldValue {
                titleLabel.textColor = isSelected ? .white : .labelColor
                needsDisplay = true
            }
        }
    }

    private var isHovered = false {
        didSet {
            if isHovered != oldValue {
                needsDisplay = true
            }
        }
    }

    init() {
        super.init(frame: .zero)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        titleLabel.textColor = .labelColor
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(imageView)
        addSubview(titleLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func mouseDown(with event: NSEvent) {
        onDown?()
    }

    func applyLayout(iconSize: CGFloat, fontSize: CGFloat) {
        let inset: CGFloat = 10
        imageView.frame = NSRect(x: inset, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
        titleLabel.font = .systemFont(ofSize: fontSize, weight: .medium)
        let labelHeight = ceil(fontSize * 1.35)
        let labelX = imageView.frame.maxX + 14
        titleLabel.frame = NSRect(x: labelX, y: (bounds.height - labelHeight) / 2, width: bounds.width - labelX - inset, height: labelHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 12, yRadius: 12)
        if isSelected {
            NSColor.controlAccentColor.withAlphaComponent(0.85).setFill()
            path.fill()
        } else if isHovered {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            path.fill()
        }
        super.draw(dirtyRect)
    }
}
