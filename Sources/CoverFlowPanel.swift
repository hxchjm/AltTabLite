import AppKit
import QuartzCore

enum PanelStyle: String, CaseIterable {
    case list, coverFlow

    var label: String {
        switch self {
        case .list: return "列表"
        case .coverFlow: return "Cover Flow"
        }
    }
}

extension PanelSize {
    var coverSize: CGFloat {
        switch self {
        case .small: return 128
        case .medium: return 160
        case .large: return 200
        }
    }
}

final class CoverFlowPanel {
    var onPick: ((Int) -> Void)?

    private let panel: NSPanel
    private let container: NSView
    private let contentHost: NSView
    private let coverView = CoverFlowView()
    private let stage = CALayer()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let labelBackground = NSVisualEffectView()
    private var covers: [CALayer] = []
    private var currentKeys: [String] = []
    private var entries: [SwitchEntry] = []
    private var selectedIndex = 0
    private var position: CGFloat = 0
    private var hoveredIndex: Int?
    private var maxOffset = 1
    private var size: PanelSize = .medium
    private var showsAppName = false

    private let padding: CGFloat = 20
    private let topInset: CGFloat = 26
    private let sideAngle: CGFloat = .pi / 3
    private let sideOpacity: Float = 0.8
    private let scrollPointsPerItem: CGFloat = 50
    private let labelBackgroundRadius: CGFloat = 10

    private var coverSize: CGFloat { size.coverSize }
    private var centerGap: CGFloat { coverSize * 0.8 }
    private var sideSpacing: CGFloat { coverSize * 0.3 }

    init() {
        let initialRect = NSRect(x: 0, y: 0, width: 600, height: 300)

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
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        container = NSView(frame: initialRect)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.layer?.masksToBounds = true

        contentHost = NSView(frame: initialRect)
        contentHost.autoresizingMask = [.width, .height]

        coverView.frame = initialRect
        coverView.layer = CALayer()
        coverView.wantsLayer = true
        coverView.layer?.addSublayer(stage)
        coverView.autoresizingMask = [.width, .height]
        coverView.onClick = { [weak self] point in self?.click(at: point) }
        coverView.onHover = { [weak self] point in self?.hover(at: point) }

        for label in [titleLabel, subtitleLabel] {
            label.wantsLayer = true
            label.alignment = .center
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byTruncatingMiddle
        }
        titleLabel.textColor = .labelColor
        subtitleLabel.textColor = .secondaryLabelColor

        labelBackground.material = .popover
        labelBackground.blendingMode = .behindWindow
        labelBackground.state = .active
        labelBackground.maskImage = SwitcherPanel.roundedMask(radius: labelBackgroundRadius)

        contentHost.addSubview(coverView)
        contentHost.addSubview(labelBackground)
        contentHost.addSubview(titleLabel)
        contentHost.addSubview(subtitleLabel)
        container.addSubview(contentHost)
        panel.contentView = container
    }

    func show(entries: [SwitchEntry], selectedIndex: Int, size: PanelSize, showsAppName: Bool) {
        guard selectedIndex >= 0, selectedIndex < entries.count else { return }
        self.showsAppName = showsAppName
        let wasVisible = panel.isVisible
        let keys = entries.map { $0.key }
        if keys != currentKeys || size != self.size {
            self.size = size
            rebuildCovers(entries)
            currentKeys = keys
        }
        self.entries = entries
        self.selectedIndex = selectedIndex
        position = CGFloat(selectedIndex)
        updateLabels(animated: wasVisible)
        relayout(count: entries.count, animated: wasVisible)

        if wasVisible {
            panel.orderFrontRegardless()
            return
        }

        panel.alphaValue = 0
        container.layer?.transform = CATransform3DMakeScale(0.98, 0.98, 1)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.08)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        container.layer?.transform = CATransform3DIdentity
        CATransaction.commit()
    }

    func hide() {
        panel.orderOut(nil)
        panel.alphaValue = 1
        container.layer?.transform = CATransform3DIdentity
        for label in [titleLabel, subtitleLabel] {
            label.layer?.removeAnimation(forKey: "transition")
        }
        hoveredIndex = nil
    }

    private func rebuildCovers(_ entries: [SwitchEntry]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        covers.forEach { $0.removeFromSuperlayer() }
        let scale = activeScreen()?.backingScaleFactor ?? 2
        let edge = coverSize
        var iconCache: [pid_t: NSImage] = [:]
        covers = entries.map { entry in
            let pid = entry.app.processIdentifier
            let icon = iconCache[pid] ?? Self.fullResolutionIcon(for: entry.app)
            iconCache[pid] = icon

            let cover = CALayer()
            cover.bounds = CGRect(x: 0, y: 0, width: edge, height: edge)

            // Isolate the icon so its shadow does not include the reflection.
            let iconLayer = CALayer()
            iconLayer.frame = cover.bounds
            iconLayer.contents = Self.rasterize(icon, edge: edge, scale: scale)
            iconLayer.contentsScale = scale
            iconLayer.contentsGravity = .resizeAspect
            iconLayer.shadowColor = NSColor.black.cgColor
            iconLayer.shadowRadius = edge * 0.06
            iconLayer.shadowOffset = CGSize(width: 0, height: -edge * 0.025)
            cover.addSublayer(iconLayer)

            // Pulled up slightly so the mirror meets the icon shape instead of its transparent margin.
            let reflection = CALayer()
            reflection.frame = CGRect(x: 0, y: -edge * 0.92, width: edge, height: edge)
            reflection.contents = Self.rasterize(Self.reflection(of: icon, edge: edge), edge: edge, scale: scale)
            reflection.contentsScale = scale
            reflection.contentsGravity = .resizeAspect
            cover.addSublayer(reflection)

            stage.addSublayer(cover)
            return cover
        }
        if let first = entries.first, let icon = iconCache[first.app.processIdentifier] {
            let largest = icon.representations.map { $0.pixelsWide }.max() ?? 0
            let rendered = (covers.first?.sublayers?.first?.contents as! CGImage?)?.width ?? 0
            log("cover flow icons: \(first.app.localizedName ?? "?") source max \(largest)px, rendered \(rendered)px for \(Int(edge))pt @\(scale)x")
        }
        CATransaction.commit()
    }

    private static func fullResolutionIcon(for app: NSRunningApplication) -> NSImage {
        if let url = app.bundleURL {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return app.icon ?? NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }

    private static func rasterize(_ image: NSImage, edge: CGFloat, scale: CGFloat) -> CGImage? {
        let pixels = Int((edge * scale).rounded())
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        bitmap.size = NSSize(width: edge, height: edge)
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmap)
        context?.imageInterpolation = .high
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: edge, height: edge), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.cgImage
    }

    private static func reflection(of icon: NSImage, edge: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.translateBy(x: 0, y: rect.height)
            context.scaleBy(x: 1, y: -1)
            icon.draw(in: rect)
            context.restoreGState()

            let colors = [NSColor(white: 0, alpha: 0.35).cgColor, NSColor(white: 0, alpha: 0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0, 0.4]) else { return false }
            context.setBlendMode(.destinationIn)
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: rect.maxY),
                end: CGPoint(x: 0, y: rect.minY),
                options: []
            )
            return true
        }
    }

    private func relayout(count: Int, animated: Bool) {
        guard let screen = activeScreen() else { return }
        let visible = screen.visibleFrame
        let edge = coverSize

        let titleFontSize = size.fontSize + 3
        let subtitleFontSize = size.fontSize - 1
        let titleHeight = ceil(titleFontSize * 1.35)
        let subtitleHeight = ceil(subtitleFontSize * 1.35)
        let reflectionSpace = edge * 0.3
        let panelHeight = topInset + edge + reflectionSpace + titleHeight + 2 + subtitleHeight + padding

        let sideCount = CGFloat(max(count - 1, 1))
        let naturalWidth = 2 * (centerGap + (sideCount - 1) * sideSpacing + edge * 0.35) + padding * 2
        let panelWidth = min(max(naturalWidth, edge * 3.4), visible.width * 0.85)

        panel.setFrame(
            NSRect(x: visible.midX - panelWidth / 2, y: visible.midY - panelHeight / 2, width: panelWidth, height: panelHeight),
            display: true
        )

        let labelWidth = panelWidth - padding * 2
        subtitleLabel.font = .systemFont(ofSize: subtitleFontSize)
        subtitleLabel.frame = NSRect(x: padding, y: padding, width: labelWidth, height: subtitleHeight)
        titleLabel.font = .systemFont(ofSize: titleFontSize, weight: .semibold)
        titleLabel.frame = NSRect(x: padding, y: subtitleLabel.frame.maxY + 2, width: labelWidth, height: titleHeight)
        layoutLabelBackground()

        maxOffset = max(1, Int((panelWidth / 2 - padding - centerGap - edge * 0.3) / sideSpacing) + 1)

        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.2)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }

        stage.bounds = CGRect(x: 0, y: 0, width: panelWidth, height: edge)
        stage.position = CGPoint(x: panelWidth / 2, y: panelHeight - topInset - edge / 2)
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / (edge * 3.2)
        stage.sublayerTransform = perspective
        layoutCovers()
        CATransaction.commit()
    }

    func scroll(by points: CGFloat, animated: Bool) {
        guard !covers.isEmpty else { return }
        position = min(max(position + points / scrollPointsPerItem, 0), CGFloat(covers.count - 1))
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.18)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        layoutCovers()
        CATransaction.commit()
    }

    func snap() -> Int {
        let index = Int(position.rounded())
        position = CGFloat(index)
        selectedIndex = index
        updateLabels(animated: panel.isVisible)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        layoutCovers()
        CATransaction.commit()
        return index
    }

    private func updateLabels(animated: Bool) {
        guard selectedIndex >= 0, selectedIndex < entries.count else { return }
        let entry = entries[selectedIndex]
        let appName = entry.app.localizedName ?? ""
        let subtitle = !showsAppName || appName == entry.title ? "" : appName
        for (label, text) in [(titleLabel, entry.title), (subtitleLabel, subtitle)] {
            if animated, label.stringValue != text {
                label.displayIfNeeded()
                let transition = CATransition()
                transition.type = .fade
                transition.duration = 0.12
                transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
                label.layer?.add(transition, forKey: "transition")
            } else if !animated {
                label.layer?.removeAnimation(forKey: "transition")
            }
            label.stringValue = text
        }
        layoutLabelBackground()
    }

    private func layoutLabelBackground() {
        let hasSubtitle = !subtitleLabel.stringValue.isEmpty
        let textWidth = max(
            titleLabel.attributedStringValue.size().width,
            hasSubtitle ? subtitleLabel.attributedStringValue.size().width : 0
        )
        let width = min(ceil(textWidth), titleLabel.frame.width) + 28
        let bottom = (hasSubtitle ? subtitleLabel.frame.minY : titleLabel.frame.minY) - 6
        let top = titleLabel.frame.maxY + 6
        labelBackground.frame = NSRect(x: titleLabel.frame.midX - width / 2, y: bottom, width: width, height: top - bottom)
    }

    private func layoutCovers() {
        let edge = coverSize
        let midX = stage.bounds.width / 2
        for (index, cover) in covers.enumerated() {
            let offset = CGFloat(index) - position
            let distance = abs(offset)
            let direction: CGFloat = offset < 0 ? -1 : 1
            let x = distance <= 1
                ? offset * centerGap
                : direction * (centerGap + (distance - 1) * sideSpacing)
            let turn = min(distance, 1)
            let emphasis = 1 - turn
            let scale = 1 + emphasis * 0.06
            cover.position = CGPoint(x: midX + x, y: edge / 2)
            // Side covers turn their faces toward the center, tucking the inner edge back.
            let transform = CATransform3DConcat(
                CATransform3DMakeRotation(-direction * sideAngle * turn, 0, 1, 0),
                CATransform3DMakeTranslation(0, 0, -edge * 0.45 * turn)
            )
            cover.transform = CATransform3DScale(transform, scale, scale, 1)
            cover.sublayers?.first?.shadowOpacity = Float(emphasis) * 0.22
            cover.zPosition = -distance * 0.01
        }

        let mouse = coverView.convert(panel.mouseLocationOutsideOfEventStream, from: nil)
        hoveredIndex = coverView.bounds.contains(mouse) ? coverIndex(at: mouse) : nil
        applyOpacity()
    }

    private func applyOpacity() {
        let limit = CGFloat(maxOffset)
        for (index, cover) in covers.enumerated() {
            let distance = abs(CGFloat(index) - position)
            let base = index == hoveredIndex ? 1 : 1 - Float(min(distance, 1)) * (1 - sideOpacity)
            let fade = Float(min(max(limit + 1 - distance, 0), 1))
            cover.opacity = base * fade
        }
    }

    private func coverIndex(at point: NSPoint) -> Int? {
        guard let root = coverView.layer else { return nil }
        let frontToBack = covers.indices
            .filter { abs(CGFloat($0) - position) <= CGFloat(maxOffset) }
            .sorted { abs(CGFloat($0) - position) < abs(CGFloat($1) - position) }
        for index in frontToBack {
            let local = covers[index].convert(point, from: root)
            if covers[index].bounds.contains(local) {
                return index
            }
        }
        return nil
    }

    private func hover(at point: NSPoint?) {
        let index = point.flatMap { coverIndex(at: $0) }
        guard index != hoveredIndex else { return }
        hoveredIndex = index
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.1)
        applyOpacity()
        CATransaction.commit()
    }

    private func click(at point: NSPoint) {
        guard let index = coverIndex(at: point) else { return }
        onPick?(index)
    }

    private func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}

private final class CoverFlowView: NSView {
    var onClick: ((NSPoint) -> Void)?
    var onHover: ((NSPoint?) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseMoved(with event: NSEvent) {
        onHover?(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(nil)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?(convert(event.locationInWindow, from: nil))
    }
}
