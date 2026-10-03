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

    func testEmptyHealthFallsBackToSimulatedSampleData() async {
        let result = await service(FakeSource()).snapshots(days: 5)
        XCTAssertEqual(result.count, 5)
        XCTAssertTrue(result.allSatisfy(\.isSimulated))
    }

    func testUnavailableHealthFallsBackToSample() async {
        let result = await service(FakeSource(isAvailable: false, samplesResult: .success(realToday()))).snapshots(days: 3)
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.allSatisfy(\.isSimulated))
    }

    func testSourceErrorFallsBackToSample() async {
        let result = await service(FakeSource(samplesResult: .failure(Boom()))).snapshots(days: 3)
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.allSatisfy(\.isSimulated))
    }

    func testFallbackCanBeSwitchedOff() async {
        let result = await service(FakeSource(), fallback: false).snapshots(days: 7)
        XCTAssertTrue(result.isEmpty)
    }

    func testDaysZeroIsEmpty() async {
        let result = await service(FakeSource()).snapshots(days: 0)
        XCTAssertTrue(result.isEmpty)
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
