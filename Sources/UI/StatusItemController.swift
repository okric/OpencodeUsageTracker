import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let openSettings: () -> Void
    private let statusItem: NSStatusItem
    private let view: UsageBarView
    private let menu = NSMenu()
    private var cancellables = Set<AnyCancellable>()

    private var isMenuOpen = false
    private var needsMenuRebuild = false

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: 120)
        self.view = UsageBarView(frame: NSRect(x: 0, y: 0, width: 120, height: 22))
        super.init()

        menu.autoenablesItems = false
        menu.delegate = self
        view.onOpenMenu = { [weak self] in self?.openMenu() }
        view.toolTip = "OpenCode usage"
        statusItem.view = view
        statusItem.menu = nil

        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // objectWillChange fires before the property is stored.
                DispatchQueue.main.async { self?.render() }
            }
            .store(in: &cancellables)

        render()
    }

    // MARK: Rendering

    private func render() {
        let snapshot = model.snapshot

        let state: UsageBarView.DisplayState
        if model.needsSetup {
            state = .setup
        } else if model.isLoading && !snapshot.hasItems {
            state = .loading
        } else if snapshot.error != nil && snapshot.updatedAt == nil {
            state = .error
        } else if model.isLoading {
            state = .loading
        } else {
            state = .normal
        }

        view.update(with: snapshot.items, state: state)
        view.toolTip = tooltip(snapshot: snapshot)
        rebuildMenu()
    }

    private func tooltip(snapshot: UsageSnapshot) -> String {
        var lines = snapshot.items.map { "\($0.label) — \($0.value) · \($0.percent)% · \($0.resetShort)" }
        if lines.isEmpty { lines = ["OpenCode usage"] }
        if model.isLoading { lines.append("Refreshing…") }
        if let error = snapshot.error, !error.isEmpty { lines.append(error) }
        return lines.joined(separator: "\n")
    }

    private func rebuildMenu() {
        guard !isMenuOpen else {
            needsMenuRebuild = true
            return
        }
        needsMenuRebuild = false

        menu.removeAllItems()

        if model.needsSetup {
            addSecondary("No OpenCode cookie yet")
            addAction("Enter Cookie…", action: #selector(settingsAction), symbol: "key")
            menu.addItem(.separator())
            addFooter()
            return
        }

        if let error = model.snapshot.error, !error.isEmpty {
            addWarning(error)
            menu.addItem(.separator())
        }

        if !model.snapshot.hasItems {
            if model.isLoading {
                addSecondary("Loading…")
            } else {
                addSecondary("No usage data")
            }
        } else {
            for item in model.snapshot.items {
                let bar = progressBar(percent: item.percent, width: 20)
                let title = "\(item.label)  \(bar) \(item.percent)%"
                addBold(title)

                var details: [String] = []
                if !item.value.isEmpty { details.append(item.value) }
                if !item.reset.isEmpty { details.append("resets in " + item.reset.lowercased()) }
                if !details.isEmpty {
                    addSecondary("  " + details.joined(separator: " · "))
                }
            }
        }

        if let updated = model.snapshot.updatedAt {
            var text = "Updated \(Fmt.time(updated))"
            if model.snapshot.isStale { text += " · stale" }
            menu.addItem(.separator())
            addSecondary(text)
        }

        menu.addItem(.separator())
        addFooter()
    }

    private func addFooter() {
        addAction("Refresh", action: #selector(refreshAction), key: "r", symbol: "arrow.clockwise")
        if model.isLoading {
            addSecondary("Refreshing…")
        }
        addAction("Settings…", action: #selector(settingsAction), key: ",", symbol: "gearshape")
        addAction("Open Workspace Page", action: #selector(usagePageAction), symbol: "safari")
        menu.addItem(.separator())
        addAction("Quit", action: #selector(quitAction), key: "q", symbol: "power")
    }

    // MARK: Menu item helpers

    private func addBold(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ])
        menu.addItem(item)
    }

    private func addSecondary(_ title: String, color: NSColor = .secondaryLabelColor) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: color,
            ])
        menu.addItem(item)
    }

    private func addWarning(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.toolTip = title
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.systemRed,
            ])
        menu.addItem(item)
    }

    private func addAction(
        _ title: String,
        action: Selector,
        key: String = "",
        symbol: String? = nil
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        menu.addItem(item)
    }

    // MARK: Menu lifecycle

    private func openMenu() {
        guard !menu.items.isEmpty else { return }
        // The custom status view is not flipped, so anchor the menu just below
        // the menu bar instead of above the item.
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: -4),
            in: view)
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        if needsMenuRebuild {
            render()
        }
    }

    // MARK: Actions

    @objc private func refreshAction() {
        model.refreshNow()
    }

    @objc private func settingsAction() {
        openSettings()
    }

    @objc private func usagePageAction() {
        model.openWorkspacePage()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    // MARK: Format

    private func progressBar(percent: Int, width: Int) -> String {
        let filled = Int(Double(percent) / 100.0 * Double(width))
        let clamped = max(0, min(filled, width))
        return String(repeating: "█", count: clamped) + String(repeating: "░", count: width - clamped)
    }
}

enum Fmt {
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .standard)
    }
}
