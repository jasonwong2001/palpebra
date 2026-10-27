import Foundation

/// Time window shown by the analysis view.
package enum AnalysisRange: Int, CaseIterable, Identifiable, Sendable {
    case week = 7
    case days28 = 28
    case days90 = 90
    case year = 365
    case all = 0
    package var id: Int { rawValue }

    package var label: String {
        switch self {
        case .week: return "Last 7 days"
        case .days28: return "Last 28 days"
        case .days90: return "Last 90 days"
        case .year: return "Last 12 months"
        case .all: return "All time"
        }
    }
}

/// Calendar grouping shown by the analysis view.
package enum AnalysisGranularity: String, CaseIterable, Identifiable, Sendable {
    case daily, weekly, monthly
    package var id: String { rawValue }

    package var label: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }
}
