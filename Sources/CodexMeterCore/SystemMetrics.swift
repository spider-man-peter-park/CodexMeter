import Darwin
import Foundation
import IOKit
import Metal

public enum SystemMemoryPressure: String, CaseIterable, Codable, Sendable {
    case normal, warning, critical
}

public struct SystemProcessUsage: Equatable, Identifiable, Sendable {
    public let pid: Int32
    public let name: String
    public let memoryBytes: UInt64?
    public let cpuUsagePercent: Double?
    public var id: Int32 { pid }

    public init(pid: Int32, name: String, memoryBytes: UInt64? = nil, cpuUsagePercent: Double? = nil) {
        self.pid = pid
        self.name = name
        self.memoryBytes = memoryBytes
        self.cpuUsagePercent = cpuUsagePercent
    }
}

public struct SystemMetricsDetailDemand: Equatable, Sendable {
    public var processes: Bool
    public var networkProcesses: Bool
    public var gpuHardware: Bool

    public init(processes: Bool = false, networkProcesses: Bool = false, gpuHardware: Bool = false) {
        self.processes = processes
        self.networkProcesses = networkProcesses
        self.gpuHardware = gpuHardware
    }

    public static let all = Self(processes: true, networkProcesses: true, gpuHardware: true)
}

public struct SystemMetricsSnapshot: Equatable, Sendable {
    public let sampledAt: Date
    public let cpuUsagePercent: Double?
    public let gpuUsagePercent: Double?
    public let memoryUsedBytes: UInt64?
    public let memoryTotalBytes: UInt64?
    public let networkUploadBytesPerSecond: Double?
    public let networkDownloadBytesPerSecond: Double?
    public let networkTopProcesses: [SystemNetworkProcessUsage]
    public let networkProcessesUpdatedAt: Date?
    public let memoryAppBytes: UInt64?
    public let memoryWiredBytes: UInt64?
    public let memoryCompressedBytes: UInt64?
    public let memoryFreeBytes: UInt64?
    public let memorySwapUsedBytes: UInt64?
    public let memoryPressure: SystemMemoryPressure?
    public let cpuUserPercent: Double?
    public let cpuSystemPercent: Double?
    public let cpuIdlePercent: Double?
    public let physicalCoreCount: Int?
    public let logicalCoreCount: Int?
    public let loadAverages: [Double]?
    public let cpuTopProcesses: [SystemProcessUsage]
    public let memoryTopProcesses: [SystemProcessUsage]
    public let gpuDeviceNames: [String]
    public let gpuHasUnifiedMemory: Bool?
    public let gpuRecommendedWorkingSetBytes: UInt64?
    public let gpuRendererUsagePercent: Double?
    public let gpuTilerUsagePercent: Double?

    public init(sampledAt: Date = Date(), cpuUsagePercent: Double? = nil, gpuUsagePercent: Double? = nil,
                memoryUsedBytes: UInt64? = nil, memoryTotalBytes: UInt64? = nil,
                networkUploadBytesPerSecond: Double? = nil, networkDownloadBytesPerSecond: Double? = nil,
                memoryAppBytes: UInt64? = nil, memoryWiredBytes: UInt64? = nil, memoryCompressedBytes: UInt64? = nil,
                memoryFreeBytes: UInt64? = nil, memorySwapUsedBytes: UInt64? = nil, memoryPressure: SystemMemoryPressure? = nil,
                cpuUserPercent: Double? = nil, cpuSystemPercent: Double? = nil, cpuIdlePercent: Double? = nil,
                physicalCoreCount: Int? = nil, logicalCoreCount: Int? = nil, loadAverages: [Double]? = nil,
                cpuTopProcesses: [SystemProcessUsage] = [], memoryTopProcesses: [SystemProcessUsage] = [],
                gpuDeviceNames: [String] = [], gpuHasUnifiedMemory: Bool? = nil, gpuRecommendedWorkingSetBytes: UInt64? = nil,
                gpuRendererUsagePercent: Double? = nil, gpuTilerUsagePercent: Double? = nil,
                networkTopProcesses: [SystemNetworkProcessUsage] = [], networkProcessesUpdatedAt: Date? = nil) {
        self.sampledAt = sampledAt
        self.cpuUsagePercent = cpuUsagePercent
        self.gpuUsagePercent = gpuUsagePercent
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.networkUploadBytesPerSecond = networkUploadBytesPerSecond
        self.networkDownloadBytesPerSecond = networkDownloadBytesPerSecond
        self.networkTopProcesses = networkTopProcesses
        self.networkProcessesUpdatedAt = networkProcessesUpdatedAt
        self.memoryAppBytes = memoryAppBytes
        self.memoryWiredBytes = memoryWiredBytes
        self.memoryCompressedBytes = memoryCompressedBytes
        self.memoryFreeBytes = memoryFreeBytes
        self.memorySwapUsedBytes = memorySwapUsedBytes
        self.memoryPressure = memoryPressure
        self.cpuUserPercent = cpuUserPercent
        self.cpuSystemPercent = cpuSystemPercent
        self.cpuIdlePercent = cpuIdlePercent
        self.physicalCoreCount = physicalCoreCount
        self.logicalCoreCount = logicalCoreCount
        self.loadAverages = loadAverages
        self.cpuTopProcesses = cpuTopProcesses
        self.memoryTopProcesses = memoryTopProcesses
        self.gpuDeviceNames = gpuDeviceNames
        self.gpuHasUnifiedMemory = gpuHasUnifiedMemory
        self.gpuRecommendedWorkingSetBytes = gpuRecommendedWorkingSetBytes
        self.gpuRendererUsagePercent = gpuRendererUsagePercent
        self.gpuTilerUsagePercent = gpuTilerUsagePercent
    }

    public var memoryUsagePercent: Double? {
        guard let memoryUsedBytes, let memoryTotalBytes, memoryTotalBytes > 0 else { return nil }
        return min(100, Double(memoryUsedBytes) / Double(memoryTotalBytes) * 100)
    }

    public func fresh(at now: Date = Date()) -> SystemMetricsSnapshot? {
        let age = now.timeIntervalSince(sampledAt)
        return (-1...10).contains(age) ? self : nil
    }
}

struct SystemCPUTicks: Equatable, Sendable {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32

    func utilization(since previous: Self) -> Double? {
        percentages(since: previous).map { 100 - $0.idle }
    }

    func percentages(since previous: Self) -> (user: Double, system: Double, idle: Double)? {
        let current = [user, system, idle, nice]
        let old = [previous.user, previous.system, previous.idle, previous.nice]
        guard zip(current, old).allSatisfy({ $0 >= $1 }) else { return nil }
        let deltas = zip(current, old).map { UInt64($0) - UInt64($1) }
        let total = deltas.reduce(0, +)
        guard total > 0 else { return nil }
        return (Double(deltas[0] + deltas[3]) / Double(total) * 100,
                Double(deltas[1]) / Double(total) * 100, Double(deltas[2]) / Double(total) * 100)
    }
}

struct SystemNetworkCounter: Equatable, Sendable {
    let received: UInt64
    let sent: UInt64
}

struct SystemMetricDeltas: Sendable {
    private var cpu: SystemCPUTicks?
    private var network: [String: SystemNetworkCounter]?
    private var uptime: TimeInterval?

    mutating func consume(cpu currentCPU: SystemCPUTicks?, network currentNetwork: [String: SystemNetworkCounter]?,
                          uptime currentUptime: TimeInterval) -> (cpu: Double?, upload: Double?, download: Double?, user: Double?, system: Double?, idle: Double?) {
        defer { cpu = currentCPU; network = currentNetwork; uptime = currentUptime }
        guard currentUptime.isFinite, let uptime else { return (nil, nil, nil, nil, nil, nil) }
        let elapsed = currentUptime - uptime
        // Long pauses (including sleep) need a fresh baseline instead of a misleading averaged rate.
        guard elapsed >= 0.05, elapsed <= 10 else { return (nil, nil, nil, nil, nil, nil) }
        let breakdown = currentCPU.flatMap { current in cpu.flatMap { current.percentages(since: $0) } }
        let usage = breakdown.map { 100 - $0.idle }
        guard let network, let currentNetwork else { return (usage, nil, nil, breakdown?.user, breakdown?.system, breakdown?.idle) }
        guard network.keys == currentNetwork.keys else { return (usage, nil, nil, breakdown?.user, breakdown?.system, breakdown?.idle) }
        var received = 0.0
        var sent = 0.0
        for (name, current) in currentNetwork {
            guard let previous = network[name], current.received >= previous.received, current.sent >= previous.sent else {
                return (usage, nil, nil, breakdown?.user, breakdown?.system, breakdown?.idle)
            }
            received += Double(current.received - previous.received)
            sent += Double(current.sent - previous.sent)
        }
        return (usage, sent / elapsed, received / elapsed, breakdown?.user, breakdown?.system, breakdown?.idle)
    }
}

struct SystemProcessCounter: Sendable {
    let pid: Int32
    let name: String
    let startIdentity: UInt64
    let memoryBytes: UInt64
    let userTicks: UInt64
    let systemTicks: UInt64
}

struct SystemProcessTimebase: Sendable {
    let numerator: UInt32
    let denominator: UInt32

    func nanoseconds(forTicks ticks: Double) -> Double? {
        guard numerator > 0, denominator > 0, ticks.isFinite, ticks >= 0 else { return nil }
        let converted = ticks * Double(numerator) / Double(denominator)
        return converted.isFinite ? converted : nil
    }
}

struct SystemProcessDeltas: Sendable {
    private var previous: [Int32: SystemProcessCounter] = [:]
    private var uptime: TimeInterval?

    mutating func consume(_ counters: [SystemProcessCounter]?, uptime now: TimeInterval,
                          timebase: SystemProcessTimebase?)
        -> (cpu: [SystemProcessUsage], memory: [SystemProcessUsage]) {
        defer {
            previous = Dictionary((counters ?? []).map { ($0.pid, $0) }, uniquingKeysWith: { _, newer in newer })
            uptime = counters == nil ? nil : now
        }
        guard let counters else { return ([], []) }
        let interval = uptime.map { now - $0 }
        let validInterval = interval.map { $0.isFinite && $0 >= 0.05 && $0 <= 15 } ?? false
        let processes = counters.map { counter in
            var cpu: Double?
            if validInterval, let interval, let old = previous[counter.pid], old.startIdentity == counter.startIdentity,
               counter.userTicks >= old.userTicks, counter.systemTicks >= old.systemTicks {
                // Match Activity Monitor: one fully occupied logical core is 100%, so a process can exceed 100%.
                // rusage CPU counters use Mach absolute ticks, whose scale differs between Intel and Apple silicon.
                let ticks = Double(counter.userTicks - old.userTicks) + Double(counter.systemTicks - old.systemTicks)
                cpu = timebase?.nanoseconds(forTicks: ticks).map { $0 / 1_000_000_000 / interval * 100 }
            }
            return SystemProcessUsage(pid: counter.pid, name: counter.name, memoryBytes: counter.memoryBytes, cpuUsagePercent: cpu)
        }
        let cpu = processes.filter { $0.cpuUsagePercent != nil }.sorted {
            let a = $0.cpuUsagePercent ?? 0, b = $1.cpuUsagePercent ?? 0
            return a == b ? $0.pid < $1.pid : a > b
        }
        let memory = processes.sorted {
            let a = $0.memoryBytes ?? 0, b = $1.memoryBytes ?? 0
            return a == b ? $0.pid < $1.pid : a > b
        }
        return (Array(cpu.prefix(8)), Array(memory.prefix(8)))
    }
}

private struct SystemMemoryValues {
    let used: UInt64
    let app: UInt64
    let wired: UInt64
    let compressed: UInt64
    let free: UInt64
}

private struct SystemGPUValues {
    let usage: Double?
    let renderer: Double?
    let tiler: Double?
}

struct SystemGPUHardware: Sendable {
    let names: [String]
    let unifiedMemory: Bool?
    let recommendedWorkingSet: UInt64?

    static func read() -> Self {
        let devices = MTLCopyAllDevices()
        let primary = MTLCreateSystemDefaultDevice()
        // Capacity and unified-memory metadata describe the default Metal device; names list all devices.
        let names = Array(Set(devices.map(\.name))).sorted()
        return Self(names: names, unifiedMemory: primary?.hasUnifiedMemory,
                    recommendedWorkingSet: primary.map(\.recommendedMaxWorkingSetSize))
    }
}

struct SystemMetricsDetailState: Sendable {
    private var processDeltas = SystemProcessDeltas()
    private var lastProcessScan: TimeInterval?
    private(set) var processUsage: (cpu: [SystemProcessUsage], memory: [SystemProcessUsage]) = ([], [])
    private(set) var gpuHardware: SystemGPUHardware?
    private var gpuHardwareUpdatedAt: TimeInterval?

    mutating func sample(demand: SystemMetricsDetailDemand, uptime: TimeInterval,
                         readProcesses: () -> [SystemProcessCounter]?,
                         readProcessTimebase: () -> SystemProcessTimebase?,
                         readGPUHardware: () -> SystemGPUHardware) {
        if demand.processes {
            if lastProcessScan == nil || uptime < (lastProcessScan ?? 0) || uptime - (lastProcessScan ?? 0) >= 5 {
                processUsage = processDeltas.consume(readProcesses(), uptime: uptime, timebase: readProcessTimebase())
                lastProcessScan = uptime
            }
        } else {
            // Closing the detail releases every process counter and requires a new CPU baseline on return.
            processDeltas = SystemProcessDeltas()
            lastProcessScan = nil
            processUsage = ([], [])
        }

        if demand.gpuHardware {
            if gpuHardware == nil || uptime < (gpuHardwareUpdatedAt ?? 0) || uptime - (gpuHardwareUpdatedAt ?? 0) >= 30 {
                gpuHardware = readGPUHardware()
                gpuHardwareUpdatedAt = uptime
            }
        } else {
            gpuHardware = nil
            gpuHardwareUpdatedAt = nil
        }
    }
}

enum SystemMetricValues {
    static func memoryUsedBytes(wired: UInt64, anonymous: UInt64, purgeable: UInt64,
                                compressed: UInt64, pageSize: UInt64, total: UInt64) -> UInt64? {
        guard pageSize > 0, total > 0 else { return nil }
        // Purgeable anonymous pages can be reclaimed; compressed pages count by their physical size.
        let appPages = anonymous > purgeable ? anonymous - purgeable : 0
        let pages = Double(wired) + Double(appPages) + Double(compressed)
        let bytes = pages * Double(pageSize)
        return bytes >= Double(total) ? total : UInt64(bytes)
    }

    static func gpuUtilization(_ statistics: [String: Any]) -> Double? {
        gpuUtilization(statistics, key: "Device Utilization %")
    }

    static func gpuUtilization(_ statistics: [String: Any], key: String) -> Double? {
        // Driver properties are optional and vary by GPU. Never substitute zero for missing telemetry.
        guard let number = statistics[key] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        return value.isFinite && (0...100).contains(value) ? value : nil
    }

    static func memoryPressure(_ value: Int32?) -> SystemMemoryPressure? {
        switch value {
        case 1: .normal
        case 2: .warning
        case 4: .critical
        default: nil
        }
    }

    static func processName(executablePath: String?, fallbackName: String?) -> String? {
        if let executablePath, executablePath.hasPrefix("/"), !executablePath.hasSuffix("/"),
           !executablePath.utf8.contains(0) {
            let name = (executablePath as NSString).lastPathComponent
            if !name.isEmpty && name != "." && name != ".." { return name }
        }
        guard let fallbackName else { return nil }
        let name = (fallbackName as NSString).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || name == "/" || name == "." || name == ".." ? nil : name
    }

    static func includesInterface(name: String, type: UInt8, flags: Int32) -> Bool {
        // en* covers macOS Wi-Fi/Ethernet, including USB adapters. Logical links are excluded to avoid counting a packet twice.
        name.hasPrefix("en") && name.dropFirst(2).allSatisfy(\.isNumber) && name.count > 2
            && type == UInt8(IFT_ETHER) && flags & IFF_UP != 0 && flags & IFF_RUNNING != 0 && flags & IFF_LOOPBACK == 0
    }
}

public actor SystemMetricsMonitor {
    private let networkProcessMonitor = NetworkProcessMonitor()
    private var deltas = SystemMetricDeltas()
    private var details = SystemMetricsDetailState()

    public init() {}

    public func reset() async {
        await networkProcessMonitor.reset()
        deltas = SystemMetricDeltas()
        details = SystemMetricsDetailState()
    }

    public func sample(demand: SystemMetricsDetailDemand = .all) async -> SystemMetricsSnapshot {
        let networkProcesses = await networkProcessMonitor.snapshot(enabled: demand.networkProcesses)
        let cpu = Self.readCPU()
        let network = Self.readNetwork()
        let rates = deltas.consume(cpu: cpu, network: network, uptime: ProcessInfo.processInfo.systemUptime)
        let total = ProcessInfo.processInfo.physicalMemory
        let memory = Self.readMemory(total: total)
        let gpu = Self.readGPU()
        details.sample(demand: demand, uptime: ProcessInfo.processInfo.systemUptime,
            readProcesses: Self.readProcesses, readProcessTimebase: Self.readProcessTimebase,
            readGPUHardware: SystemGPUHardware.read)
        return SystemMetricsSnapshot(cpuUsagePercent: rates.cpu, gpuUsagePercent: gpu.usage,
            memoryUsedBytes: memory?.used, memoryTotalBytes: total > 0 ? total : nil,
            networkUploadBytesPerSecond: rates.upload, networkDownloadBytesPerSecond: rates.download,
            memoryAppBytes: memory?.app, memoryWiredBytes: memory?.wired, memoryCompressedBytes: memory?.compressed,
            memoryFreeBytes: memory?.free, memorySwapUsedBytes: Self.readSwap(),
            memoryPressure: SystemMetricValues.memoryPressure(Self.readInt("kern.memorystatus_vm_pressure_level")),
            cpuUserPercent: rates.user, cpuSystemPercent: rates.system, cpuIdlePercent: rates.idle,
            physicalCoreCount: Self.readInt("hw.physicalcpu").map(Int.init),
            logicalCoreCount: Self.readInt("hw.logicalcpu").map(Int.init), loadAverages: Self.readLoadAverages(),
            cpuTopProcesses: details.processUsage.cpu, memoryTopProcesses: details.processUsage.memory,
            gpuDeviceNames: details.gpuHardware?.names ?? [], gpuHasUnifiedMemory: details.gpuHardware?.unifiedMemory,
            gpuRecommendedWorkingSetBytes: details.gpuHardware?.recommendedWorkingSet,
            gpuRendererUsagePercent: gpu.renderer, gpuTilerUsagePercent: gpu.tiler,
            networkTopProcesses: networkProcesses?.processes ?? [], networkProcessesUpdatedAt: networkProcesses?.updatedAt)
    }

    private static func readCPU() -> SystemCPUTicks? {
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
        return SystemCPUTicks(user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
    }

    private static func readMemory(total: UInt64) -> SystemMemoryValues? {
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
        guard result == KERN_SUCCESS, host_page_size(host, &pageSize) == KERN_SUCCESS else { return nil }
        guard let used = SystemMetricValues.memoryUsedBytes(wired: UInt64(info.wire_count), anonymous: UInt64(info.internal_page_count),
            purgeable: UInt64(info.purgeable_count), compressed: UInt64(info.compressor_page_count), pageSize: UInt64(pageSize), total: total) else { return nil }
        let appPages = info.internal_page_count > info.purgeable_count ? info.internal_page_count - info.purgeable_count : 0
        // Free includes reclaimable cache so the displayed used/free amounts partition physical memory.
        return SystemMemoryValues(used: used, app: UInt64(appPages) * UInt64(pageSize),
            wired: UInt64(info.wire_count) * UInt64(pageSize), compressed: UInt64(info.compressor_page_count) * UInt64(pageSize), free: total - used)
    }

    private static func readGPU() -> SystemGPUValues {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return SystemGPUValues(usage: nil, renderer: nil, tiler: nil)
        }
        defer { IOObjectRelease(iterator) }
        var values: [SystemGPUValues] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            if let property = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
               let statistics = property as? [String: Any] {
                values.append(SystemGPUValues(usage: SystemMetricValues.gpuUtilization(statistics),
                    renderer: SystemMetricValues.gpuUtilization(statistics, key: "Renderer Utilization %"),
                    tiler: SystemMetricValues.gpuUtilization(statistics, key: "Tiler Utilization %")))
            }
        }
        // On multi-GPU systems show the busiest reporting device; summing percentages would exceed 100%.
        return values.max(by: { ($0.usage ?? -1) < ($1.usage ?? -1) }) ?? SystemGPUValues(usage: nil, renderer: nil, tiler: nil)
    }

    private static func readInt(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0, size == MemoryLayout<Int32>.size else { return nil }
        return value
    }

    private static func readSwap() -> UInt64? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0, size == MemoryLayout<xsw_usage>.size else { return nil }
        return usage.xsu_used
    }

    private static func readLoadAverages() -> [Double]? {
        var values = [Double](repeating: 0, count: 3)
        let count = values.withUnsafeMutableBufferPointer { getloadavg($0.baseAddress, 3) }
        guard count == 3, values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        return values
    }

    private static func readProcesses() -> [SystemProcessCounter]? {
        let initialCount = proc_listallpids(nil, 0)
        guard initialCount > 0, initialCount < 1_000_000 else { return nil }
        let capacity = Int(initialCount) + 128
        var pids = [Int32](repeating: 0, count: capacity)
        let count = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { return nil }
        var counters: [SystemProcessCounter] = []
        counters.reserveCapacity(Int(count))
        for pid in pids.prefix(min(Int(count), capacity)) where pid > 0 {
            var usage = rusage_info_v2()
            let result = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
            }
            // Processes can exit during enumeration, and protected/other-user processes may deny access.
            guard result == 0 else { continue }
            var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let pathLength = path.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
            path[path.count - 1] = 0
            // Only the executable basename leaves this scope; full executable paths are never retained.
            var displayName = SystemMetricValues.processName(executablePath: pathLength > 0 ? String(cString: path) : nil, fallbackName: nil)
            if displayName == nil {
                var name = [CChar](repeating: 0, count: 1024)
                let nameLength = name.withUnsafeMutableBytes { proc_name(pid, $0.baseAddress, UInt32($0.count)) }
                name[name.count - 1] = 0
                displayName = SystemMetricValues.processName(executablePath: nil, fallbackName: nameLength > 0 ? String(cString: name) : nil)
            }
            guard let displayName else { continue }
            counters.append(SystemProcessCounter(pid: pid, name: displayName, startIdentity: usage.ri_proc_start_abstime,
                memoryBytes: usage.ri_phys_footprint, userTicks: usage.ri_user_time, systemTicks: usage.ri_system_time))
        }
        return counters
    }

    private static func readProcessTimebase() -> SystemProcessTimebase? {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS, info.numer > 0, info.denom > 0 else { return nil }
        return SystemProcessTimebase(numerator: info.numer, denominator: info.denom)
    }

    private static func readNetwork() -> [String: SystemNetworkCounter]? {
        // NET_RT_IFLIST2 provides 64-bit byte counters; getifaddrs only exposes 32-bit counters on macOS.
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var data = Data(count: size)
        let result = data.withUnsafeMutableBytes { sysctl(&mib, u_int(mib.count), $0.baseAddress, &size, nil, 0) }
        guard result == 0 else { return nil }
        return data.withUnsafeBytes { buffer in
            var counters: [String: SystemNetworkCounter] = [:]
            var offset = 0
            while offset + 4 <= size {
                let length = Int(buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard length >= 4, offset + length <= size else { return nil }
                let type = buffer[offset + 3]
                if type == RTM_IFINFO2, length >= MemoryLayout<if_msghdr2>.size {
                    let message = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var name = [CChar](repeating: 0, count: Int(IFNAMSIZ))
                    if if_indextoname(UInt32(message.ifm_index), &name) != nil {
                        let interface = String(cString: name)
                        if SystemMetricValues.includesInterface(name: interface, type: message.ifm_data.ifi_type, flags: message.ifm_flags) {
                            let identity = "\(interface)#\(message.ifm_index)"
                            counters[identity] = SystemNetworkCounter(received: message.ifm_data.ifi_ibytes, sent: message.ifm_data.ifi_obytes)
                        }
                    }
                }
                offset += length
            }
            return counters
        }
    }
}
