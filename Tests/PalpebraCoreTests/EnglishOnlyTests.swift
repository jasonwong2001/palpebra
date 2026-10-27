import PalpebraCore
import Testing

struct EnglishOnlyTests {
    @Test func labelsAreEnglish() {
        #expect(
            ReminderStyle.allCases.map(\.label) == [
                "Full-screen popup", "Mini popup", "Notification",
            ])
        #expect(
            SkipMode.allCases.map(\.label) == [
                "Skip freely", "Arithmetic challenge", "Cannot skip",
            ])
        #expect(DetectMode.allCases.map(\.label) == ["Smart", "Always on"])
        #expect(
            PopupBackground.allCases.map(\.label) == [
                "Match system", "Light", "Dark", "Default", "Custom image",
            ])
        #expect(
            AnalysisRange.allCases.map(\.label) == [
                "Last 7 days", "Last 28 days", "Last 90 days", "Last 12 months", "All time",
            ])
        #expect(AnalysisGranularity.allCases.map(\.label) == ["Daily", "Weekly", "Monthly"])
    }
}
