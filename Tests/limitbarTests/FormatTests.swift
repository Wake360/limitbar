import Testing
import Foundation
@testable import limitbar

private func avail(_ percent: Double, backAt: Date?) -> Availability {
    Availability(provider: .claude, window: UsageWindow(label: "", usedPercent: percent, resetsAt: backAt, kind: .fiveHour), hot: false, backAt: backAt)
}

@Test func durationFormats() {
    #expect(Format.duration(95 * 60) == "1 h 35 min")
    #expect(Format.duration(12 * 60) == "12 min")
    #expect(Format.duration(11 * 60 + 1) == "12 min")
    #expect(Format.duration(2 * 3600) == "2 h")
    #expect(Format.duration(95 * 60, compact: true) == "1h 35m")
    #expect(Format.duration(0) == "now")
}
@Test func backTextWithinDay() {
    let now = Date()
    #expect(Format.backText(avail(10, backAt: now.addingTimeInterval(95 * 60)), now: now) == "in 1 h 35 min")
    #expect(Format.backText(avail(0, backAt: now.addingTimeInterval(3 * 3600)), now: now) == "in 3 h")
}
@Test func backTextPastResetIsNow() {
    let now = Date()
    #expect(Format.backText(avail(100, backAt: now.addingTimeInterval(-300)), now: now) == "now")
}
@Test func backTextWithoutResetShowsPercent() {
    #expect(Format.backText(avail(95.4, backAt: nil), now: Date()) == "95%")
}
@Test func backTextBeyondDayShowsWeekdayAndClock() {
    let calendar = Calendar.current
    let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 11, minute: 25))!
    let back = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 9))!
    #expect(Format.backText(avail(100, backAt: back), now: now) == "Sun 09:00")
}
@Test func clockFormatsHoursAndMinutes() {
    let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 7, minute: 5))!
    #expect(Format.clock(date) == "07:05")
}
@Test func updatedJustNow() {
    #expect(Format.updatedText(Date().addingTimeInterval(-5), now: Date()) == "updated just now")
}
@Test func updatedMinutes() {
    #expect(Format.updatedText(Date().addingTimeInterval(-130), now: Date()) == "updated 2 min ago")
}
@Test func updatedHours() {
    #expect(Format.updatedText(Date().addingTimeInterval(-7300), now: Date()) == "updated 2 h ago")
}
