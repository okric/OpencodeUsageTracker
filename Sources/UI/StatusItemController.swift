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
        self.statusItem = NSStatusBar.system.statusItem(withLength: 68)
        self.view = UsageBarView(frame: NSRect(x: 0, y: 0, width: 68, height: 22))
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
        if model.connectionInfo == nil && !model.isLoading {
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

        // Fit the item to its content instead of a fixed width; the reset
        // text is the only thing that needs room on the right.
        let width = idealWidth(items: snapshot.items, state: state)
        if statusItem.length != width { statusItem.length = width }
        view.setFrameSize(NSSize(width: width, height: 22))

        view.update(with: snapshot.items, state: state)
        view.toolTip = tooltip(snapshot: snapshot)
        rebuildMenu()
    }

    /// leftPad(4) + bars(60) + gap(4), plus the widest reset countdown when it
    /// is drawn (normal and loading states); setup and error states omit it.
    private func idealWidth(items: [UsageItem], state: UsageBarView.DisplayState) -> CGFloat {
        let base: CGFloat = 68
        let showsResets = (state == .normal || state == .loading)
            && items.contains(where: { !$0.resetShort.isEmpty })
        guard showsResets else { return base }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 7, weight: .regular)
        let textWidth = items.prefix(3)
            .map { ($0.resetShort as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        return min(96, base + textWidth.rounded(.up) + 2)
    }

    private func tooltip(snapshot: UsageSnapshot) -> String {
        var lines = snapshot.items.map { "\($0.label) · \($0.percent)% · \($0.reset)" }
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

        let configured = model.connectionInfo != nil

        if let name = model.connectionInfo {
            addSecondary(name, color: .tertiaryLabelColor.withAlphaComponent(0.9))
        } else {
            addSecondary("OpenCode CLI not linked")
        }

        guard configured else {
            addSecondary("Run the opencode CLI and connect this device.")
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

                if !item.reset.isEmpty {
                    addSecondary("  \(item.reset)")
                }
            }

            let budgets = model.snapshot.budgets
            if !budgets.isEmpty {
                menu.addItem(.separator())
                addBold("Budgets")
                for budget in budgets {
                    let spent = String(format: "%.2f", budget.spent)
                    let limit = String(format: "%.2f", budget.limit)
                    var text = "  \(budget.name) — $\(spent) of $\(limit)"
                    if !budget.resetsText.isEmpty {
                        text += " · \(budget.resetsText.lowercased())"
                    }
                    addSecondary("  \(text)", color: secondaryColor(for: budget))
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

    private func secondaryColor(for budget: Budget) -> NSColor {
        budget.percent >= 90 ? .systemRed : .secondaryLabelColor
    }

    private func addFooter() {
        addAction("Refresh", action: #selector(refreshAction), key: "r", symbol: "arrow.clockwise")
        if model.isLoading {
            addSecondary("Refreshing…")
        }
        addAction("Settings…", action: #selector(settingsAction), key: ",", symbol: "gearshape")
        addAction("Open Usage Page", action: #selector(usagePageAction), symbol: "safari")
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
        if !model.openActivityPage() {
            openSettings()
        }
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
