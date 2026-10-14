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
    private struct WindowMetadata {
        let bounds: CGRect
        let layer: Int
        let isOnScreen: Bool
    }

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
        let metadata = windowMetadata()
        let fallbackBase = max(100_000, (zOrder.values.max() ?? 0) + 1)
        var ranked: [(entry: SwitchEntry, rank: Int)] = []

        for (appIndex, app) in apps.enumerated() {
            let windows = entries(for: app, metadata: metadata)
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

    private static func entries(for app: NSRunningApplication, metadata: [CGWindowID: WindowMetadata]) -> [SwitchEntry] {
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
            let rawTitle = stringAttribute(element, kAXTitleAttribute) ?? ""
            let isMinimized = boolAttribute(element, kAXMinimizedAttribute) ?? false

            if hasID, let window = metadata[cgID] {
                guard window.layer == 0 else { continue }
                guard isMinimized || (window.bounds.width >= 120 && window.bounds.height >= 80) else { continue }
                guard !rawTitle.isEmpty || window.isOnScreen || isMinimized else { continue }
            }

            let title = rawTitle.isEmpty ? app.localizedName ?? "?" : rawTitle
            entries.append(SwitchEntry(app: app, axWindow: element, title: title, windowID: hasID ? cgID : nil))
        }
        return entries
    }

    private static func windowMetadata() -> [CGWindowID: WindowMetadata] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var result: [CGWindowID: WindowMetadata] = [:]
        for info in list {
            guard let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else { continue }
            let isOnScreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
            result[CGWindowID(number)] = WindowMetadata(bounds: bounds, layer: layer, isOnScreen: isOnScreen)
        }
        return result
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

    private static func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? Bool
    }
}
