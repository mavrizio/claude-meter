import AppKit
import SwiftUI

/// Development aid: `ClaudeMeter --snapshot /path/panel` renders the menu bar panel with demo data
/// to /path/panel-light.png and /path/panel-dark.png, then quits. No USB, no Claude Code needed.
enum Snapshot {
    static var outputBase: String? {
        guard let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }

    static var requested: Bool { outputBase != nil }

    static func run(model: AppModel) {
        guard let base = outputBase else { return }
        model.tick()
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let host = NSHostingView(rootView: PanelView().environment(model)
                .background(Color(nsColor: .windowBackgroundColor)))
            host.appearance = NSAppearance(named: appearance)
            let size = host.fittingSize
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.backgroundColor = appearance == .darkAqua ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.96, alpha: 1)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            // let SwiftUI settle its first layout pass
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            let url = URL(fileURLWithPath: "\(base)-\(name).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            print("scritto \(url.path)")
        }
        exit(0)
    }
}
