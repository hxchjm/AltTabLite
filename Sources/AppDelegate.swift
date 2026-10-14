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
        panel.selectionAnimationEnabled = UserDefaults.standard.bool(forKey: "selectionAnimationEnabled")
        tapController = EventTapController(appList: appList, panel: panel)
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

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出 AltTabLite", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
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
}
