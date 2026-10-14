import AppKit
import ApplicationServices
import Darwin

struct SwitchEntry {
    let app: NSRunningApplication
    let axWindow: AXUIElement?
    let title: String
    let windowID: CGWindowID?

    var key: String {
        if let windowID = windowID {
            return "\(app.processIdentifier)-\(windowID)"
        }
        return "\(app.processIdentifier)-app"
    }
}

enum WindowEnumerator {
    private typealias AXGetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    private static let axGetWindow: AXGetWindowFn? = {
        let paths = [
            "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
            "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices",
        ]
        for path in paths {
            guard let handle = dlopen(path, RTLD_LAZY), let symbol = dlsym(handle, "_AXUIElementGetWindow") else { continue }
            return unsafeBitCast(symbol, to: AXGetWindowFn.self)
        }
        return nil
    }()

    static func entries(for apps: [NSRunningApplication]) -> [SwitchEntry] {
        let zOrder = windowZOrder()
        let fallbackBase = max(100_000, (zOrder.values.max() ?? 0) + 1)
        var ranked: [(entry: SwitchEntry, rank: Int)] = []

        for (appIndex, app) in apps.enumerated() {
            let windows = entries(for: app)
            if windows.isEmpty {
                let entry = SwitchEntry(app: app, axWindow: nil, title: app.localizedName ?? "?", windowID: nil)
                ranked.append((entry, fallbackBase + appIndex * 1_000))
                continue
            }
            for (windowIndex, entry) in windows.enumerated() {
                let rank = entry.windowID.flatMap { zOrder[$0] }
                    ?? fallbackBase + appIndex * 1_000 + windowIndex
                ranked.append((entry, rank))
            }
        }

        ranked.sort { $0.rank < $1.rank }
        return ranked.map { $0.entry }
    }

    private static func entries(for app: NSRunningApplication) -> [SwitchEntry] {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.25)

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let elements = value as? [AXUIElement] else { return [] }

        var entries: [SwitchEntry] = []
        for element in elements {
            if let subrole = stringAttribute(element, kAXSubroleAttribute),
               subrole != "AXStandardWindow", subrole != "AXDialog" {
                continue
            }
            var cgID = CGWindowID(0)
            let hasID = axGetWindow.map { $0(element, &cgID) == .success } ?? false
            var title = stringAttribute(element, kAXTitleAttribute) ?? ""
            if title.isEmpty {
                title = app.localizedName ?? "?"
            }
            entries.append(SwitchEntry(app: app, axWindow: element, title: title, windowID: hasID ? cgID : nil))
        }
        return entries
    }

    private static func windowZOrder() -> [CGWindowID: Int] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var ranks: [CGWindowID: Int] = [:]
        var rank = 0
        for info in list {
            guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0,
                  let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            ranks[CGWindowID(number)] = rank
            rank += 1
        }
        return ranks
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
