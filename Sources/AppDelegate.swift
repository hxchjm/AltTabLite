import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appList: AppListTracker!
    private var panel: SwitcherPanel!
    private var tapController: EventTapController!
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bundleID = Bundle.main.bundleIdentifier ?? "alttablite"
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
            log("another instance is already running, exiting")
            NSApp.terminate(nil)
            return
        }

        appList = AppListTracker()
        panel = SwitcherPanel()
        if let saved = UserDefaults.standard.string(forKey: "panelSize"), let size = PanelSize(rawValue: saved) {
            panel.size = size
        }
        if let saved = UserDefaults.standard.string(forKey: "panelStyle"), let style = PanelStyle(rawValue: saved) {
            panel.style = style
        }
        panel.selectionAnimationEnabled = UserDefaults.standard.bool(forKey: "selectionAnimationEnabled")
        panel.coverFlowShowsAppName = UserDefaults.standard.bool(forKey: "coverFlowShowsAppName")
        panel.coverFlowShowsCurrentWindowDot = UserDefaults.standard.object(forKey: "coverFlowShowsCurrentWindowDot") as? Bool ?? true
        if let saved = UserDefaults.standard.object(forKey: "coverFlowSideOpacity") as? NSNumber {
            panel.coverFlowSideOpacity = min(max(saved.floatValue, 0.2), 1)
        }
        tapController = EventTapController(appList: appList, panel: panel)
        if let saved = UserDefaults.standard.string(forKey: "coverFlowScrollDirection"),
           let direction = CoverFlowScrollDirection(rawValue: saved) {
            tapController.coverFlowScrollDirection = direction
        }
        if let saved = UserDefaults.standard.string(forKey: "coverFlowScrollSensitivity"),
           let sensitivity = CoverFlowScrollSensitivity(rawValue: saved) {
            tapController.coverFlowScrollSensitivity = sensitivity
        }
        if let saved = UserDefaults.standard.string(forKey: "coverFlowSnapDelay"),
           let delay = CoverFlowSnapDelay(rawValue: saved) {
            tapController.coverFlowSnapDelay = delay
        }
        setupStatusItem()

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        log("launch: accessibility trusted=\(trusted), window-level activation=\(AppActivator.windowLevelActivationAvailable)")
        attemptStart()
    }

    private func attemptStart() {
        if AXIsProcessTrusted(), tapController.start() {
            log("event tap installed")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.attemptStart()
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "AltTabLite") {
            item.button?.image = image
        } else {
            item.button?.title = "AT"
        }
        let menu = NSMenu()

        let styleItem = NSMenuItem(title: "显示样式", action: nil, keyEquivalent: "")
        let styleMenu = NSMenu()
        for style in PanelStyle.allCases {
            let item = NSMenuItem(title: style.label, action: #selector(selectPanelStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            item.state = (style == panel.style) ? .on : .off
            styleMenu.addItem(item)
        }
        styleItem.submenu = styleMenu
        menu.addItem(styleItem)

        let sizeItem = NSMenuItem(title: "面板大小", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        for preset in PanelSize.allCases {
            let item = NSMenuItem(title: preset.label, action: #selector(selectPanelSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.rawValue
            item.state = (preset == panel.size) ? .on : .off
            sizeMenu.addItem(item)
        }
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        let selectionAnimationItem = NSMenuItem(
            title: "选中块滑动动画",
            action: #selector(toggleSelectionAnimation(_:)),
            keyEquivalent: ""
        )
        selectionAnimationItem.target = self
        selectionAnimationItem.state = panel.selectionAnimationEnabled ? .on : .off
        menu.addItem(selectionAnimationItem)

        let appNameItem = NSMenuItem(
            title: "Cover Flow 显示程序名",
            action: #selector(toggleCoverFlowAppName(_:)),
            keyEquivalent: ""
        )
        appNameItem.target = self
        appNameItem.state = panel.coverFlowShowsAppName ? .on : .off
        menu.addItem(appNameItem)

        let currentWindowDotItem = NSMenuItem(
            title: "Cover Flow 显示当前窗口圆点",
            action: #selector(toggleCoverFlowCurrentWindowDot(_:)),
            keyEquivalent: ""
        )
        currentWindowDotItem.target = self
        currentWindowDotItem.state = panel.coverFlowShowsCurrentWindowDot ? .on : .off
        menu.addItem(currentWindowDotItem)

        let interactionItem = NSMenuItem(title: "Cover Flow 交互", action: nil, keyEquivalent: "")
        let interactionMenu = NSMenu()

        let opacityItem = NSMenuItem()
        let opacityView = NSView(frame: NSRect(x: 0, y: 0, width: 230, height: 52))
        let opacityLabel = NSTextField(labelWithString: "侧边图标透明度 \(Int((panel.coverFlowSideOpacity * 100).rounded()))%")
        opacityLabel.tag = 1
        opacityLabel.frame = NSRect(x: 12, y: 29, width: 206, height: 17)
        let opacitySlider = NSSlider(
            value: Double(panel.coverFlowSideOpacity),
            minValue: 0.2,
            maxValue: 1,
            target: self,
            action: #selector(changeCoverFlowSideOpacity(_:))
        )
        opacitySlider.frame = NSRect(x: 12, y: 4, width: 206, height: 20)
        opacitySlider.isContinuous = true
        opacityView.addSubview(opacityLabel)
        opacityView.addSubview(opacitySlider)
        opacityItem.view = opacityView
        interactionMenu.addItem(opacityItem)

        let directionItem = NSMenuItem(title: "滚动方向", action: nil, keyEquivalent: "")
        let directionMenu = NSMenu()
        for direction in CoverFlowScrollDirection.allCases {
            let item = NSMenuItem(title: direction.label, action: #selector(selectCoverFlowScrollDirection(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = direction.rawValue
            item.state = direction == tapController.coverFlowScrollDirection ? .on : .off
            directionMenu.addItem(item)
        }
        directionItem.submenu = directionMenu
        interactionMenu.addItem(directionItem)

        let sensitivityItem = NSMenuItem(title: "触控板灵敏度", action: nil, keyEquivalent: "")
        let sensitivityMenu = NSMenu()
        for sensitivity in CoverFlowScrollSensitivity.allCases {
            let item = NSMenuItem(title: sensitivity.label, action: #selector(selectCoverFlowScrollSensitivity(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = sensitivity.rawValue
            item.state = sensitivity == tapController.coverFlowScrollSensitivity ? .on : .off
            sensitivityMenu.addItem(item)
        }
        sensitivityItem.submenu = sensitivityMenu
        interactionMenu.addItem(sensitivityItem)

        let snapDelayItem = NSMenuItem(title: "停止后选中", action: nil, keyEquivalent: "")
        let snapDelayMenu = NSMenu()
        for delay in CoverFlowSnapDelay.allCases {
            let item = NSMenuItem(title: delay.label, action: #selector(selectCoverFlowSnapDelay(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = delay.rawValue
            item.state = delay == tapController.coverFlowSnapDelay ? .on : .off
            snapDelayMenu.addItem(item)
        }
        snapDelayItem.submenu = snapDelayMenu
        interactionMenu.addItem(snapDelayItem)

        interactionItem.submenu = interactionMenu
        menu.addItem(interactionItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出 AltTabLite", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func selectPanelStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = PanelStyle(rawValue: raw) else { return }
        panel.style = style
        UserDefaults.standard.set(style.rawValue, forKey: "panelStyle")
        sender.menu?.items.forEach { $0.state = ($0 === sender) ? .on : .off }
        log("panel style set to \(style.rawValue)")
    }

    @objc private func selectPanelSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let preset = PanelSize(rawValue: raw) else { return }
        panel.size = preset
        UserDefaults.standard.set(preset.rawValue, forKey: "panelSize")
        sender.menu?.items.forEach { $0.state = ($0 === sender) ? .on : .off }
        log("panel size set to \(preset.rawValue) (icon: \(Int(preset.iconSize))pt, font: \(Int(preset.fontSize))pt)")
    }

    @objc private func toggleSelectionAnimation(_ sender: NSMenuItem) {
        panel.selectionAnimationEnabled.toggle()
        UserDefaults.standard.set(panel.selectionAnimationEnabled, forKey: "selectionAnimationEnabled")
        sender.state = panel.selectionAnimationEnabled ? .on : .off
        log("selection animation enabled=\(panel.selectionAnimationEnabled)")
    }

    @objc private func toggleCoverFlowAppName(_ sender: NSMenuItem) {
        panel.coverFlowShowsAppName.toggle()
        UserDefaults.standard.set(panel.coverFlowShowsAppName, forKey: "coverFlowShowsAppName")
        sender.state = panel.coverFlowShowsAppName ? .on : .off
        log("cover flow shows app name=\(panel.coverFlowShowsAppName)")
    }

    @objc private func toggleCoverFlowCurrentWindowDot(_ sender: NSMenuItem) {
        panel.coverFlowShowsCurrentWindowDot.toggle()
        UserDefaults.standard.set(panel.coverFlowShowsCurrentWindowDot, forKey: "coverFlowShowsCurrentWindowDot")
        sender.state = panel.coverFlowShowsCurrentWindowDot ? .on : .off
        log("cover flow shows current window dot=\(panel.coverFlowShowsCurrentWindowDot)")
    }

    @objc private func changeCoverFlowSideOpacity(_ sender: NSSlider) {
        panel.coverFlowSideOpacity = Float(sender.doubleValue)
        UserDefaults.standard.set(sender.doubleValue, forKey: "coverFlowSideOpacity")
        if let label = sender.superview?.viewWithTag(1) as? NSTextField {
            label.stringValue = "侧边图标透明度 \(Int((sender.doubleValue * 100).rounded()))%"
        }
        log("cover flow side opacity=\(panel.coverFlowSideOpacity)")
    }

    @objc private func selectCoverFlowScrollDirection(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let direction = CoverFlowScrollDirection(rawValue: raw) else { return }
        tapController.coverFlowScrollDirection = direction
        UserDefaults.standard.set(direction.rawValue, forKey: "coverFlowScrollDirection")
        sender.menu?.items.forEach { $0.state = ($0 === sender) ? .on : .off }
        log("cover flow scroll direction=\(direction.rawValue)")
    }

    @objc private func selectCoverFlowScrollSensitivity(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let sensitivity = CoverFlowScrollSensitivity(rawValue: raw) else { return }
        tapController.coverFlowScrollSensitivity = sensitivity
        UserDefaults.standard.set(sensitivity.rawValue, forKey: "coverFlowScrollSensitivity")
        sender.menu?.items.forEach { $0.state = ($0 === sender) ? .on : .off }
        log("cover flow scroll sensitivity=\(sensitivity.rawValue)")
    }

    @objc private func selectCoverFlowSnapDelay(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let delay = CoverFlowSnapDelay(rawValue: raw) else { return }
        tapController.coverFlowSnapDelay = delay
        UserDefaults.standard.set(delay.rawValue, forKey: "coverFlowSnapDelay")
        sender.menu?.items.forEach { $0.state = ($0 === sender) ? .on : .off }
        log("cover flow snap delay=\(delay.rawValue)")
    }
}
