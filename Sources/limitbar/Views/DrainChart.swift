import SwiftUI
import Charts

struct DrainChart: View {
    nonisolated static func color(slot: Int, provider: Provider) -> Color {
        let slots: [Color] = provider == .codex || provider == .grok
            ? [.sessionViolet, .sessionTeal, .sessionSky, .sessionOther]
            : [provider.accent, .sessionViolet, .sessionTeal, .sessionOther]
        return slots[min(max(slot, 0), 3)]
    }

    let drain: Drain?
    let readings: [(at: Date, percent: Double)]
    let start: Date
    let resetsAt: Date
    let now: Date
    let usedPercent: Double
    let hot: Bool
    let provider: Provider

    private var neutral: Bool { provider == .gemini || provider == .grok }

    private var bands: [Band] {
        (drain?.bands ?? []).sorted { $0.slot != $1.slot ? $0.slot > $1.slot : $0.at < $1.at }
    }

    var body: some View {
        Chart {
            if let climb = drain?.climb {
                RectangleMark(xStart: .value("Time", climb.from), xEnd: .value("Time", climb.to))
                    .foregroundStyle(Self.color(slot: 0, provider: provider).opacity(0.10))
                    .cornerRadius(6)
            }

            ForEach(Array(bands.enumerated()), id: \.offset) { _, band in
                AreaMark(x: .value("Time", band.at), y: .value("Used", band.value), stacking: .standard)
                    .foregroundStyle(by: .value("Session", String(band.slot)))
            }

            if neutral {
                ForEach(Array(readings.enumerated()), id: \.offset) { _, reading in
                    AreaMark(x: .value("Time", reading.at), y: .value("Used", reading.percent))
                        .foregroundStyle(provider.accent.opacity(provider == .grok ? 0.35 : 0.85))
                }
            }

            ForEach(Array(readings.enumerated()), id: \.offset) { _, reading in
                LineMark(x: .value("Time", reading.at), y: .value("Used", reading.percent), series: .value("Series", "readings"))
                    .foregroundStyle(Color.primary)
                    .lineStyle(StrokeStyle(lineWidth: 1.75, lineJoin: .round))
            }

            if !readings.isEmpty || !bands.isEmpty {
                PointMark(x: .value("Time", now), y: .value("Used", usedPercent))
                    .symbol {
                        Circle().fill(Color.primary).frame(width: 11, height: 11)
                            .padding(4)
                            .background(Circle().fill(Color.primary.opacity(0.15)))
                    }
            }

            RuleMark(x: .value("Time", now))
                .foregroundStyle(Color.primary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .annotation(position: .trailing, alignment: .bottom, spacing: 6) {
                    if resetsAt.timeIntervalSince(now) > resetsAt.timeIntervalSince(start) * 0.25 {
                        Text("now \(Format.clock(now))").font(.system(size: 10.5)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }

            RuleMark(x: .value("Time", resetsAt))
                .foregroundStyle(hot ? AnyShapeStyle(Color.warn) : AnyShapeStyle(Color.secondary))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .annotation(position: .leading, alignment: .bottom, spacing: 6) {
                    Text("resets \(Format.clock(resetsAt))")
                        .font(.system(size: 10.5, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(hot ? AnyShapeStyle(Color.warnText) : AnyShapeStyle(.secondary))
                }

            if let drain, let climb = drain.climb {
                PointMark(x: .value("Time", climb.to), y: .value("Used", total(at: climb.to)))
                    .symbolSize(0)
                    .annotation(position: .trailing, alignment: .top, spacing: 8) { callout(climb, drain: drain) }
            }
        }
        .chartBackground { proxy in
            GeometryReader { geo in
                if let plot = proxy.plotFrame, let from = proxy.position(forX: min(now, resetsAt)), let to = proxy.position(forX: resetsAt) {
                    let frame = geo[plot]
                    Canvas { context, size in
                        var stripes = Path()
                        var x = -size.height
                        while x < size.width {
                            stripes.move(to: CGPoint(x: x, y: size.height))
                            stripes.addLine(to: CGPoint(x: x + size.height, y: 0))
                            x += 6
                        }
                        context.stroke(stripes, with: .color(.primary.opacity(0.06)), lineWidth: 1.5)
                    }
                    .frame(width: max(0, to - from), height: frame.height)
                    .clipped()
                    .offset(x: frame.minX + from, y: frame.minY)
                }
            }
        }
        .chartForegroundStyleScale(domain: ["0", "1", "2", "3"], range: (0...3).map { slot in
            let color = Self.color(slot: slot, provider: provider)
            return LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .top, endPoint: .bottom)
        })
        .chartLegend(.hidden)
        .chartXScale(domain: start...resetsAt)
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let percent = value.as(Int.self) { Text(percent == 0 ? "0" : "\(percent)%").monospacedDigit() }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: xTicks) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) { Text(tickLabel(date)).monospacedDigit() }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Usage chart")
        .accessibilityValue("\(Int(usedPercent.rounded()))% used, resets \(Format.when(resetsAt, now: now))")
    }

    private var weekly: Bool { resetsAt.timeIntervalSince(start) > 86400 }

    private var xTicks: AxisMarkValues {
        if weekly { return .stride(by: .day) }
        return resetsAt.timeIntervalSince(start) > 6 * 3600 ? .stride(by: .hour, count: 4) : .stride(by: .hour)
    }

    private func tickLabel(_ date: Date) -> String {
        guard weekly else { return Format.clock(date) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func total(at time: Date) -> Double {
        Dictionary(grouping: bands.filter { $0.at <= time.addingTimeInterval(1) }, by: \.slot)
            .values.reduce(0) { $0 + ($1.map(\.value).max() ?? 0) }
    }

    private func callout(_ climb: Climb, drain: Drain) -> some View {
        let session = drain.sessions.first { $0.name == climb.session }
        let rise = "+\(Int(climb.rise.rounded()))% in \(Format.duration(climb.to.timeIntervalSince(climb.from)))"
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(Self.color(slot: session?.slot ?? 3, provider: provider)).frame(width: 8, height: 8)
                Text(drain.measured ? rise : "about " + rise)
                    .font(.system(size: 14, weight: .bold, design: .rounded)).monospacedDigit()
            }
            Text([climb.session, session?.detail].compactMap { $0 }.joined(separator: ", "))
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .modifier(CardStyle(tint: nil, radius: 10))
        .background(Color.canvas, in: RoundedRectangle(cornerRadius: 10))
        .fixedSize()
    }
}
