import Cocoa

// MARK: - Data

struct UsageItem {
    let label: String
    let percent: Int
    let reset: String
}

// MARK: - Custom Bar View

class UsageBarView: NSView {
    var items: [UsageItem] = []
    weak var statusItem: NSStatusItem?

    private let barColors: [NSColor] = [.systemGreen, .systemBlue, .systemOrange]

    func update(with newItems: [UsageItem]) {
        items = newItems
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        bounds.fill()

        guard !items.isEmpty else { return }

        let barCount = min(items.count, 3)
        let barWidth: CGFloat = 14
        let gap: CGFloat = 3
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
        let startX = (bounds.width - totalWidth) / 2
        let maxHeight = bounds.height - 8
        let bottomY: CGFloat = 4

        for i in 0..<barCount {
            let item = items[i]
            let barHeight = max(2, maxHeight * CGFloat(item.percent) / 100)
            let x = startX + CGFloat(i) * (barWidth + gap)
            let rect = NSRect(x: x, y: bottomY, width: barWidth, height: barHeight)

            let color = i < barColors.count ? barColors[i] : .systemGray
            color.set()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        if let menu = statusItem?.menu {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height), in: self)
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var barView: UsageBarView!
    var timer: Timer?
    let scriptPath: String

    override init() {
        scriptPath = NSHomeDirectory() + "/WebstormProjects/OpencodeDashboard/index.js"
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: 54)

        barView = UsageBarView(frame: NSRect(x: 0, y: 0, width: 54, height: NSStatusBar.system.thickness))
        barView.statusItem = statusItem
        statusItem.view = barView

        buildMenu(items: [], loading: true)
        refresh()

        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    // MARK: - Fetch

    @objc func refresh() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            let items = self.fetchUsage()
            DispatchQueue.main.async {
                self.updateUI(items: items)
            }
        }
    }

    func fetchUsage() -> [UsageItem] {
        let task = Process()
        let pipe = Pipe()

        let nodeCandidates = ["/usr/local/bin/node", "/opt/homebrew/bin/node", "/Users/you/.nvm/versions/node/v22.21.0/bin/node"]
        guard let node = nodeCandidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return [UsageItem(label: "node not found", percent: 0, reset: "")]
        }

        task.executableURL = URL(fileURLWithPath: node)
        task.arguments = [scriptPath, "--json"]
        task.standardOutput = pipe
        task.standardError = FileHandle.standardError

        let env = ProcessInfo.processInfo.environment
        task.environment = env

        task.launch()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        return parseOutput(output)
    }

    // MARK: - Parsing

    func parseOutput(_ output: String) -> [UsageItem] {
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return json.compactMap { dict in
            guard let label = dict["label"] as? String,
                  let percent = dict["percent"] as? Int,
                  let reset = dict["reset"] as? String
            else { return nil }
            return UsageItem(label: label, percent: percent, reset: reset)
        }
    }

    // MARK: - UI

    func updateUI(items: [UsageItem]) {
        barView.update(with: items)
        buildMenu(items: items, loading: false)
    }

    func buildMenu(items: [UsageItem], loading: Bool) {
        let menu = NSMenu()

        if loading {
            menu.addItem(NSMenuItem(title: "Loading…", action: nil, keyEquivalent: ""))
        } else if items.isEmpty {
            menu.addItem(NSMenuItem(title: "No data (check cookie/script path)", action: nil, keyEquivalent: ""))
        } else {
            for item in items {
                let bar = progressBar(percent: item.percent, width: 20)
                let title = "\(item.label)  \(bar) \(item.percent)%"
                let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                mi.isEnabled = false
                menu.addItem(mi)

                if !item.reset.isEmpty {
                    let resetItem = NSMenuItem(title: "  \(item.reset)", action: nil, keyEquivalent: "")
                    resetItem.isEnabled = false
                    resetItem.attributedTitle = NSAttributedString(
                        string: "  \(item.reset)",
                        attributes: [.foregroundColor: NSColor.secondaryLabelColor,
                                     .font: NSFont.systemFont(ofSize: 11)]
                    )
                    menu.addItem(resetItem)
                }
                menu.addItem(.separator())
            }
        }

        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func progressBar(percent: Int, width: Int) -> String {
        let filled = Int(Double(percent) / 100.0 * Double(width))
        let clamped = max(0, min(filled, width))
        return String(repeating: "█", count: clamped) + String(repeating: "░", count: width - clamped)
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // no Dock icon
app.run()