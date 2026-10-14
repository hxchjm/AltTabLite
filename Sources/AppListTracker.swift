import AppKit

final class AppListTracker {
    private var mruOrder: [pid_t] = []
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NSWorkspace.shared.notificationCenter

        observers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.moveToFront(pid: app.processIdentifier)
        })

        observers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.forget(pid: app.processIdentifier)
        })

        var seed: [pid_t] = []
        if let front = NSWorkspace.shared.frontmostApplication {
            seed.append(front.processIdentifier)
        }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if !seed.contains(app.processIdentifier) {
                seed.append(app.processIdentifier)
            }
        }
        mruOrder = seed
    }

    func orderedApplications() -> [NSRunningApplication] {
        if let front = NSWorkspace.shared.frontmostApplication {
            moveToFront(pid: front.processIdentifier)
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var seen = Set<pid_t>()
        var result: [NSRunningApplication] = []

        func collect(_ app: NSRunningApplication) {
            let pid = app.processIdentifier
            guard pid != ownPID, !seen.contains(pid), !app.isTerminated, app.activationPolicy == .regular else { return }
            seen.insert(pid)
            result.append(app)
        }

        for pid in mruOrder {
            if let app = NSRunningApplication(processIdentifier: pid) {
                collect(app)
            }
        }
        for app in NSWorkspace.shared.runningApplications {
            collect(app)
        }

        mruOrder = result.map { $0.processIdentifier }
        return result
    }

    private func moveToFront(pid: pid_t) {
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }
        mruOrder.removeAll { $0 == pid }
        mruOrder.insert(pid, at: 0)
    }

    private func forget(pid: pid_t) {
        mruOrder.removeAll { $0 == pid }
    }
}
