import Foundation
import PalpebraCore
import Testing

struct NotificationOutcomeTests {
    @Test func notificationPermissionWarningsMatchDeliveryAvailability() {
        for permission in [NotificationPermission.notDetermined, .denied, .unavailable] {
            #expect(!permission.canDeliver)
            #expect(permission.warning != nil)
        }
        #expect(NotificationPermission.authorized.canDeliver)
        #expect(NotificationPermission.authorized.warning == nil)
        #expect(!NotificationPermission.unknown.canDeliver)
    }

    @Test func undeliveredNotificationCannotCompleteRestOrResetFatigue() throws {
        let outcome = try #require(BreakFinishReason.notificationOutcome(delivered: false))
        #expect(outcome.rawValue == "ignored")
        var settings = AppSettings()
        settings.usageThresholdMinutes = 5
        var now = TestDates.date(day: 25)
        var core = FatigueCore(now: now)
        while !core.breakRunning {
            now = now.addingTimeInterval(5)
            _ = core.step(now: now, signals: .init(inputIdleSeconds: 0), settings: settings)
        }
        core.completeBreak(reason: outcome, at: now)
        #expect(core.fatigue == 100)
        #expect(!core.breakRunning)
        let next = core.step(now: now.addingTimeInterval(5), signals: .init(inputIdleSeconds: 0), settings: settings)
        #expect(!next.contains(.thresholdReached))

        var history = UsageHistory()
        let calendar = TestDates.calendar
        history.recordBreakStart(on: now, calendar: calendar)
        history.recordBreakFinish(reason: outcome, on: now, calendar: calendar)
        let summary = BreakSummary(records: history.days)
        #expect(summary.completed == 0)
        #expect(summary.ignored == 1)
        #expect(summary.compliance == 0)
        let data = try JSONEncoder().encode(history.days)
        #expect(try JSONDecoder().decode([DayRecord].self, from: data) == history.days)
        #expect(BreakFinishReason.notificationOutcome(delivered: true) == nil)
    }
}
