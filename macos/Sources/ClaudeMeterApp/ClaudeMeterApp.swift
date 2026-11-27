import MeterCore
import SwiftUI

@main
struct ClaudeMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environment(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Icon + "23% · 41%" in the menu bar.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        let s = model.state
        let fh = s?.fiveHour.flatMap { $0.isValid(at: model.now) ? $0 : nil }
        let sd = s?.sevenDay.flatMap { $0.isValid(at: model.now) ? $0 : nil }
        HStack(spacing: 4) {
            Image(systemName: model.menuBarSymbol)
            if model.showPercentInMenuBar, fh != nil || sd != nil {
                Text("\(pct(fh)) · \(pct(sd))").monospacedDigit()
            }
        }
    }

    private func pct(_ w: UsageWindow?) -> String { w.map { "\(Int($0.pct.rounded()))%" } ?? "--" }
}
