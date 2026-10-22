import SwiftUI

struct DashboardView: View {
    let store: Store
    var claudeRoot = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    var codexRoot = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
    @State private var selection: Provider?

    var body: some View {
        TimelineView(.everyMinute) { context in
            let ordered = Limits.ordered(store.status, now: context.date)
            let current = selection ?? ordered[0]
            NavigationSplitView {
                DashboardSidebar(store: store, now: context.date, selection: Binding(get: { current }, set: { selection = $0 }))
            } detail: {
                ScrollView {
                    DashboardDetail(store: store, provider: current, now: context.date, claudeRoot: claudeRoot, codexRoot: codexRoot)
                        .id(current)
                }
                .background(Color.canvas)
            }
            .frame(minWidth: 900, minHeight: 640)
        }
        .onAppear { NSApp.setActivationPolicy(.regular) }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }
}

struct DashboardSidebar: View {
    let store: Store
    let now: Date
    @Binding var selection: Provider?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PROVIDERS").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.bottom, 4)
            ForEach(Limits.ordered(store.status, now: now), id: \.self) { provider in
                let selected = provider == selection
                Button { selection = provider } label: {
                    ProviderRow(provider: provider, status: store.status[provider] ?? .empty, now: now, style: .sidebar)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 56)
                        .background(selected ? provider.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? provider.accent.opacity(0.35) : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer()
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).frame(height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 10).padding(.top, 12)
        .navigationSplitViewColumnWidth(min: 220, ideal: 236)
        .toolbar(removing: .sidebarToggle)
    }
}

struct DrainData: Sendable {
    let key: String
    let drain: Drain?
    let readings: [(at: Date, percent: Double)]

    static func span(_ kind: WindowKind) -> (length: TimeInterval, step: TimeInterval)? {
        switch kind {
        case .fiveHour: (5 * 3600, 300)
        case .daily: (86400, 900)
        case .weekly: (7 * 86400, 3600)
        case .credits: nil
        }
    }

    static func load(key: String, provider: Provider, window: UsageWindow, history: History, claudeRoot: URL, codexRoot: URL, now: Date) -> DrainData {
        guard let resetsAt = window.resetsAt, let span = span(window.kind) else { return DrainData(key: key, drain: nil, readings: []) }
        let start = resetsAt - span.length
        let readings = History.readings(history.load(provider, since: start), label: window.label, resetsAt: resetsAt)
        switch provider {
        case .claude:
            let events = ClaudeSessions.load(root: claudeRoot, from: start, to: now)
            let drain = Drain.estimated(events, usedPercent: window.usedPercent, start: start, now: now, step: span.step)
            return DrainData(key: key, drain: drain, readings: readings)
        case .codex:
            let minutes = window.kind == .fiveHour ? 300 : 10080
            let points = CodexSessions.load(root: codexRoot, from: start, to: now)
                .filter { $0.windowMinutes == minutes && abs($0.resetsAt.timeIntervalSince(resetsAt)) <= 60 }
            let drain = Drain.measured(points, start: start, now: now, step: span.step)
            let merged = (readings + points.map { (at: $0.at, percent: $0.usedPercent) }).sorted { $0.at < $1.at }
            return DrainData(key: key, drain: drain, readings: merged)
        case .gemini, .grok:
            return DrainData(key: key, drain: nil, readings: readings)
        }
    }
}

struct Countdown: Equatable {
    let caption: String
    let value: String
    let line: String?
}

struct DashboardDetail: View {
    let store: Store
    let provider: Provider
    let now: Date
    let claudeRoot: URL
    let codexRoot: URL
    @State private var selected: String?
    @State private var data: DrainData?
    @State private var showOthers = false
    @Environment(\.colorScheme) private var colorScheme

    init(store: Store, provider: Provider, now: Date, claudeRoot: URL, codexRoot: URL, data: DrainData? = nil) {
        self.store = store
        self.provider = provider
        self.now = now
        self.claudeRoot = claudeRoot
        self.codexRoot = codexRoot
        _data = State(initialValue: data)
    }

    private var status: ProviderStatus { store.status[provider] ?? .empty }

    private var signedOut: Bool {
        if case .loggedOut = status { return true }
        return false
    }

    private var hasToggle: Bool {
        provider != .gemini && status.snapshot?.shortWindow != nil && status.snapshot?.longWindow != nil
    }

    var window: UsageWindow? {
        guard let snapshot = status.snapshot else { return nil }
        if let selected, Self.selectable(provider, snapshot).contains(selected), let picked = snapshot.windows.first(where: { $0.label == selected }) {
            return picked
        }
        if provider == .gemini { return snapshot.highest }
        let picked = Limits.availability(provider, status, now: now)?.window.label
        return [snapshot.shortWindow, snapshot.longWindow].compactMap { $0 }.first { $0.label == picked } ?? snapshot.shortWindow ?? snapshot.longWindow
    }

    nonisolated static func cards(_ provider: Provider, _ snapshot: Snapshot, now: Date) -> [UsageWindow] {
        let current = snapshot.windows.map { Limits.current($0, now: now) }
        guard provider == .gemini else { return current }
        return Array(current.sorted { $0.usedPercent > $1.usedPercent }.prefix(4))
    }

    nonisolated static func selectable(_ provider: Provider, _ snapshot: Snapshot) -> [String] {
        if provider == .gemini { return snapshot.windows.map(\.label) }
        return [snapshot.shortWindow, snapshot.longWindow].compactMap { $0?.label }
    }

    nonisolated static func countdown(_ availability: Availability, windows: [UsageWindow], now: Date) -> Countdown {
        let window = availability.window
        guard window.kind != .credits, let target = availability.backAt, target > now else {
            return Countdown(caption: "Used", value: "\(Int(window.usedPercent.rounded()))%", line: Format.resetText(window, now: now))
        }
        let kind = windows.first { $0.resetsAt == target }?.kind ?? window.kind
        let named = "when the \(Verdict.kindWord(kind)) window resets"
        let lead = availability.hot ? "Back" : "Resets"
        guard target.timeIntervalSince(now) < 86400 else {
            return Countdown(caption: lead, value: Format.day(target), line: named)
        }
        return Countdown(caption: lead + " in", value: Format.duration(target.timeIntervalSince(now)), line: "at \(Format.clock(target)), " + named)
    }

    var key: String {
        let resets = window?.resetsAt.map { "\($0.timeIntervalSince1970)" } ?? ""
        return [provider.rawValue, window?.label ?? "", resets].joined(separator: "|")
    }

    private var taskKey: String {
        key + "|" + (store.lastRefresh.map { "\($0.timeIntervalSince1970)" } ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            if let window, let snapshot = status.snapshot {
                content(window, snapshot: snapshot)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(provider.displayName).font(.system(size: 30, weight: .bold))
                    Text(signedOutLine ?? staleMessage ?? "Loading").font(.system(size: 14)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(EdgeInsets(top: 14, leading: 30, bottom: 28, trailing: 30))
        .background(alignment: .top) { glow }
        .background(Color.canvas)
        .task(id: taskKey) {
            guard let window else { return }
            let (key, provider, history, claudeRoot, codexRoot) = (key, provider, store.history, claudeRoot, codexRoot)
            data = await Task.detached {
                DrainData.load(key: key, provider: provider, window: window, history: history, claudeRoot: claudeRoot, codexRoot: codexRoot, now: Date())
            }.value
        }
    }

    @ViewBuilder private var glow: some View {
        if provider == .claude || provider == .gemini {
            RadialGradient(colors: [provider.accent.opacity(colorScheme == .dark ? 0.16 : 0.12), .clear], center: .top, startRadius: 0, endRadius: 420)
                .frame(height: 360)
                .allowsHitTesting(false)
        }
    }

    private var toolbar: some View {
        let refresh = RefreshStatus.make(store.status, lastRefresh: store.lastRefresh, refreshing: store.refreshing, now: now)
        return HStack(spacing: 6) {
            Spacer(minLength: 0)
            Circle().fill(refresh.fresh ? Color.fresh : Color.secondary).frame(width: 7, height: 7)
            Text(refresh.text).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
            RefreshButton(store: store)
        }
        .padding(.bottom, 12)
    }

    private func content(_ window: UsageWindow, snapshot: Snapshot) -> some View {
        let current = data?.key == key ? data : nil
        let chartable = window.kind != .credits && window.resetsAt != nil
        let reset = window.resetsAt.map { $0 <= now } ?? false
        let drain = reset ? nil : current?.drain
        return VStack(alignment: .leading, spacing: 0) {
                header(window, snapshot: snapshot, drain: drain)
                windowCards(snapshot, selected: window, drain: drain).padding(.top, 24)
                if reset {
                    Text("This window has reset. The next refresh shows the new one.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .padding(.top, 24)
                } else if chartable, let resetsAt = window.resetsAt, let span = DrainData.span(window.kind) {
                    chartCard(window, data: current, start: resetsAt - span.length, end: resetsAt).padding(.top, 24)
                    if let drain = current?.drain, !drain.sessions.isEmpty {
                        sessions(drain, kind: window.kind, start: resetsAt - span.length, end: resetsAt).padding(.top, 16)
                    }
                }
        }
    }

    private func hot(_ window: UsageWindow) -> Bool { !signedOut && window.usedPercent >= Limits.hot }

    private func percent(_ value: Double) -> Int { Int(value.rounded()) }

    private func tint(hot: Bool) -> Color { signedOut ? .secondary : hot ? .warn : provider.accent }

    private func header(_ window: UsageWindow, snapshot: Snapshot, drain: Drain?) -> some View {
        let availability = Limits.availability(provider, status, now: now)
        let hot = availability?.hot == true
        return HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    provider.icon.resizable().scaledToFit().frame(width: 26, height: 26).foregroundStyle(tint(hot: hot))
                    Text(provider.displayName).font(.system(size: 30, weight: .bold))
                        .foregroundStyle(signedOut ? .secondary : .primary)
                    if !snapshot.plan.isEmpty, !signedOut {
                        pill(snapshot.plan, fill: provider.accent.opacity(0.14), text: planText, dot: nil)
                    }
                    if case .loggedOut(_, let hint) = status {
                        pill(ProviderRow.signedOutTitle(hint), fill: Color.neutral.opacity(0.08), text: .secondary, dot: nil)
                    } else if hot {
                        pill("Nearly out", fill: Color.warn.opacity(0.14), text: .warnText, dot: .warn)
                    } else {
                        pill("Plenty left", fill: Color.neutral.opacity(0.08), text: .secondary, dot: nil)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(lines(window, drain: drain), id: \.self) { line in
                        Text((try? AttributedString(markdown: line)) ?? AttributedString(line))
                    }
                }
                .font(.system(size: 14)).monospacedDigit().foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            }
            Spacer(minLength: 0)
            if let availability {
                let countdown = Self.countdown(availability, windows: snapshot.windows, now: now)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(countdown.caption).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    Text(countdown.value)
                        .font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(hot ? Color.warnText : Color.primary)
                    if let line = countdown.line {
                        Text(line).font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var planText: Color {
        switch provider {
        case .claude: .claudeText
        case .gemini, .codex, .grok: .secondary
        }
    }

    private func pill(_ title: String, fill: Color, text: Color, dot: Color?) -> some View {
        HStack(spacing: 5) {
            if let dot { Circle().fill(dot).frame(width: 6, height: 6) }
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(text)
        }
        .padding(.horizontal, 9).frame(height: 22)
        .background(fill, in: Capsule())
    }

    private func windowCards(_ snapshot: Snapshot, selected: UsageWindow, drain: Drain?) -> some View {
        let selectable = Self.selectable(provider, snapshot)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
            ForEach(Self.cards(provider, snapshot, now: now), id: \.label) { card in
                if selectable.contains(card.label) {
                    let isSelected = card.label == selected.label
                    Button { self.selected = card.label } label: { windowCard(card, selected: isSelected) }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                } else {
                    windowCard(card, selected: false)
                }
            }
            if let climb = drain?.climb {
                climbCard(climb, long: (DrainData.span(selected.kind)?.length ?? 0) > 6 * 3600)
            }
        }
    }

    private func windowCard(_ window: UsageWindow, selected: Bool) -> some View {
        let hot = hot(window)
        let tint = tint(hot: hot)
        return HStack(spacing: 14) {
            Ring.View(percent: window.usedPercent, color: tint, size: 56).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(window.label).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                Text("\(percent(window.usedPercent))%")
                    .font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(hot ? Color.warnText : Color.primary)
                if let reset = Format.resetText(window, now: now) {
                    Text(reset).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .modifier(CardStyle(tint: selected ? tint : nil))
        .accessibilityElement(children: .combine)
    }

    private func climbCard(_ climb: Climb, long: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Steepest climb").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Text("+\(percent(climb.rise))%").font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
            Text("in \(Format.duration(climb.to.timeIntervalSince(climb.from))), \(Self.stamp(climb.from, long: long)) to \(Self.stamp(climb.to, long: long))")
                .font(.system(size: 11.5)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .padding(14)
        .modifier(CardStyle(tint: nil))
        .accessibilityElement(children: .combine)
    }

    private var staleMessage: String? {
        guard case .stale(nil, let message) = status else { return nil }
        return message
    }

    private var signedOutLine: String? {
        guard case .loggedOut(let snapshot, let hint) = status else { return nil }
        let product = switch provider {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .gemini: "Antigravity"
        case .grok: "Grok"
        }
        let sentence = hint.prefix(1).uppercased() + hint.dropFirst()
        let shown = snapshot.map { " Showing data from \(Format.clock($0.fetchedAt))." } ?? ""
        let lead = ProviderRow.signedOutTitle(hint) == "Signed out" ? "Signed out of \(product)." : "limitbar can't read the \(product) login yet."
        return "\(lead) \(sentence)\(sentence.hasSuffix(".") ? "" : ".")\(shown)"
    }

    private func used(_ window: UsageWindow) -> String {
        let resets = window.resetsAt.map { ", resets \(Format.when($0, now: now))" } ?? ""
        return "\(window.label): \(percent(Limits.current(window, now: now).usedPercent))% used\(resets)."
    }

    private func lines(_ window: UsageWindow, drain: Drain?) -> [String] {
        var lines: [String] = []
        if let signedOutLine { lines.append(signedOutLine) }
        if let drain, let top = drain.sessions.first(where: { $0.slot == 0 }) {
            lines.append(Self.topLine(top, measured: drain.measured, long: (DrainData.span(window.kind)?.length ?? 0) > 6 * 3600))
        }
        if hasToggle, let snapshot = status.snapshot, let other = self.window == snapshot.longWindow ? snapshot.shortWindow : snapshot.longWindow {
            lines.append(used(other))
        }
        if provider == .claude, let highest = status.snapshot?.highest, highest.label == "Opus weekly" {
            lines.append(used(highest))
        }
        return lines
    }

    static func stamp(_ date: Date, long: Bool) -> String {
        long ? Format.day(date) : Format.clock(date)
    }

    static func topLine(_ top: SessionShare, measured: Bool, long: Bool) -> String {
        let range = "between \(stamp(top.first, long: long)) and \(stamp(top.last, long: long))."
        let share = Int(top.share.rounded())
        if measured { return "\(top.name) used \(share)% of the limit \(range)" }
        if top.detail?.hasSuffix("subagents") == true { return "\(top.name)'s agent run used about \(share)% of the limit \(range)" }
        return "\(top.name) used about \(share)% of the limit \(range)"
    }

    static func activeHeader(start: Date, end: Date) -> String {
        let long = end.timeIntervalSince(start) > 6 * 3600
        return "Active, \(stamp(start, long: long)) to \(stamp(end, long: long))"
    }

    private func cardTitle(_ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(subtitle).font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func chartCard(_ window: UsageWindow, data: DrainData?, start: Date, end: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                cardTitle("What used the \(Verdict.kindWord(window.kind)) window", String(Self.activeHeader(start: start, end: end).dropFirst("Active, ".count)))
                Spacer(minLength: 0)
                HStack(spacing: 14) {
                    ForEach(data?.drain?.sessions ?? [], id: \.id) { session in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(DrainChart.color(slot: session.slot, provider: provider)).frame(width: 8, height: 8)
                            Text(session.name).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
            DrainChart(
                drain: data?.drain,
                readings: data?.readings ?? [],
                start: start,
                resetsAt: end,
                now: now,
                usedPercent: window.usedPercent,
                hot: hot(window),
                provider: provider
            )
            .frame(height: 250)
            .padding(.top, 16)
            notes(data).padding(.top, 12)
        }
        .padding(20)
        .modifier(CardStyle(tint: nil, radius: 16))
    }

    private func sessions(_ drain: Drain, kind: WindowKind, start: Date, end: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle("Sessions", "share of the \(Verdict.kindWord(kind)) limit").padding(.bottom, 8)
            ViewThatFits(in: .horizontal) {
                sessionRows(drain, start: start, end: end).frame(minWidth: 560)
                ScrollView(.horizontal) { sessionRows(drain, start: start, end: end).frame(width: 560) }
            }
            if !drain.measured {
                Text("Estimated from each session's token share. Anthropic doesn't publish the exact weighting.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }
        }
        .padding(20)
        .modifier(CardStyle(tint: nil, radius: 16))
    }

    private func sessionRows(_ drain: Drain, start: Date, end: Date) -> some View {
        VStack(spacing: 0) {
            ForEach(drain.sessions, id: \.id) { session in
                if session.id != drain.sessions.first?.id { Divider() }
                if session.id == "other" {
                    Button { showOthers.toggle() } label: { row(session, drain: drain, start: start, end: end, expandable: true) }
                        .buttonStyle(.plain)
                        .accessibilityValue(showOthers ? "expanded" : "collapsed")
                    if showOthers {
                        ForEach(drain.others, id: \.id) { other in
                            Divider()
                            row(other, drain: drain, start: start, end: end, expandable: false).padding(.leading, 18)
                        }
                    }
                } else {
                    row(session, drain: drain, start: start, end: end, expandable: false)
                }
            }
        }
    }

    private func row(_ session: SessionShare, drain: Drain, start: Date, end: Date, expandable: Bool) -> some View {
        let color = DrainChart.color(slot: session.slot, provider: provider)
        let span = end.timeIntervalSince(start)
        return HStack(spacing: 16) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 9, height: 9)
                Text(session.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                if let detail = session.detail {
                    Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                if expandable {
                    Image(systemName: showOthers ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                }
            }
            .frame(width: 260, alignment: .leading)
            GeometryReader { geo in
                let x = geo.size.width * max(0, session.first.timeIntervalSince(start)) / span
                let width = geo.size.width * max(0, session.last.timeIntervalSince(session.first)) / span
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06)).frame(height: 8)
                    Capsule().fill(color).frame(width: max(8, width), height: 8).offset(x: x)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 14)
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06))
                    Capsule().fill(color).frame(width: 54 * min(max(session.share, 0), 100) / 100)
                }
                .frame(width: 54, height: 6)
                Text(drain.measured ? "\(percent(session.share))%" : "~\(percent(session.share))%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }

    private func notes(_ data: DrainData?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let data, data.readings.isEmpty {
                Text("limitbar saves a reading every refresh. The curve starts with the next one.")
            }
            if provider == .gemini || provider == .grok {
                Text("\(provider == .gemini ? "Antigravity" : "Grok") keeps no local session logs, so limitbar can show when usage rose, not which session caused it.")
            }
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
    }
}

struct CardStyle: ViewModifier {
    let tint: Color?
    var radius: CGFloat = 12
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(tint?.opacity(0.06) ?? .clear, in: RoundedRectangle(cornerRadius: radius))
            .background(Color.card, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(tint?.opacity(0.5) ?? Color.cardBorder))
            .shadow(color: colorScheme == .light ? .black.opacity(0.05) : .clear, radius: 12, y: 4)
    }
}
