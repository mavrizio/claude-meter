import AppKit
import MeterCore
import SwiftUI

/// The window that drops down from the menu bar icon.
struct PanelView: View {
    @Environment(AppModel.self) private var model
    var inWindow = false

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            header
            if inWindow {
                Label("Claude Meter vive nella barra dei menu, in alto a destra. Puoi chiudere questa finestra: continua a funzionare. Per riaprirla, apri di nuovo l'app.",
                      systemImage: "menubar.arrow.up.rectangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.setup != .ours { SetupCard() }

            HStack(spacing: 22) {
                RingGauge(title: "SESSIONE 5H", window: valid(model.state?.fiveHour),
                          windowLength: UsageWindow.fiveHourLength, now: model.now)
                RingGauge(title: "SETTIMANA", window: valid(model.state?.sevenDay),
                          windowLength: UsageWindow.sevenDayLength, now: model.now)
            }
            .frame(maxWidth: .infinity)

            if let s = model.state {
                StatsRow(state: s)
                Text(updatedText(s))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Apri Claude Code nel terminale e invia un messaggio: i limiti compaiono dopo la prima risposta.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let n = model.notice {
                HStack(alignment: .top) {
                    Text(n).font(.caption).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            Divider()

            Toggle("Avvia al login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            Toggle("Percentuali nella barra dei menu", isOn: $model.showPercentInMenuBar)

            HStack {
                Button(model.paused ? "Riprendi collegamento" : "Sospendi collegamento") { model.paused.toggle() }
                    .help("Libera la porta USB, per esempio per aggiornare il firmware")
                Spacer()
                Menu {
                    Toggle("Dati dimostrativi", isOn: $model.demo)
                    Divider()
                    Button("Rimuovi configurazione da Claude Code") { model.removeClaudeCodeConfiguration() }
                    Divider()
                    Text("Claude Meter \(MeterVersion.marketing) (\(MeterVersion.build))")
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Button("Esci") { NSApp.terminate(nil) }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(16)
        .frame(width: 340)
        .onAppear { model.refreshSetup() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3).fill(Palette.accent).frame(width: 11, height: 11)
            Text("Claude Meter").font(.headline)
            if model.demo {
                Text("DEMO").font(.caption2.bold()).padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Palette.accent.opacity(0.2), in: Capsule())
            }
            Spacer()
            DeviceChip(status: model.link)
        }
    }

    private func valid(_ w: UsageWindow?) -> UsageWindow? {
        guard let w, w.isValid(at: model.now) else { return nil }
        return w
    }

    private func updatedText(_ s: UsageState) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.unitsStyle = .full
        let when = f.localizedString(for: s.updatedDate, relativeTo: model.now)
        return ["Aggiornato da Claude Code \(when)", s.model].compactMap { $0 }.joined(separator: " · ")
    }
}

struct DeviceChip: View {
    let status: DeviceLink.Status

    var body: some View {
        let (color, text, help): (Color, String, String) = {
            switch status {
            case let .connected(port, fw): return (Palette.green.color, "Display collegato", "\(port) · firmware \(fw)")
            case let .probing(port): return (Palette.amber.color, "Verifico...", port)
            case .searching: return (.secondary, "Display non trovato", "Collega il display con un cavo USB dati")
            case .paused: return (.secondary, "In pausa", "Collegamento sospeso")
            }
        }()
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
        .help(help)
    }
}

struct StatsRow: View {
    let state: UsageState

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            stat("CONTESTO") {
                HStack(spacing: 6) {
                    ProgressView(value: min(state.contextPct ?? 0, 100), total: 100)
                        .tint(Palette.level(state.contextPct ?? 0))
                        .frame(width: 60)
                    Text(state.contextPct.map { "\(Int($0.rounded()))%" } ?? "--").monospacedDigit()
                }
            }
            stat("COSTO") {
                Text(state.costUsd.map { String(format: "$%.2f", $0) } ?? "--").monospacedDigit()
            }
            stat("RIGHE") {
                HStack(spacing: 6) {
                    Text("+\(state.linesAdded ?? 0)").foregroundStyle(Palette.green.color)
                    Text("-\(state.linesRemoved ?? 0)").foregroundStyle(Palette.red.color)
                }
                .monospacedDigit()
            }
        }
        .font(.callout)
        .padding(10)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }

    private func stat<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 9, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shown until Claude Code's statusLine points at this app.
struct SetupCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let (title, text, button): (String, String, String?) = {
            switch model.setup {
            case .missing:
                return ("Collega Claude Code",
                        "Claude Meter legge i limiti dalla barra di stato di Claude Code. Aggiungo la voce statusLine in ~/.claude/settings.json (ne faccio prima un backup).",
                        "Configura")
            case .oursOutdated:
                return ("Aggiorna la configurazione",
                        "La barra di stato di Claude Code usa una versione precedente di Claude Meter.",
                        "Aggiorna")
            case let .other(cmd):
                return ("Hai gia' una barra di stato",
                        "Claude Code usa: \(cmd)\nSe la sostituisci, la trovi nel backup di settings.json.",
                        "Sostituisci")
            case .unreadable:
                return ("settings.json non leggibile",
                        "~/.claude/settings.json non e' un JSON valido: correggilo, poi riapri questo pannello.",
                        nil)
            case .ours:
                return ("", "", nil)
            }
        }()
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "terminal").font(.subheadline.bold())
            Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let button {
                Button(button) { model.configureClaudeCode() }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }
}
