import Foundation
import Observation
import Contracts
import Insights

/// Loads what the Postępy screen shows from the app services and prepares it with `ProgressReport`.
///
/// Simulated history ("Anna") is used only in demo mode, that is while recovery itself is simulated (no Apple Health
/// data on the phone). With real Health data, a missing technique history or check-in history stays empty and the
/// screen says what to do. Every simulated section is flagged, so the UI can show "Dane przykładowe" next to it.
@Observable
@MainActor
final class ProgressModel {
    private(set) var report = ProgressReport(technique: nil, recovery: [], mood: [], trendSentence: nil)
    private(set) var techniqueSimulated = false
    private(set) var recoverySimulated = false
    private(set) var moodSimulated = false
    /// What the technique chart draws from (analyses, or the sample ones in demo mode).
    private(set) var techniqueResults: [TechniqueResult] = []
    /// Every logged set with its weight and reps, for the load chart.
    private(set) var loads: [LoggedLoad] = []
    private(set) var care: CareAssessment?
    private(set) var careSimulated = false
    private(set) var loaded = false

    var isFullyEmpty: Bool { loaded && report.isEmpty }

    /// Simulation flags of the sections that have data.
    private var presentFlags: [Bool] {
        var flags: [Bool] = []
        if report.technique != nil { flags.append(techniqueSimulated) }
        return flags
    }

    /// Some sections show simulated data and others real data: then every card carries its own badge.
    var isMixed: Bool { Set(presentFlags).count > 1 }
    /// One badge in the header when all sections with data are simulated.
    var showsHeaderBadge: Bool { !isMixed && presentFlags.contains(true) }
    var anySimulated: Bool { presentFlags.contains(true) }

    func load(services: AppServices, now: Date = Date()) async {
        let snapshots = await services.recovery.snapshots(days: 14)
        let storedCheckIns = await services.checkIns.checkIns(days: 14)
        let storedResults = await services.technique.results(limit: 50)
        let loggedSets = services.trainingLog.sets
        let activitySets = loggedSets.map { LoggedActivity(exerciseId: $0.exerciseId, date: $0.date) }
        loads = loggedSets.map { LoggedLoad(exerciseId: $0.exerciseId, date: $0.date, weightKg: $0.weightKg, reps: $0.reps) }

        let demo = snapshots.isEmpty || snapshots.contains(where: \.isSimulated)
        let realResults = storedResults.filter { !$0.isSimulated }

        var results = realResults
        techniqueSimulated = false
        if results.isEmpty, demo {
            results = ProgressSample.techniqueResults(now: now)
            techniqueSimulated = true
        }
        var checkIns = storedCheckIns
        moodSimulated = false
        if checkIns.isEmpty, demo {
            checkIns = ProgressSample.checkIns(now: now)
            moodSimulated = true
        }
        recoverySimulated = snapshots.contains(where: \.isSimulated)
        techniqueResults = results

        report = ProgressReport.make(results: results, snapshots: snapshots, checkIns: checkIns,
                                     activitySets: activitySets, now: now)
        care = CarePathway().assess(snapshots: snapshots, checkIns: checkIns, techniqueResults: results, now: now)
        careSimulated = techniqueSimulated || moodSimulated || recoverySimulated
        loaded = true
    }
}
