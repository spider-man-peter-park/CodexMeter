import Darwin
import Foundation

public struct HUDMockAIState: Equatable, Sendable {
    public var status = "Ready"
    public var task = "Awaiting instruction"
    public var model = "Demo assistant"
    public var tokenUsage = 12_840
    public let isMock = true
    public init() {}
}

public struct HUDActivityEvent: Equatable, Sendable, Identifiable {
    public let id: String
    public let date: Date
    public let title: String
    public let isMock: Bool
    public init(id: String, date: Date, title: String, isMock: Bool) {
        self.id = id; self.date = date; self.title = title; self.isMock = isMock
    }
}

public struct HUDDataSnapshot: Equatable, Sendable {
    public var coreContent: HUDTextContent?
    public var moduleContent: [HUDModule: HUDTextContent] = [:]
    public var date = Date()
    public var deviceName = "Mac"
    public var osVersion = "macOS"
    public var uptime: TimeInterval = 0
    public var cpuUsage: Double?
    public var memoryUsedBytes: UInt64?
    public var memoryTotalBytes: UInt64?
    public var gpuUsage: Double?
    public var uploadBytesPerSecond: Double?
    public var downloadBytesPerSecond: Double?
    public var networkConnected: Bool?
    public var cpuHistory: [Double] = []
    public var uploadHistory: [Double] = []
    public var downloadHistory: [Double] = []
    public var mockAI = HUDMockAIState()
    public var activities: [HUDActivityEvent] = []
    public var isFixture = false
    public init() {}

    public static var preview: Self {
        var value = Self()
        value.date = Date(timeIntervalSince1970: 1_794_436_200)
        value.deviceName = "Mac · Mock"
        value.osVersion = "macOS · Mock"
        value.uptime = 81_240
        value.cpuUsage = 0.23
        value.memoryTotalBytes = 24 * 1_024 * 1_024 * 1_024
        value.memoryUsedBytes = 13 * 1_024 * 1_024 * 1_024
        value.uploadBytesPerSecond = 242_000
        value.downloadBytesPerSecond = 1_840_000
        value.networkConnected = true
        value.cpuHistory = [0.12, 0.15, 0.19, 0.17, 0.31, 0.24, 0.2, 0.23]
        value.uploadHistory = [90_000, 120_000, 95_000, 180_000, 220_000, 200_000, 242_000]
        value.downloadHistory = [520_000, 800_000, 720_000, 1_180_000, 1_900_000, 1_600_000, 1_840_000]
        value.activities = MockHUDDataProvider().activities(now: value.date)
        value.isFixture = true
        return value
    }
}

public struct MockHUDDataProvider: Sendable {
    public init() {}
    public func aiState() -> HUDMockAIState { HUDMockAIState() }
    public func activities(now: Date) -> [HUDActivityEvent] {
        [HUDActivityEvent(id: "mock-projection", date: now.addingTimeInterval(-15), title: "Projection ready", isMock: true),
         HUDActivityEvent(id: "mock-model", date: now.addingTimeInterval(-48), title: "Demo model available", isMock: true),
         HUDActivityEvent(id: "mock-session", date: now.addingTimeInterval(-120), title: "Study session started", isMock: true)]
    }
}

@MainActor
public protocol HUDDataProviding {
    func sample(modules: Set<HUDModule>, now: Date) -> HUDDataSnapshot
    func reset()
}

public extension HUDDataProviding {
    func reset() {}
}

struct HUDCPUCounters: Equatable {
    let user: UInt64
    let system: UInt64
    let idle: UInt64
    let nice: UInt64
    func fraction(since previous: Self) -> Double? {
        guard user >= previous.user, system >= previous.system,
              idle >= previous.idle, nice >= previous.nice else { return nil }
        let busy = Double(user - previous.user) + Double(system - previous.system) + Double(nice - previous.nice)
        let total = busy + Double(idle - previous.idle)
        return total > 0 ? min(1, max(0, busy / total)) : nil
    }
}

struct HUDNetworkCounters: Equatable {
    let received: UInt64
    let sent: UInt64
}

struct HUDNetworkRateAccumulator {
    private var previous: [String: HUDNetworkCounters]?
    private var previousTime: TimeInterval?
    mutating func sample(_ values: [String: HUDNetworkCounters]?, at time: TimeInterval) -> (upload: Double?, download: Double?) {
        let old = previous, oldTime = previousTime
        previous = values; previousTime = values == nil ? nil : time
        guard let values, let old, let oldTime, time.isFinite, oldTime.isFinite,
              time > oldTime, time - oldTime <= 10 else { return (nil, nil) }
        var upload = 0.0, download = 0.0, valid = 0
        for (name, value) in values {
            guard let prior = old[name], value.received >= prior.received, value.sent >= prior.sent else { continue }
            valid += 1
            upload += Double(value.sent - prior.sent)
            download += Double(value.received - prior.received)
        }
        guard valid > 0 || (values.isEmpty && old.isEmpty) else { return (nil, nil) }
        return (upload / (time - oldTime), download / (time - oldTime))
    }
}

@MainActor
public final class NativeHUDDataProvider: HUDDataProviding {
    private var previousCPU: HUDCPUCounters?
    private var network = HUDNetworkRateAccumulator()
    private var cpuHistory: [Double] = []
    private var uploadHistory: [Double] = []
    private var downloadHistory: [Double] = []
    private let mock = MockHUDDataProvider()
    private let historyLimit = 60

    public init() {}

    public func reset() {
        previousCPU = nil; network = HUDNetworkRateAccumulator()
    }

    public func sample(modules: Set<HUDModule>, now: Date = Date()) -> HUDDataSnapshot {
        var value = HUDDataSnapshot()
        value.date = now
        value.deviceName = Host.current().localizedName ?? "Mac"
        let version = ProcessInfo.processInfo.operatingSystemVersion
        value.osVersion = "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        value.uptime = ProcessInfo.processInfo.systemUptime
        if modules.contains(.performance) {
            let counters = Self.readCPU()
            if let counters, let previousCPU { value.cpuUsage = counters.fraction(since: previousCPU) }
            previousCPU = counters
            value.memoryTotalBytes = ProcessInfo.processInfo.physicalMemory
            value.memoryUsedBytes = Self.readMemory(total: value.memoryTotalBytes ?? 0)
            if let cpu = value.cpuUsage { append(cpu, to: &cpuHistory) }
            value.cpuHistory = cpuHistory
        } else { previousCPU = nil }
        if modules.contains(.network) {
            let counters = Self.readNetwork()
            value.networkConnected = counters.map { !$0.isEmpty }
            let rates = network.sample(counters, at: value.uptime)
            value.uploadBytesPerSecond = rates.upload
            value.downloadBytesPerSecond = rates.download
            if let rate = rates.upload { append(rate, to: &uploadHistory) }
            if let rate = rates.download { append(rate, to: &downloadHistory) }
            value.uploadHistory = uploadHistory; value.downloadHistory = downloadHistory
        } else { network = HUDNetworkRateAccumulator() }
        if modules.contains(.ai) { value.mockAI = mock.aiState() }
        if modules.contains(.activity) { value.activities = mock.activities(now: now) }
        return value
    }

    private func append(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > historyLimit { history.removeFirst(history.count - historyLimit) }
    }

    private static func readCPU() -> HUDCPUCounters? {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return HUDCPUCounters(user: UInt64(info.cpu_ticks.0), system: UInt64(info.cpu_ticks.1),
                              idle: UInt64(info.cpu_ticks.2), nice: UInt64(info.cpu_ticks.3))
    }

    private static func readMemory(total: UInt64) -> UInt64? {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        guard result == KERN_SUCCESS, host_page_size(host, &pageSize) == KERN_SUCCESS, total > 0 else { return nil }
        let anonymous = info.internal_page_count > info.purgeable_count ? info.internal_page_count - info.purgeable_count : 0
        let pages = UInt64(info.wire_count) + UInt64(anonymous) + UInt64(info.compressor_page_count)
        let bytes = pages.multipliedReportingOverflow(by: UInt64(pageSize))
        return bytes.overflow ? nil : min(total, bytes.partialValue)
    }

    private static func readNetwork() -> [String: HUDNetworkCounters]? {
        // Route interface messages carry native 64-bit counters; avoid loopback and tunnel double-counting.
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var count = 0
        guard sysctl(&mib, u_int(mib.count), nil, &count, nil, 0) == 0, count > 0 else { return nil }
        var data = Data(count: count)
        let result = data.withUnsafeMutableBytes { sysctl(&mib, u_int(mib.count), $0.baseAddress, &count, nil, 0) }
        guard result == 0 else { return nil }
        return data.withUnsafeBytes { bytes in
            var result: [String: HUDNetworkCounters] = [:]
            var offset = 0
            while offset + 4 <= count {
                let length = Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard length >= 4, offset + length <= count else { return nil }
                if bytes[offset + 3] == RTM_IFINFO2, length >= MemoryLayout<if_msghdr2>.size {
                    let message = bytes.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var name = [CChar](repeating: 0, count: Int(IFNAMSIZ))
                    if if_indextoname(UInt32(message.ifm_index), &name) != nil {
                        let interface = String(cString: name)
                        if interface.hasPrefix("en"), message.ifm_flags & IFF_UP != 0,
                           message.ifm_flags & IFF_RUNNING != 0, message.ifm_flags & IFF_LOOPBACK == 0 {
                            result["\(interface)#\(message.ifm_index)"] = HUDNetworkCounters(
                                received: message.ifm_data.ifi_ibytes, sent: message.ifm_data.ifi_obytes)
                        }
                    }
                }
                offset += length
            }
            return result
        }
    }
}
