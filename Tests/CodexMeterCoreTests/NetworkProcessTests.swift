import Foundation
import Testing
@testable import CodexMeterCore

struct NetworkProcessTests {
    private let header = ",bytes_in,bytes_out,"

    @Test func processRatesUseTwoMonotonicSnapshotsAndPreserveDirections() throws {
        var parser = NettopCSVParser()
        parser.consume(header, uptime: 10)
        parser.consume("Example.app.42,1000,2000,", uptime: 10)
        #expect(parser.snapshot() == nil)
        parser.consume(header, uptime: 11.5)
        parser.consume("Example.app.42,4000,8000,", uptime: 11.5)
        let sample = try #require(parser.snapshot(at: Date(timeIntervalSince1970: 100)))
        #expect(sample.updatedAt == Date(timeIntervalSince1970: 100))
        #expect(sample.processes == [.init(pid: 42, name: "Example.app", uploadBytesPerSecond: 4000, downloadBytesPerSecond: 2000)])
    }

    @Test func csvHandlesQuotedNamesCommasEscapedQuotesAndReorderedColumns() throws {
        #expect(NettopCSVParser.fields("\"Name, with \"\"quotes\"\".9\",3,4,") == ["Name, with \"quotes\".9", "3", "4", ""])
        #expect(NettopCSVParser.fields("\"unterminated,3,4,") == nil)
        var parser = NettopCSVParser()
        for time in [1.0, 2.0] {
            parser.consume(",bytes_out,unused,bytes_in,", uptime: time)
            parser.consume("\"Name, with \"\"quotes\"\".9\",\(Int(time) * 10),x,\(Int(time) * 20),", uptime: time)
        }
        let process = try #require(parser.snapshot()?.processes.first)
        #expect(process.name == "Name, with \"quotes\"")
        #expect(process.uploadBytesPerSecond == 10 && process.downloadBytesPerSecond == 20)
    }

    @Test func newResetRenamedExitedAndInactiveProcessesDoNotInventTraffic() throws {
        var parser = NettopCSVParser()
        parser.consume(header, uptime: 0)
        for pid in 1...6 { parser.consume("Old.\(pid),100,100,", uptime: 0) }
        parser.consume(header, uptime: 1)
        for row in ["New.1,200,200,", "Old.2,99,200,", "Old.3,200,99,", "Old.4,100,100,", "New.7,1000000,1000000,", "Old.6,200,300,"] {
            parser.consume(row, uptime: 1)
        }
        let processes = try #require(parser.snapshot()?.processes)
        #expect(processes.map(\.pid) == [6])
        #expect(processes.first?.uploadBytesPerSecond == 200)
    }

    @Test func invalidRowsAndIntervalsCannotProduceSpikes() {
        for elapsed in [0.0, -1, 0.001, 6, Double.infinity, Double.nan] {
            var parser = NettopCSVParser()
            parser.consume(header, uptime: 10)
            parser.consume("App.5,0,0,", uptime: 10)
            parser.consume(header, uptime: 10 + elapsed)
            parser.consume("App.5,1000000,1000000,", uptime: 10 + elapsed)
            #expect(parser.snapshot() == nil)
        }
        var parser = NettopCSVParser()
        parser.consume(header, uptime: 0)
        parser.consume(header, uptime: 1)
        for row in ["App.bad,1,1,", "App.0,1,1,", ".4,1,1,", "App.4,-1,1,", "App.4,1,not-a-number,", "App.4,1", "connection row"] {
            parser.consume(row, uptime: 1)
        }
        #expect(parser.snapshot()?.processes.isEmpty == true)
    }

    @Test func largeCountersAreRankedByCombinedTrafficAndBoundedToEight() throws {
        var parser = NettopCSVParser()
        let baseline: UInt64 = 1 << 50
        parser.consume(header, uptime: 0)
        for pid in 1...12 { parser.consume("App.\(pid),\(baseline),\(baseline),", uptime: 0) }
        parser.consume(header, uptime: 1)
        for pid in 1...12 {
            parser.consume("App.\(pid),\(baseline + UInt64(pid) * 100),\(baseline + 20),", uptime: 1)
        }
        let processes = try #require(parser.snapshot()?.processes)
        #expect(processes.map(\.pid) == [12, 11, 10, 9, 8, 7, 6, 5])
        #expect(processes.first?.uploadBytesPerSecond == 20)
        #expect(processes.first?.downloadBytesPerSecond == 1200)
    }

    @Test func resetCancelsAnInFlightCaptureAndClearsItsSnapshot() async {
        let monitor = NetworkProcessMonitor()
        #expect(await monitor.snapshot()?.updatedAt == nil)
        await monitor.reset()
        #expect(await monitor.snapshot()?.updatedAt == nil)
        await monitor.reset()
    }
}
