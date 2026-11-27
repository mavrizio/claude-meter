import MeterCore
import SwiftUI

/// 270° ring like the device: track, coloured value with glow, white "pace" dot, reset countdown.
struct RingGauge: View {
    let title: String
    let window: UsageWindow?
    let windowLength: Int
    let now: Date

    private let size: CGFloat = 132
    private let stroke: CGFloat = 11

    var body: some View {
        let pct = window?.pct ?? 0
        let color = Palette.level(pct)
        let radius = (size - stroke) / 2

        ZStack {
            arc(to: 1).stroke(Palette.track, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            arc(to: min(pct, 100) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .shadow(color: color.opacity(0.55), radius: 6)
                .animation(.easeInOut(duration: 0.9), value: pct)

            if let w = window {
                let pace = w.pace(at: now, windowLength: windowLength)
                Circle()
                    .fill(.white)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(.black.opacity(0.55), lineWidth: 1.5))
                    .offset(x: radius)
                    .rotationEffect(.degrees(135 + 270 * pace))
                    .help("Ritmo: \(Int(pace * 100))% della finestra e' trascorso")
            }

            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(window.map { "\(Int($0.pct.rounded()))" } ?? "--")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeInOut, value: pct)
                    if window != nil {
                        Text("%").font(.system(size: 14, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                    }
                }
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
            }
            .offset(y: -4)

            if let w = window {
                Label(MeterFormat.remaining(w.remaining(at: now)), systemImage: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                    .offset(y: size / 2 - 8)
                    .help("Si azzera tra \(MeterFormat.remaining(w.remaining(at: now)))")
            }
        }
        .frame(width: size, height: size)
    }

    private func arc(to fraction: Double) -> some Shape {
        Circle()
            .inset(by: stroke / 2)
            .trim(from: 0, to: 0.75 * max(fraction, 0))
            .rotation(.degrees(135))
    }
}
