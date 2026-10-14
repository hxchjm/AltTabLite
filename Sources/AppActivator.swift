import AppKit
import ApplicationServices
import Darwin

enum AppActivator {
    static var windowLevelActivationAvailable: Bool {
        WindowServerFocus.isAvailable
    }

    static func activate(_ entry: SwitchEntry) {
        let app = entry.app
        guard !app.isTerminated else { return }

        if app.isHidden {
            app.unhide()
        }

        if let window = entry.axWindow, let windowID = entry.windowID {
            unminimize(window)
            let privateStatus = WindowServerFocus.focus(pid: app.processIdentifier, windowID: windowID)
            if privateStatus.fronted {
                let raiseStatus = raise(window)
                log("activate-window [\(app.localizedName ?? "?")] \(entry.title) key=\(entry.key) front=\(privateStatus.frontStatus) key=\(privateStatus.keyStatus) raise=\(raiseStatus.rawValue)")
                return
            }
            log("window-level activation unavailable, falling back: front=\(privateStatus.frontStatus)")
        }

        activateApplication(app)
        var raiseStatus = "app-level"
        if let window = entry.axWindow {
            raiseStatus = String(raise(window).rawValue)
        }
        log("activate-fallback [\(app.localizedName ?? "?")] \(entry.title) key=\(entry.key) raise=\(raiseStatus)")
    }

    private static func activateApplication(_ app: NSRunningApplication) {
        if #available(macOS 14.0, *) {
            let from = NSWorkspace.shared.frontmostApplication ?? NSRunningApplication.current
            _ = app.activate(from: from, options: [])
        } else {
            _ = app.activate(options: [.activateIgnoringOtherApps])
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        _ = AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    }

    private static func unminimize(_ window: AXUIElement) {
        var minimized: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized) == .success,
           (minimized as? Bool) == true {
            _ = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
    }

    private static func raise(_ window: AXUIElement) -> AXError {
        unminimize(window)
        let result = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        _ = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        return result
    }
}

private enum WindowServerFocus {
    private typealias GetProcess = @convention(c) (
        pid_t, UnsafeMutablePointer<ProcessSerialNumber>
    ) -> OSStatus
    private typealias SetFrontProcessWithOptions = @convention(c) (
        UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32
    ) -> CGError
    private typealias PostEventRecord = @convention(c) (
        UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>
    ) -> CGError

    private static let framework = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
        RTLD_LAZY | RTLD_LOCAL
    )
    private static let applicationServices = dlopen(
        "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
        RTLD_LAZY | RTLD_LOCAL
    )

    private static let getProcess: GetProcess? = load("GetProcessForPID")
    private static let setFront: SetFrontProcessWithOptions? = load("_SLPSSetFrontProcessWithOptions")
    private static let postEvent: PostEventRecord? = load("SLPSPostEventRecordTo")

    static var isAvailable: Bool {
        getProcess != nil && setFront != nil && postEvent != nil
    }

    static func focus(pid: pid_t, windowID: CGWindowID) -> (fronted: Bool, frontStatus: Int32, keyStatus: Int32) {
        guard let getProcess, let setFront, let postEvent else { return (false, -1, -1) }

        var psn = ProcessSerialNumber()
        guard getProcess(pid, &psn) == noErr else { return (false, -2, -1) }

        let frontStatus = setFront(&psn, windowID, 0x200)
        guard frontStatus == .success else { return (false, frontStatus.rawValue, -1) }
        let keyStatus = makeKeyWindow(&psn, windowID, postEvent)
        return (true, frontStatus.rawValue, keyStatus.rawValue)
    }

    private static func makeKeyWindow(
        _ psn: inout ProcessSerialNumber,
        _ windowID: CGWindowID,
        _ postEvent: PostEventRecord
    ) -> CGError {
        var windowID = windowID
        var point = CGPoint(x: 300_000, y: 300_000)
        var bytes = [UInt8](repeating: 0, count: 0x100)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        bytes[0x08] = 0x01
        _ = withUnsafeMutableBytes(of: &windowID) { source in
            bytes.withUnsafeMutableBytes { destination in
                memcpy(destination.baseAddress!.advanced(by: 0x3c), source.baseAddress!, source.count)
            }
        }
        _ = withUnsafeMutableBytes(of: &point) { source in
            bytes.withUnsafeMutableBytes { destination in
                memcpy(destination.baseAddress!.advanced(by: 0x20), source.baseAddress!, source.count)
            }
        }
        return bytes.withUnsafeMutableBufferPointer { buffer in
            postEvent(&psn, buffer.baseAddress!)
        }
    }

    private static func load<T>(_ name: String) -> T? {
        for handle in [framework, applicationServices].compactMap({ $0 }) {
            if let symbol = dlsym(handle, name) {
                return unsafeBitCast(symbol, to: T.self)
            }
        }
        return nil
    }
}
