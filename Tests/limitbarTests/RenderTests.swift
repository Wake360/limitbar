import Testing
import SwiftUI
import AppKit
@testable import limitbar

@MainActor private func writePNG<V: View>(_ view: V, scheme: ColorScheme, name: String) -> NSImage? {
    let framed = view
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, scheme)
    let renderer = ImageRenderer(content: framed)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("limitbar-render")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? png.write(to: directory.appendingPathComponent(name))
    return image
}

private func scenarioFetcher(now: Date) -> Fetcher {
    { provider in
        switch provider {
        case .claude:
            Snapshot(provider: .claude, plan: "Max", windows: [
                UsageWindow(label: "5-hour", usedPercent: 92, resetsAt: now.addingTimeInterval(95 * 60), kind: .fiveHour),
                UsageWindow(label: "Weekly", usedPercent: 17, resetsAt: now.addingTimeInterval(3 * 86400), kind: .weekly)
            ], fetchedAt: now)
        case .grok:
            Snapshot(provider: .grok, plan: "", windows: [
                UsageWindow(label: "Weekly", usedPercent: 67, resetsAt: now.addingTimeInterval(4 * 86400), kind: .weekly)
            ], fetchedAt: now)
        case .codex:
            Snapshot(provider: .codex, plan: "Plus", windows: [
                UsageWindow(label: "5-hour", usedPercent: 0, resetsAt: nil, kind: .fiveHour),
                UsageWindow(label: "Weekly", usedPercent: 0, resetsAt: nil, kind: .weekly)
            ], fetchedAt: now)
        case .gemini:
            Snapshot(provider: .gemini, plan: "", windows: [
                UsageWindow(label: "Gemini 3 Pro", usedPercent: 2, resetsAt: now.addingTimeInterval(3600), kind: .daily)
            ], fetchedAt: now)
        }
    }
}

@MainActor @Test func renderPopover() async {
    let now = Date()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = Store(fetcher: scenarioFetcher(now: now), fileURL: directory.appendingPathComponent("snapshots.json"), historyURL: directory.appendingPathComponent("history.jsonl"))
    await store.refresh()
    #expect(writePNG(PopoverView(store: store), scheme: .light, name: "popover-light.png") != nil)
    #expect(writePNG(PopoverView(store: store), scheme: .dark, name: "popover-dark.png") != nil)
}

@MainActor @Test func renderDashboard() async throws {
    let now = Date()
    let reset = now.addingTimeInterval(95 * 60)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let claudeRoot = directory.appendingPathComponent("projects")
    let project = claudeRoot.appendingPathComponent("-Users-test-dev")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

    let stamp = ISO8601DateFormatter()
    stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var lines: [String] = []
    func add(_ session: String, _ cwd: String, _ branch: String, minutesAgo: Double, tokens: Int, agent: String? = nil) {
        let at = stamp.string(from: now.addingTimeInterval(-minutesAgo * 60))
        let agentField = agent.map { "\"agentId\":\"\($0)\"," } ?? ""
        lines.append("{\"timestamp\":\"\(at)\",\"sessionId\":\"\(session)\",\"cwd\":\"/Users/test/dev/\(cwd)\",\"gitBranch\":\"\(branch)\",\(agentField)\"requestId\":\"req-\(lines.count)\",\"message\":{\"id\":\"msg-\(lines.count)\",\"usage\":{\"input_tokens\":0,\"output_tokens\":\(tokens)}}}")
    }
    for i in 0..<14 { add("s-waldean", "waldean", "agent-baseline", minutesAgo: 149 - Double(i) * 44 / 13, tokens: 400, agent: "a\(i % 4)") }
    for i in 0..<10 { add("s-limitbar", "limitbar", "main", minutesAgo: 195 - Double(i) * 160 / 9, tokens: 250) }
    for i in 0..<3 { add("s-lifeos", "LifeOS", "vault", minutesAgo: 73 - Double(i) * 9, tokens: 200) }
    add("s-a", "dotfiles", "main", minutesAgo: 200, tokens: 200)
    add("s-b", "notes", "main", minutesAgo: 185, tokens: 200)
    add("s-c", "scratch", "main", minutesAgo: 170, tokens: 100)
    try Data(lines.joined(separator: "\n").utf8).write(to: project.appendingPathComponent("session.jsonl"))

    let historyURL = directory.appendingPathComponent("history.jsonl")
    let history = History(url: historyURL)
    for (minutesAgo, percent) in [(200.0, 2.0), (175, 5), (150, 10), (135, 30), (120, 52), (105, 75), (80, 80), (55, 86), (30, 90), (10, 92)] {
        history.append(Snapshot(provider: .claude, plan: "Max", windows: [
            UsageWindow(label: "5-hour", usedPercent: percent, resetsAt: reset, kind: .fiveHour),
            UsageWindow(label: "Weekly", usedPercent: 17, resetsAt: now.addingTimeInterval(3 * 86400), kind: .weekly)
        ], fetchedAt: now.addingTimeInterval(-minutesAgo * 60)))
    }

    let store = Store(fetcher: scenarioFetcher(now: now), fileURL: directory.appendingPathComponent("snapshots.json"), historyURL: historyURL)
    await store.refresh()
    let codexRoot = directory.appendingPathComponent("codex")
    let probe = DashboardDetail(store: store, provider: .claude, now: now, claudeRoot: claudeRoot, codexRoot: codexRoot)
    let window = try #require(probe.window)
    let data = DrainData.load(key: probe.key, provider: .claude, window: window, history: store.history, claudeRoot: claudeRoot, codexRoot: codexRoot, now: now)
    #expect(data.drain?.sessions.map(\.name) == ["waldean", "limitbar", "LifeOS", "Other"])
    let dashboard = HStack(spacing: 0) {
        DashboardSidebar(store: store, now: now, selection: .constant(.claude))
            .frame(width: 236)
            .background(.background.secondary)
        Divider()
        DashboardDetail(store: store, provider: .claude, now: now, claudeRoot: claudeRoot, codexRoot: codexRoot, data: data)
            .frame(maxHeight: .infinity, alignment: .top)
    }
    .frame(width: 1180, height: 900)
    #expect(writePNG(dashboard, scheme: .light, name: "dashboard-light.png") != nil)
    #expect(writePNG(dashboard, scheme: .dark, name: "dashboard-dark.png") != nil)
}
