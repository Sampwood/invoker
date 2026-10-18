import Darwin
import Foundation

struct SystemMonitorSnapshot {
    let cpuUsage: Double
    let memoryUsage: Double
    let usedMemory: UInt64
    let totalMemory: UInt64
    let usedDisk: UInt64
    let totalDisk: UInt64
    let uptime: TimeInterval
}

@MainActor
final class SystemMonitorViewModel: ObservableObject {
    @Published private(set) var snapshot: SystemMonitorSnapshot

    private var previousCPUTicks: [UInt64]?

    init() {
        snapshot = SystemMonitorSnapshot(
            cpuUsage: 0,
            memoryUsage: 0,
            usedMemory: 0,
            totalMemory: ProcessInfo.processInfo.physicalMemory,
            usedDisk: 0,
            totalDisk: 0,
            uptime: ProcessInfo.processInfo.systemUptime
        )
        refresh()
    }

    func refresh() {
        let memory = readMemory()
        let disk = readDisk()

        snapshot = SystemMonitorSnapshot(
            cpuUsage: readCPUUsage(),
            memoryUsage: memory.usedRatio,
            usedMemory: memory.used,
            totalMemory: memory.total,
            usedDisk: disk.used,
            totalDisk: disk.total,
            uptime: ProcessInfo.processInfo.systemUptime
        )
    }

    private func readCPUUsage() -> Double {
        var processorCount: natural_t = 0
        var cpuLoadInfo: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &cpuLoadInfo,
            &infoCount
        )
        guard result == KERN_SUCCESS, let cpuLoadInfo else {
            return 0
        }

        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: cpuLoadInfo),
                vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }

        let ticks = Array(UnsafeBufferPointer(
            start: cpuLoadInfo,
            count: Int(infoCount)
        )).map { UInt64(max($0, 0)) }
        let statesPerProcessor = Int(CPU_STATE_MAX)
        guard ticks.count >= Int(processorCount) * statesPerProcessor else {
            return 0
        }

        var totalDelta: UInt64 = 0
        var idleDelta: UInt64 = 0
        for processor in 0..<Int(processorCount) {
            let offset = processor * statesPerProcessor
            let current = Array(ticks[offset..<(offset + statesPerProcessor)])
            let previous = previousCPUTicks.map {
                Array($0[offset..<(offset + statesPerProcessor)])
            }

            if let previous {
                let deltas = zip(current, previous).map { $0 >= $1 ? $0 - $1 : 0 }
                totalDelta += deltas.reduce(0, +)
                idleDelta += deltas[Int(CPU_STATE_IDLE)]
            }
        }

        previousCPUTicks = ticks
        guard totalDelta > 0 else {
            return 0
        }
        return min(max(1 - Double(idleDelta) / Double(totalDelta), 0), 1)
    }

    private func readMemory() -> (used: UInt64, total: UInt64, usedRatio: Double) {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let pageSize = UInt64(vm_kernel_page_size)

        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            let total = ProcessInfo.processInfo.physicalMemory
            return (0, total, 0)
        }

        let usedPages = UInt64(statistics.active_count)
            + UInt64(statistics.inactive_count)
            + UInt64(statistics.wire_count)
            + UInt64(statistics.compressor_page_count)
        let used = usedPages * pageSize
        let total = ProcessInfo.processInfo.physicalMemory
        return (used, total, total > 0 ? Double(used) / Double(total) : 0)
    }

    private func readDisk() -> (used: UInt64, total: UInt64) {
        let path = FileManager.default.homeDirectoryForCurrentUser.path
        guard
            let values = try? FileManager.default.attributesOfFileSystem(forPath: path),
            let total = values[.systemSize] as? NSNumber,
            let free = values[.systemFreeSize] as? NSNumber
        else {
            return (0, 0)
        }

        let totalBytes = total.uint64Value
        let freeBytes = free.uint64Value
        return (totalBytes > freeBytes ? totalBytes - freeBytes : 0, totalBytes)
    }
}
