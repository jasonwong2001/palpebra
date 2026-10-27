import Combine
import Foundation
import PalpebraCore

/// Observable adapter for usage history in the app's Application Support directory.
@MainActor
final class UsageStore: ObservableObject {
    /// Each save rewrites the whole history, so accumulating usage is saved at most this often.
    /// Quitting, locking and sleeping save sooner.
    private static let saveInterval: TimeInterval = 120

    @Published private var history: UsageHistory

    private let fileURL: URL
    private var dirty = false
    private var lastSave = Date.distantPast
    private var canSave = true

    init(directory: URL, filename: String = "usage.json") {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            AppLog.history.error("Could not create the history directory: \(error)")
        }
        fileURL = directory.appendingPathComponent(filename)
        do {
            history = try UsageHistory(contentsOf: fileURL, now: Date(), calendar: .current)
            if let recovery = history.recovery {
                AppLog.history.error(
                    "Recovered history; skipped records: \(recovery.skippedRecords ?? -1). Original saved at \(recovery.backupURL.path, privacy: .public)"
                )
            }
            if !history.unmigratedDayKeys.isEmpty {
                AppLog.history.error(
                    "Could not migrate \(self.history.unmigratedDayKeys.count) day keys; records preserved.")
            }
        } catch {
            history = UsageHistory()
            canSave = false
            AppLog.history.error("History load failed; saving disabled to preserve the original: \(error)")
        }
    }

    func recordActive(seconds: Double, fatigue: Double, on date: Date = Date()) {
        history.recordActive(seconds: seconds, fatigue: fatigue, on: date, calendar: .current)
        scheduleSave()
    }

    func recordFatigued(seconds: Double, on date: Date = Date()) {
        history.recordFatigued(seconds: seconds, on: date, calendar: .current)
        scheduleSave()
    }

    func recordBreakStart(on date: Date = Date()) {
        history.recordBreakStart(on: date, calendar: .current)
        scheduleSave()
    }

    func recordBreakFinish(reason: BreakFinishReason, on date: Date = Date()) {
        history.recordBreakFinish(reason: reason, on: date, calendar: .current)
        scheduleSave()
    }

    func recordReminder(on date: Date = Date()) {
        history.recordReminder(on: date, calendar: .current)
        scheduleSave()
    }

    func screenTimeNotified(primary: Bool, on date: Date = Date()) -> Bool {
        history.screenTimeNotified(primary: primary, on: date, calendar: .current)
    }

    func setScreenTimeNotified(primary: Bool, on date: Date = Date()) {
        history.setScreenTimeNotified(primary: primary, on: date, calendar: .current)
        scheduleSave()
    }

    // MARK: queries

    func activeSeconds(on date: Date = Date()) -> Double {
        history.activeSeconds(on: date, calendar: .current)
    }

    func buckets(last daysBack: Int, by granularity: AnalysisGranularity) -> [Bucket] {
        history.buckets(last: daysBack, by: granularity, now: Date(), calendar: .current)
    }

    func dailyAverage(last daysBack: Int) -> DailyAverage {
        history.dailyAverage(last: daysBack, now: Date(), calendar: .current)
    }

    func breakSummary(last daysBack: Int) -> BreakSummary {
        BreakSummary(records: history.records(last: daysBack, now: Date(), calendar: .current))
    }

    func csv() -> String { history.csv() }

    // MARK: persistence

    func clear() throws {
        guard canSave else { throw ClearError.savingDisabled }
        try history.clear(savedTo: fileURL)
        dirty = false
        lastSave = Date()
    }

    private enum ClearError: LocalizedError {
        case savingDisabled

        var errorDescription: String? {
            "Palpebra couldn’t read your history file, so it left it untouched. Quit and reopen Palpebra, then try again."
        }
    }

    private func scheduleSave() {
        dirty = true
        guard Date().timeIntervalSince(lastSave) > Self.saveInterval else { return }
        save()
    }

    func save() {
        guard dirty, canSave else { return }
        lastSave = Date()
        do {
            try history.save(to: fileURL)
            dirty = false
        } catch {
            AppLog.history.error("Could not save history: \(error)")
        }
    }
}
