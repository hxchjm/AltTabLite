import AppKit
import ApplicationServices

final class EventTapController {
    private let appList: AppListTracker
    private let panel: SwitcherPanel

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var sessionActive = false
    private var sessionEntries: [SwitchEntry] = []
    private var selectedIndex = 0
    private var pendingSnap: DispatchWorkItem?

    private let tabKeyCode: Int64 = 48
    private let escapeKeyCode: Int64 = 53
    private let upArrowKeyCode: Int64 = 126
    private let downArrowKeyCode: Int64 = 125
    private let leftArrowKeyCode: Int64 = 123
    private let rightArrowKeyCode: Int64 = 124

    init(appList: AppListTracker, panel: SwitcherPanel) {
        self.appList = appList
        self.panel = panel
        panel.onPick = { [weak self] index in self?.commitFromUI(index) }
    }

    func start() -> Bool {
        guard tap == nil else { return true }

        let mask: CGEventMask =
            CGEventMask(1 << CGEventType.keyDown.rawValue) |
            CGEventMask(1 << CGEventType.keyUp.rawValue) |
            CGEventMask(1 << CGEventType.flagsChanged.rawValue) |
            CGEventMask(1 << CGEventType.scrollWheel.rawValue)

        let info = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, info in
                guard let info = info else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<EventTapController>.fromOpaque(info).takeUnretainedValue()
                return controller.handle(type: type, event: event)
            },
            userInfo: info
        ) else {
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap {
                CGEvent.tapEnable(tap: tap, enable: true)
                log("event tap re-enabled after system disable")
            }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            return handleKeyDown(event)
        case .keyUp:
            return handleKeyUp(event)
        case .flagsChanged:
            return handleFlagsChanged(event)
        case .scrollWheel:
            return handleScroll(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        if keyCode == tabKeyCode, flags.contains(.maskAlternate) {
            let backwards = flags.contains(.maskShift)
            if sessionActive {
                advance(backwards: backwards)
            } else {
                beginSession(backwards: backwards)
            }
            return nil
        }

        if keyCode == escapeKeyCode, sessionActive {
            endSession(cancel: true)
            return nil
        }

        if sessionActive, keyCode == upArrowKeyCode || keyCode == downArrowKeyCode {
            advance(backwards: keyCode == upArrowKeyCode)
            return nil
        }

        if sessionActive, panel.style == .coverFlow, keyCode == leftArrowKeyCode || keyCode == rightArrowKeyCode {
            advance(backwards: keyCode == leftArrowKeyCode)
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleKeyUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if keyCode == tabKeyCode, sessionActive || event.flags.contains(.maskAlternate) {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleFlagsChanged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        if sessionActive, !event.flags.contains(.maskAlternate) {
            endSession(cancel: false)
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleScroll(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard sessionActive, panel.style == .coverFlow else { return Unmanaged.passUnretained(event) }
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let dx = event.getDoubleValueField(continuous ? .scrollWheelEventPointDeltaAxis2 : .scrollWheelEventDeltaAxis2)
        let dy = event.getDoubleValueField(continuous ? .scrollWheelEventPointDeltaAxis1 : .scrollWheelEventDeltaAxis1)
        let delta = abs(dx) >= abs(dy) ? dx : dy
        if delta != 0 {
            // A wheel tick spans one cover (50 points), even when macOS reports only a small line delta.
            let points: CGFloat = continuous ? CGFloat(delta) : (delta > 0 ? 50 : -50)
            panel.scrollCoverFlow(by: points, animated: !continuous)
            scheduleScrollSnap()
        }
        return nil
    }

    private func scheduleScrollSnap() {
        pendingSnap?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.snapScroll() }
        pendingSnap = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func snapScroll() {
        guard pendingSnap != nil else { return }
        pendingSnap?.cancel()
        pendingSnap = nil
        guard sessionActive, let index = panel.snapCoverFlow() else { return }
        selectedIndex = index
        log("scroll snap: index \(index)")
    }

    private func beginSession(backwards: Bool) {
        let apps = appList.orderedApplications()
        let startedAt = DispatchTime.now()
        let entries = WindowEnumerator.entries(for: apps)
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds) / 1_000_000
        log(String(format: "session begin (apps: %d, entries: %d, %.1fms, backwards: %@)", apps.count, entries.count, elapsedMs, backwards ? "true" : "false"))
        log("entry titles: \(entries.prefix(24).map { $0.title.prefix(48) }.joined(separator: " | "))")
        guard entries.count > 1 else { return }
        sessionActive = true
        sessionEntries = entries
        selectedIndex = backwards ? entries.count - 1 : 1
        panel.show(entries: entries, selectedIndex: selectedIndex)
    }

    private func advance(backwards: Bool) {
        guard !sessionEntries.isEmpty else { return }
        pendingSnap?.cancel()
        pendingSnap = nil
        let count = sessionEntries.count
        selectedIndex = backwards ? (selectedIndex - 1 + count) % count : (selectedIndex + 1) % count
        panel.show(entries: sessionEntries, selectedIndex: selectedIndex, navigationStep: backwards ? -1 : 1)
    }

    private func commitFromUI(_ index: Int) {
        guard sessionActive, index >= 0, index < sessionEntries.count else { return }
        pendingSnap?.cancel()
        pendingSnap = nil
        selectedIndex = index
        log("ui pick: index \(index)")
        endSession(cancel: false)
    }

    private func endSession(cancel: Bool) {
        if !cancel {
            snapScroll()
        }
        pendingSnap?.cancel()
        pendingSnap = nil
        let entries = sessionEntries
        let index = selectedIndex
        sessionActive = false
        sessionEntries = []
        selectedIndex = 0
        panel.hide()
        let title = (index >= 0 && index < entries.count) ? entries[index].title : "?"
        log("session end (cancel: \(cancel), index: \(index), title: \(title))")
        guard !cancel, index >= 0, index < entries.count else { return }
        let target = entries[index]
        DispatchQueue.main.async {
            AppActivator.activate(target)
        }
    }
}
