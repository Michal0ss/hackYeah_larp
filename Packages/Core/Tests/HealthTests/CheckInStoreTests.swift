import XCTest
import Contracts
@testable import Health

final class CheckInStoreTests: XCTestCase {
    private var calendar = Calendar(identifier: .gregorian)
    private lazy var now: Date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 9))!
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("forma-checkin-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private var file: URL { dir.appendingPathComponent("checkins.json") }

    private func makeStore() -> CheckInStore {
        let fixedNow = now
        return CheckInStore(fileURL: file, calendar: calendar, now: { fixedNow })
    }

    private func day(_ ago: Int, hour: Int = 9) -> Date {
        let base = calendar.date(byAdding: .day, value: -ago, to: now)!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base)!
    }

    func testEmptyWhenNothingSaved() async {
        let result = await makeStore().checkIns(days: 7)
        XCTAssertTrue(result.isEmpty)
    }

    func testSavedCheckInComesBack() async throws {
        let store = makeStore()
        try await store.save(CheckIn(date: day(0), mood: 4, stress: 2, energy: 5, note: "Dobrze spałam"))
        let result = await store.checkIns(days: 7)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].mood, 4)
        XCTAssertEqual(result[0].note, "Dobrze spałam")
    }

    func testNewestFirst() async throws {
        let store = makeStore()
        try await store.save(CheckIn(date: day(2), mood: 3, stress: 3, energy: 3))
        try await store.save(CheckIn(date: day(0), mood: 4, stress: 2, energy: 4))
        try await store.save(CheckIn(date: day(1), mood: 2, stress: 4, energy: 2))
        let result = await store.checkIns(days: 7)
        XCTAssertEqual(result.map(\.mood), [4, 2, 3])
    }

    func testSameDayReplacesEarlierCheckIn() async throws {
        let store = makeStore()
        try await store.save(CheckIn(date: day(0, hour: 7), mood: 2, stress: 5, energy: 1))
        try await store.save(CheckIn(date: day(0, hour: 18), mood: 4, stress: 2, energy: 4))
        let result = await store.checkIns(days: 7)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].mood, 4)
    }

    func testDaysWindowIncludesTodayAndExcludesOlder() async throws {
        let store = makeStore()
        for ago in [0, 1, 2, 6, 7, 10] {
            try await store.save(CheckIn(date: day(ago), mood: 3, stress: 3, energy: 3))
        }
        let three = await store.checkIns(days: 3)
        let seven = await store.checkIns(days: 7)
        let none = await store.checkIns(days: 0)
        XCTAssertEqual(three.count, 3)
        XCTAssertEqual(seven.count, 4)
        XCTAssertTrue(none.isEmpty)
    }

    func testValuesAreClampedAndBlankNoteDropped() async throws {
        let store = makeStore()
        let stored = try await store.save(CheckIn(date: day(0), mood: 9, stress: 0, energy: -3, note: "   \n"))
        XCTAssertEqual([stored.mood, stored.stress, stored.energy], [5, 1, 1])
        XCTAssertNil(stored.note)
    }

    func testPersistsAcrossInstances() async throws {
        let first = makeStore()
        try await first.save(CheckIn(date: day(0), mood: 4, stress: 2, energy: 3, note: "ok"))
        let second = makeStore()
        let result = await second.checkIns(days: 7)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].note, "ok")
    }

    func testCorruptFileGivesEmptyHistoryAndKeepsCopy() async throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file)
        let store = makeStore()
        let empty = await store.checkIns(days: 7)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("checkins.corrupt.json").path))
        // The store keeps working after the recovery.
        try await store.save(CheckIn(date: day(0), mood: 3, stress: 3, energy: 3))
        let afterSave = await store.checkIns(days: 7)
        XCTAssertEqual(afterSave.count, 1)
    }

    func testRemoveAllWipesHistoryAndFile() async throws {
        let store = makeStore()
        try await store.save(CheckIn(date: day(0), mood: 3, stress: 3, energy: 3))
        try await store.removeAll()
        let result = await store.checkIns(days: 7)
        XCTAssertTrue(result.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let reopened = await makeStore().checkIns(days: 7)
        XCTAssertTrue(reopened.isEmpty)
    }

    func testHistoryIsCapped() async throws {
        let store = makeStore()
        for ago in 0..<(CheckInStore.maxEntries + 5) {
            try await store.save(CheckIn(date: day(ago), mood: 3, stress: 3, energy: 3))
        }
        let all = await store.checkIns(days: 1000)
        XCTAssertEqual(all.count, CheckInStore.maxEntries)
        XCTAssertEqual(all.first?.date, day(0))
    }

    func testWorksThroughTheProtocol() async throws {
        let store = makeStore()
        try await store.save(CheckIn(date: day(0), mood: 4, stress: 2, energy: 4))
        let provider: CheckInProviding = store
        let result = await provider.checkIns(days: 1)
        XCTAssertEqual(result.count, 1)
    }
}
