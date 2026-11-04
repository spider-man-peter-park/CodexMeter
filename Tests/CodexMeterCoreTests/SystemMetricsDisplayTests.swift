import Foundation
import Testing
@testable import CodexMeterCore

struct SystemMetricsDisplayTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let systemIDs: [MenuBarMetric] = [.cpu, .gpu, .ram, .network]

    private var snapshot: SystemMetricsSnapshot {
        SystemMetricsSnapshot(sampledAt: now, cpuUsagePercent: 27.4, gpuUsagePercent: 8.8,
            memoryUsedBytes: 12_000_000_000, memoryTotalBytes: 24_000_000_000,
            networkUploadBytesPerSecond: 1_500, networkDownloadBytesPerSecond: 2_300_000)
    }

    private var options: DisplayOptions {
        DisplayOptions(showFiveHour: false, showWeekly: false, showTPS: false, showTodayTokens: false)
    }

    @Test func independentItemsUseLocalReadingsEvenWhenQuotaIsStale() {
        let items = MenuBarFormatter.items(quota: nil, sample: nil, options: options, now: now,
            stale: true, systemMetrics: snapshot)
        #expect(items.map(\.metric) == systemIDs)
        #expect(items.map(\.title) == ["CPU 27%", "GPU 9%", "RAM 50%", "↑ 1.5 KB/s ↓ 2.3 MB/s"])
        #expect(items.map(\.symbolName) == ["cpu", "display", "memorychip", nil])
        #expect(items.map(\.systemValue) == ["27%", "9%", "50%", nil])
        #expect(items.map(\.systemLabel) == ["CPU", "GPU", "RAM", nil])
        #expect(items.last?.networkUploadValue == "1.5 KB/s")
        #expect(items.last?.networkDownloadValue == "2.3 MB/s")
        #expect(Set(items.map(\.id)).count == 4)
        #expect(items.allSatisfy { !$0.title.contains("*") && $0.metric.isSystemMetric })
    }

    @Test func missingOrStaleReadingsAreUnavailableRatherThanZero() {
        for metrics in [nil, snapshot] {
            let items = MenuBarFormatter.items(quota: nil, sample: nil, options: options,
                now: now.addingTimeInterval(11), systemMetrics: metrics)
            #expect(items.map(\.title) == ["CPU —", "GPU —", "RAM —", "↑ — ↓ —"])
            #expect(items.last?.networkUploadValue == "—")
            #expect(items.last?.networkDownloadValue == "—")
            #expect(items.allSatisfy { $0.accessibilityLabel.contains(L10n.text("System reading unavailable")) })
        }
        let zero = SystemMetricsSnapshot(sampledAt: now, cpuUsagePercent: 0, gpuUsagePercent: nil,
            networkUploadBytesPerSecond: 0, networkDownloadBytesPerSecond: 0)
        let items = MenuBarFormatter.items(quota: nil, sample: nil, options: options, now: now, systemMetrics: zero)
        #expect(items.map(\.title) == ["CPU 0%", "GPU —", "RAM —", "↑ 0 B/s ↓ 0 B/s"])
    }

    @Test func systemVisibilitySurvivesPresetsAndPreferenceRoundTrips() throws {
        var selected = options
        selected.showGPU = false
        selected.showRAM = false
        selected.showNetworkUpload = false
        selected.cpuDisplay = .init(showIcon: false, showLabel: true, labelPosition: .above)
        selected.gpuDisplay = .init(showIcon: true, showLabel: false, labelPosition: .leading)
        selected.ramDisplay = .init(showIcon: false, showLabel: false, labelPosition: .above)
        for preset in DisplayPreset.allCases {
            selected.applyPreset(preset)
            let restored = try JSONDecoder().decode(DisplayOptions.self, from: JSONEncoder().encode(selected))
            #expect(restored == selected)
            #expect(restored.cpuDisplay == SystemMetricDisplayOptions(showIcon: false, showLabel: true, labelPosition: .above))
            #expect(restored.gpuDisplay == SystemMetricDisplayOptions(showIcon: true, showLabel: false, labelPosition: .leading))
            #expect(restored.ramDisplay == SystemMetricDisplayOptions(showIcon: false, showLabel: false, labelPosition: .above))
            let items = MenuBarFormatter.items(quota: nil, sample: nil, options: restored, now: now, systemMetrics: snapshot)
            #expect(items.map(\.metric) == [.cpu, .network])
            #expect(items.last?.networkUploadValue == nil && items.last?.networkDownloadValue == "2.3 MB/s")
        }
        selected.showCPU = false
        selected.showNetworkDownload = false
        #expect(MenuBarFormatter.items(quota: nil, sample: nil, options: selected, now: now).map(\.metric) == [.fallback])
    }

    @Test func existingPreferencesGainSystemMetricsWithoutChangingSavedChoices() throws {
        let migrated = try JSONDecoder().decode(DisplayOptions.self,
            from: Data(#"{"showTPS":false,"showTodayTokens":false,"showWeekly":false,"fontSize":14}"#.utf8))
        #expect(!migrated.showTPS && !migrated.showTodayTokens && !migrated.showWeekly)
        #expect(migrated.fontSize == 14)
        #expect(migrated.showCPU && migrated.showGPU && migrated.showRAM)
        #expect(migrated.showNetworkUpload && migrated.showNetworkDownload)
        #expect(migrated.cpuDisplay == SystemMetricDisplayOptions())
        #expect(migrated.gpuDisplay == SystemMetricDisplayOptions())
        #expect(migrated.ramDisplay == SystemMetricDisplayOptions())
    }

    @Test func nestedDisplayPreferencesDefaultMissingKeysAndRetainIndependentValues() throws {
        let migrated = try JSONDecoder().decode(DisplayOptions.self,
            from: Data(#"{"showNetworkUpload":false,"cpuDisplay":{"showIcon":false},"gpuDisplay":{"showLabel":false,"labelPosition":"above"},"ramDisplay":{"labelPosition":"unknown"}}"#.utf8))
        #expect(!migrated.showNetworkUpload && migrated.showNetworkDownload)
        #expect(migrated.cpuDisplay == SystemMetricDisplayOptions(showIcon: false))
        #expect(migrated.gpuDisplay == SystemMetricDisplayOptions(showLabel: false, labelPosition: .above))
        #expect(migrated.ramDisplay == SystemMetricDisplayOptions())
        let empty = try JSONDecoder().decode(SystemMetricDisplayOptions.self, from: Data("{}".utf8))
        #expect(empty == SystemMetricDisplayOptions())
    }

    @Test func processorLabelsIconsAndPositionsAreIndependentAndKeepAccessibleNames() throws {
        let cases: [(MenuBarMetric, String, String, String, WritableKeyPath<DisplayOptions, SystemMetricDisplayOptions>)] = [
            (.cpu, "CPU", "cpu", "27%", \.cpuDisplay),
            (.gpu, "GPU", "display", "9%", \.gpuDisplay),
            (.ram, "RAM", "memorychip", "50%", \.ramDisplay)
        ]
        for (metric, label, symbol, value, keyPath) in cases {
            for icon in [false, true] {
                for showLabel in [false, true] {
                    for position in MenuBarLabelPosition.allCases {
                        var selected = options
                        selected[keyPath: keyPath] = .init(showIcon: icon, showLabel: showLabel, labelPosition: position)
                        let items = MenuBarFormatter.items(quota: nil, sample: nil, options: selected, now: now, systemMetrics: snapshot)
                        let item = try #require(items.first { $0.metric == metric })
                        #expect(item.title == (showLabel ? label + " " + value : value))
                        #expect(item.symbolName == (icon ? symbol : nil))
                        #expect(item.systemValue == value)
                        #expect(item.systemLabel == (showLabel ? label : nil))
                        #expect(item.accessibilityLabel == label + ", " + value)
                        #expect(item.networkUploadValue == nil && item.networkDownloadValue == nil)
                        for (other, otherLabel, otherSymbol, otherValue, _) in cases where other != metric {
                            let unchanged = try #require(items.first { $0.metric == other })
                            #expect(unchanged.symbolName == otherSymbol)
                            #expect(unchanged.systemLabel == otherLabel)
                            #expect(unchanged.systemValue == otherValue)
                        }
                    }
                }
            }
        }
    }

    @Test func combinedNetworkHasOneStableIdentityForBothOrEitherVisibleDirection() throws {
        for uploadVisible in [false, true] {
            for downloadVisible in [false, true] {
                var selected = options
                selected.showCPU = false
                selected.showGPU = false
                selected.showRAM = false
                selected.showNetworkUpload = uploadVisible
                selected.showNetworkDownload = downloadVisible
                let items = MenuBarFormatter.items(quota: nil, sample: nil, options: selected, now: now, systemMetrics: snapshot)
                if !uploadVisible && !downloadVisible {
                    #expect(items.map(\.metric) == [.fallback])
                    continue
                }
                #expect(items.count == 1)
                let item = try #require(items.first)
                #expect(item.id == .network)
                #expect(item.metric.isSystemMetric)
                #expect(item.symbolName == nil && item.systemValue == nil && item.systemLabel == nil)
                #expect(item.networkUploadValue == (uploadVisible ? "1.5 KB/s" : nil))
                #expect(item.networkDownloadValue == (downloadVisible ? "2.3 MB/s" : nil))
                let expectedTitle = [uploadVisible ? "↑ 1.5 KB/s" : nil, downloadVisible ? "↓ 2.3 MB/s" : nil]
                    .compactMap { $0 }.joined(separator: " ")
                #expect(item.title == expectedTitle)
                #expect(item.accessibilityLabel.contains(L10n.text("Upload")) == uploadVisible)
                #expect(item.accessibilityLabel.contains(L10n.text("Download")) == downloadVisible)
            }
        }
    }

    @Test func missingHiddenLabelReadingRetainsMetricIdentityAndUnavailableValue() throws {
        var selected = options
        selected.cpuDisplay = .init(showIcon: false, showLabel: false, labelPosition: .above)
        let items = MenuBarFormatter.items(quota: nil, sample: nil, options: selected, now: now)
        let cpu = try #require(items.first { $0.metric == .cpu })
        #expect(cpu.title == "—" && cpu.systemValue == "—")
        #expect(cpu.systemLabel == nil && cpu.symbolName == nil)
        #expect(cpu.accessibilityLabel == "CPU, " + L10n.text("System reading unavailable"))
    }

    @Test func formattingHandlesUnitBoundariesAndInvalidReadings() {
        #expect(SystemMetricsFormatter.percent(.nan) == "—")
        #expect(SystemMetricsFormatter.percent(101) == "—")
        #expect(SystemMetricsFormatter.rate(-1) == "—")
        #expect(SystemMetricsFormatter.rate(.infinity) == "—")
        #expect(SystemMetricsFormatter.rate(999_500) == "1.0 MB/s")
        #expect(SystemMetricsFormatter.rate(1_000) == "1.0 KB/s")
        #expect(SystemMetricsFormatter.rate(99_949_000) == "99.9 MB/s")
        #expect(SystemMetricsFormatter.rate(99_999_999) == "100 MB/s")
        #expect(SystemMetricsFormatter.rate(999_499_999) == "999 MB/s")
        #expect(SystemMetricsFormatter.bytes(24_000_000_000) == "24.0 GB")
        #expect(SystemMetricsFormatter.bytes(nil) == "—")
    }

    @Test func hardwareFreshnessUsesItsOwnClockWithoutChangingQuotaCountdowns() {
        let hardwareTime = now.addingTimeInterval(60)
        let quota = QuotaSnapshot(fiveHour: QuotaWindow(usedPercent: 25, windowDurationMins: 300,
            resetsAt: now.addingTimeInterval(3600)), weekly: nil, updatedAt: now, source: .appServer)
        let hardware = SystemMetricsSnapshot(sampledAt: hardwareTime, cpuUsagePercent: 37)
        let items = MenuBarFormatter.items(quota: quota, sample: nil, options: DisplayOptions(), now: now,
            systemMetrics: hardware, systemNow: hardwareTime)
        #expect(items.first(where: { $0.metric == .fiveHour })?.title == "AI 75% 1h0m")
        #expect(items.first(where: { $0.metric == .cpu })?.title == "CPU 37%")
    }
}
