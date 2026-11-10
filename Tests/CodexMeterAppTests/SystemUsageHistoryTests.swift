import Foundation
import Testing
@testable import CodexMeterApp
import CodexMeterCore

@MainActor struct SystemUsageHistoryTests {
    private let end = Date(timeIntervalSince1970: 1_800_000_000)

    private func sample(_ seconds: TimeInterval, _ value: Double?) -> SystemMetricsSnapshot {
        SystemMetricsSnapshot(sampledAt: end.addingTimeInterval(seconds), cpuUsagePercent: value)
    }

    @Test func fixedAxisSurvivesAdvancingHistoryWithoutChangingPointTimes() {
        let history = [sample(-120, 10), sample(-60, 30), sample(0, 50)]
        let first = SystemUsageHistoryData(history: history, value: { $0.cpuUsagePercent })
        let next = SystemUsageHistoryData(history: history + [sample(2, 70)], value: { $0.cpuUsagePercent })

        #expect(SystemUsageHistoryData.axisValues == [-120, -60, 0])
        #expect(first.points.map(\.secondsFromEnd) == [-120, -60, 0])
        #expect(next.points.map(\.secondsFromEnd) == [-62, -2, 0])
        #expect(next.points.map(\.time) == history.dropFirst().map(\.sampledAt) + [end.addingTimeInterval(2)])
        #expect(next.points.allSatisfy { (-120...0).contains($0.secondsFromEnd) })
    }

    @Test func invalidReadingsAndLongGapsDoNotConnectHistorySegments() {
        let history = [sample(-122, 1), sample(-120, 0), sample(-118, nil), sample(-116, 10),
                       sample(-114, .nan), sample(-112, .infinity), sample(-110, -1), sample(-108, 101),
                       sample(-106, 100), sample(-94, 50), sample(-92, 60), sample(0, 70)]
        let data = SystemUsageHistoryData(history: history, value: { $0.cpuUsagePercent })

        #expect(data.points.map(\.value) == [0, 10, 100, 50, 60, 70])
        #expect(data.points[0].segment != data.points[1].segment)
        #expect(data.points[1].segment != data.points[2].segment)
        #expect(data.points[2].segment != data.points[3].segment)
        #expect(data.points[3].segment == data.points[4].segment)
        #expect(data.points[4].segment != data.points[5].segment)
    }

    @Test func chartProjectionKeepsAtMostTheLatestSixtyOneScalarPoints() {
        let history = (0..<10_000).map { sample(Double($0 - 9_999) / 100, Double($0 % 101)) }
        let data = SystemUsageHistoryData(history: history, value: { $0.cpuUsagePercent })

        #expect(data.points.count == 61)
        #expect(data.points.first?.time == history[9_939].sampledAt)
        #expect(data.points.last?.time == end)
        #expect(data.points.map(\.value) == history.suffix(61).compactMap(\.cpuUsagePercent))
    }

    @Test func emptyAndUnavailableHistoriesRemainDistinct() {
        let empty = SystemUsageHistoryData(history: [], value: { $0.cpuUsagePercent })
        let unavailable = SystemUsageHistoryData(history: [sample(0, nil)], value: { $0.cpuUsagePercent })

        #expect(!empty.hasHistory)
        #expect(empty.points.isEmpty)
        #expect(unavailable.hasHistory)
        #expect(unavailable.points.isEmpty)
        #expect(empty.nearest(to: end) == nil)
        #expect(unavailable.nearest(to: nil) == nil)
    }

    @Test func selectionStaysOnTheActualSampleAsTheRelativeAxisAdvances() {
        let selection = SystemUsageHistorySelection()
        let original = SystemUsageHistoryData(history: [sample(-60, 20), sample(-58, 30), sample(0, 40)],
                                              value: { $0.cpuUsagePercent })
        let originalBinding = selection.relativeSeconds(in: original)
        originalBinding.wrappedValue = -60
        #expect(selection.date == end.addingTimeInterval(-60))

        let data = SystemUsageHistoryData(history: [sample(-60, 20), sample(-58, 30), sample(2, 40)],
                                          value: { $0.cpuUsagePercent })
        let advancedBinding = selection.relativeSeconds(in: data)
        #expect(advancedBinding.wrappedValue == -62)
        #expect(selection.selectedPoint(in: data)?.time == end.addingTimeInterval(-60))
        #expect(data.nearest(to: selection.date)?.time == end.addingTimeInterval(-60))
        #expect(data.nearest(to: end.addingTimeInterval(-57))?.value == 30)

        advancedBinding.wrappedValue = nil
        #expect(selection.date == nil)
    }

    @Test func expiredSelectionDoesNotJumpToAnotherSample() {
        let data = SystemUsageHistoryData(history: [sample(-120, 10), sample(-60, 30), sample(0, 50)],
                                          value: { $0.cpuUsagePercent })
        #expect(data.nearest(to: end.addingTimeInterval(-120))?.value == 10)
        let advanced = SystemUsageHistoryData(history: [sample(-60, 30), sample(0, 50), sample(2, 70)],
                                              value: { $0.cpuUsagePercent })
        #expect(advanced.nearest(to: end.addingTimeInterval(-120)) == nil)
        #expect(advanced.nearest(to: end.addingTimeInterval(-121)) == nil)
        #expect(advanced.nearest(to: end.addingTimeInterval(3)) == nil)
        #expect(advanced.nearest(to: end.addingTimeInterval(-59))?.value == 30)
    }

    @Test func relativeSelectionRejectsExpiredFutureAndInvalidCoordinates() {
        let selection = SystemUsageHistorySelection()
        let original = SystemUsageHistoryData(history: [sample(-120, 10), sample(0, 50)],
                                              value: { $0.cpuUsagePercent })
        let advanced = SystemUsageHistoryData(history: [sample(0, 50), sample(2, 70)],
                                              value: { $0.cpuUsagePercent })
        let binding = selection.relativeSeconds(in: original)
        binding.wrappedValue = -120
        #expect(binding.wrappedValue == -120)
        #expect(selection.relativeSeconds(in: advanced).wrappedValue == nil)
        selection.reconcile(with: advanced)
        #expect(selection.date == nil)
        for invalid in [-121.0, 1, .nan, .infinity, -.infinity, .greatestFiniteMagnitude, -.greatestFiniteMagnitude] {
            binding.wrappedValue = invalid
            #expect(selection.date == nil)
            #expect(binding.wrappedValue == nil)
        }
        binding.wrappedValue = 0
        #expect(selection.date == end)
        binding.wrappedValue = nil
        #expect(selection.date == nil)
    }

    @Test func fractionalInputSnapsToTheSampleAndExpiresWithThatSample() {
        let selection = SystemUsageHistorySelection()
        let original = SystemUsageHistoryData(history: [sample(-120, 10), sample(-118, 30), sample(0, 50)],
                                              value: { $0.cpuUsagePercent })
        selection.relativeSeconds(in: original).wrappedValue = -119.5
        #expect(selection.date == end.addingTimeInterval(-120))
        #expect(selection.selectedPoint(in: original)?.value == 10)

        let advanced = SystemUsageHistoryData(history: [sample(-118, 30), sample(0, 50), sample(1, 70)],
                                              value: { $0.cpuUsagePercent })
        #expect(selection.relativeSeconds(in: advanced).wrappedValue == nil)
        #expect(selection.selectedPoint(in: advanced) == nil)
        selection.reconcile(with: advanced)
        #expect(selection.date == nil)

        selection.relativeSeconds(in: advanced).wrappedValue = -118.5
        #expect(selection.selectedPoint(in: advanced)?.time == end.addingTimeInterval(-118))
    }
}
