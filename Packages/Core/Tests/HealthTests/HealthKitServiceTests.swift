import XCTest
import Contracts
@testable import Health

private struct FakeSource: HealthSampleSource {
    var isAvailable = true
    var accessResult = true
    var samplesResult: Result<HealthSamples, Error> = .success(HealthSamples())

    func requestAccess() async -> Bool { accessResult }
    func samples(from start: Date, to end: Date) async throws -> HealthSamples { try samplesResult.get() }
}

private struct Boom: Error {}

final class HealthKitServiceTests: XCTestCase {
    private var calendar = Calendar(identifier: .gregorian)
    private lazy var now: Date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 9))!
    private lazy var aggregator = RecoveryAggregator(calendar: calendar)

    private func service(_ source: FakeSource, fallback: Bool = true) -> HealthKitService {
        let fixedNow = now
        return HealthKitService(source: source, aggregator: aggregator, useSampleFallback: fallback, now: { fixedNow })
    }

    private func realToday() -> HealthSamples {
        let wake = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: now)!
        return HealthSamples(
            sleep: [SleepInterval(start: wake.addingTimeInterval(-7 * 3600), end: wake)],
            restingHeartRate: [DatedValue(date: wake, value: 57)],
            hrv: [DatedValue(date: wake.addingTimeInterval(-3600), value: 47)])
    }

    func testRealDataIsReturnedAndNotMarkedSimulated() async {
        let result = await service(FakeSource(samplesResult: .success(realToday()))).snapshots(days: 7)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].sleepMinutes, 420)
        XCTAssertFalse(result[0].isSimulated)
    }

    func testEmptyHealthMeansNoDataAndNeverSampleData() async {
        let result = await service(FakeSource()).snapshots(days: 5)
        XCTAssertTrue(result.isEmpty)
    }

    func testUnavailableHealthFallsBackToSample() async {
        let result = await service(FakeSource(isAvailable: false, samplesResult: .success(realToday()))).snapshots(days: 3)
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.allSatisfy(\.isSimulated))
    }

    func testSourceErrorMeansNoDataAndNeverSampleData() async {
        let s = service(FakeSource(samplesResult: .failure(Boom())))
        let snapshots = await s.snapshots(days: 3)
        let summaries = await s.summaries(days: 3)
        XCTAssertTrue(snapshots.isEmpty)
        XCTAssertTrue(summaries.isEmpty)
    }

    func testFallbackCanBeSwitchedOff() async {
        let result = await service(FakeSource(isAvailable: false), fallback: false).snapshots(days: 7)
        XCTAssertTrue(result.isEmpty)
    }

    func testDaysZeroIsEmpty() async {
        let result = await service(FakeSource()).snapshots(days: 0)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: Summaries for display

    func testSummariesAreRealWhenHealthHasData() async {
        let summaries = await service(FakeSource(samplesResult: .success(realToday()))).summaries(days: 7)
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries[0].sleepMinutes, 420)
        XCTAssertFalse(summaries[0].isSimulated)
    }

    func testSummariesAreEmptyWhenHealthIsEmpty() async {
        let summaries = await service(FakeSource()).summaries(days: 5)
        XCTAssertTrue(summaries.isEmpty)
    }

    func testSummariesFallBackToSimulatedSampleWhenHealthIsUnavailable() async {
        let summaries = await service(FakeSource(isAvailable: false)).summaries(days: 5)
        XCTAssertEqual(summaries.count, 5)
        XCTAssertTrue(summaries.allSatisfy(\.isSimulated))
        XCTAssertEqual(summaries[0].snapshot, SampleData.recovery[0])
    }

    func testClosedGateWithEmptyHealthStillUsesSampleData() async {
        let gate = HealthDataGate()
        gate.allowsRealData = false
        let fixedNow = now
        let s = HealthKitService(source: FakeSource(), aggregator: aggregator, gate: gate, now: { fixedNow })
        let summaries = await s.summaries(days: 4)
        XCTAssertEqual(summaries.count, 4)
        XCTAssertTrue(summaries.allSatisfy(\.isSimulated))
    }

    func testPartialRealDataIsShownAndNeverMixedWithSampleData() async {
        // Only sleep (an iPhone without a watch).
        let wake = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: now)!
        let onlySleep = HealthSamples(sleep: [SleepInterval(start: wake.addingTimeInterval(-6 * 3600), end: wake)])
        let s = service(FakeSource(samplesResult: .success(onlySleep)))
        let summaries = await s.summaries(days: 7)
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries[0].sleepMinutes, 360)
        XCTAssertNil(summaries[0].hrvMs)
        XCTAssertFalse(summaries[0].isSimulated)
        // The rule engine gets no complete day, but also no sample day.
        let snapshots = await s.snapshots(days: 7)
        XCTAssertTrue(snapshots.isEmpty)
    }

    func testClosedGateUsesSampleDataEvenWhenHealthHasData() async {
        let gate = HealthDataGate()
        gate.allowsRealData = false
        let fixedNow = now
        let s = HealthKitService(source: FakeSource(samplesResult: .success(realToday())), aggregator: aggregator,
                                 gate: gate, now: { fixedNow })
        let summaries = await s.summaries(days: 3)
        let snapshots = await s.snapshots(days: 3)
        XCTAssertTrue(summaries.allSatisfy(\.isSimulated))
        XCTAssertTrue(snapshots.allSatisfy(\.isSimulated))
        gate.allowsRealData = true
        let real = await s.summaries(days: 3)
        XCTAssertFalse(real[0].isSimulated)
    }

    func testSummariesWithFallbackOffAreEmptyWithoutData() async {
        let empty = await service(FakeSource(isAvailable: false), fallback: false).summaries(days: 7)
        XCTAssertTrue(empty.isEmpty)
    }

    func testReadReportCountsWhatHealthReturned() async {
        let log = HealthReadLog()
        let fixedNow = now
        var samples = realToday()
        samples.inBedCount = 4
        let s = HealthKitService(source: FakeSource(samplesResult: .success(samples)), aggregator: aggregator,
                                 readLog: log, now: { fixedNow })
        _ = await s.summaries(days: 7)
        let report = try? XCTUnwrap(log.last)
        XCTAssertEqual(report?.sleepSamples, 1)
        XCTAssertEqual(report?.restingHeartRateSamples, 1)
        XCTAssertEqual(report?.hrvSamples, 1)
        XCTAssertEqual(report?.inBedSamples, 4)
        XCTAssertEqual(report?.lookbackDays, 21)
        XCTAssertEqual(report?.foundNothing, false)
        XCTAssertEqual(report?.failed, false)
    }

    func testReadReportSaysHealthWasEmptyOrTheReadFailed() async {
        let log = HealthReadLog()
        let fixedNow = now
        let empty = HealthKitService(source: FakeSource(), aggregator: aggregator, readLog: log, now: { fixedNow })
        _ = await empty.summaries(days: 7)
        XCTAssertEqual(log.last?.foundNothing, true)
        XCTAssertEqual(log.last?.summaryText, "Znaleziono (21 dni): sen 0, tętno spoczynkowe 0, HRV 0.")

        let broken = HealthKitService(source: FakeSource(samplesResult: .failure(Boom())), aggregator: aggregator,
                                      readLog: log, now: { fixedNow })
        _ = await broken.summaries(days: 7)
        XCTAssertEqual(log.last?.failed, true)
        XCTAssertEqual(log.last?.foundNothing, false)
        XCTAssertTrue(log.last?.summaryText.hasPrefix("Odczyt nie powiódł się") == true)
    }

    func testReadReportMentionsInBedOnlySleep() {
        let report = HealthReadReport(lookbackDays: 21, inBedSamples: 9)
        XCTAssertTrue(report.foundNothing)
        XCTAssertEqual(report.summaryText, "Znaleziono (21 dni): sen 0, tętno spoczynkowe 0, HRV 0, tylko „w łóżku” 9.")
    }

    func testClosedGateLeavesTheReadLogUntouched() async {
        let log = HealthReadLog()
        let gate = HealthDataGate()
        gate.allowsRealData = false
        let s = HealthKitService(source: FakeSource(), aggregator: aggregator, gate: gate, readLog: log)
        _ = await s.summaries(days: 3)
        XCTAssertNil(log.last)
    }

    func testRequestAccessForwardsResultAndHandlesUnavailable() async {
        let granted = await service(FakeSource(accessResult: true)).requestAccess()
        let refused = await service(FakeSource(accessResult: false)).requestAccess()
        let unavailable = await service(FakeSource(isAvailable: false, accessResult: true)).requestAccess()
        XCTAssertTrue(granted)
        XCTAssertFalse(refused)
        XCTAssertFalse(unavailable)
    }

    func testWorksThroughTheProtocols() async {
        let s = service(FakeSource(samplesResult: .success(realToday())))
        let recovery: RecoveryProviding = s
        let auth: HealthAuthorizing = s
        let snapshots = await recovery.snapshots(days: 1)
        let access = await auth.requestAccess()
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertTrue(access)
    }
}
