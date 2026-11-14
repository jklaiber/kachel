import Darwin
import Foundation

/// CPU, memory and network samples for the bar. Cheap kernel calls only.
final class Stats {
    private(set) var cpu: Double = 0          // 0…1, all cores
    private(set) var memoryUsed: UInt64 = 0   // bytes, like Activity Monitor's "Memory Used"
    let memoryTotal = ProcessInfo.processInfo.physicalMemory
    private(set) var down: Double = 0         // bytes/s
    private(set) var up: Double = 0

    private var lastTicks: (busy: UInt64, total: UInt64)?
    private var lastNet: (rx: UInt64, tx: UInt64, at: Date)?

    /// Screenshots: fixed numbers instead of measurements.
    func setDemo(cpu: Double, memory: UInt64, down: Double, up: Double) {
        self.cpu = cpu; memoryUsed = memory; self.down = down; self.up = up
    }

    func sample(cpu wantCPU: Bool, memory wantMemory: Bool, network wantNetwork: Bool) {
        if wantCPU { sampleCPU() }
        if wantMemory { sampleMemory() }
        if wantNetwork { sampleNetwork() }
    }

    private func sampleCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return }
        let t = info.cpu_ticks   // user, system, idle, nice
        let busy = UInt64(t.0) + UInt64(t.1) + UInt64(t.3)
        let total = busy + UInt64(t.2)
        if let last = lastTicks, total > last.total {
            cpu = Double(busy - last.busy) / Double(total - last.total)
        }
        lastTicks = (busy, total)
    }

    private func sampleMemory() {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return }
        let page = UInt64(vm_kernel_page_size)
        // Activity Monitor: app memory (internal - purgeable) + wired + compressed
        let app = UInt64(vm.internal_page_count) - UInt64(vm.purgeable_count)
        memoryUsed = (app + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)) * page
    }

    private func sampleNetwork() {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return }
        defer { freeifaddrs(ifap) }
        var rx: UInt64 = 0, tx: UInt64 = 0
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = p.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  ifa.ifa_flags & UInt32(IFF_UP) != 0, ifa.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  let data = ifa.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            let name = String(cString: ifa.ifa_name)
            // Physical interfaces and VPN tunnels would double count; keep en*/pdp*.
            guard name.hasPrefix("en") || name.hasPrefix("pdp_ip") else { continue }
            rx += UInt64(data.pointee.ifi_ibytes)
            tx += UInt64(data.pointee.ifi_obytes)
        }
        let now = Date()
        if let last = lastNet {
            let dt = now.timeIntervalSince(last.at)
            if dt > 0 {
                // Counters are 32-bit per interface and can wrap; ignore negative deltas.
                down = rx >= last.rx ? Double(rx - last.rx) / dt : down
                up = tx >= last.tx ? Double(tx - last.tx) / dt : up
            }
        }
        lastNet = (rx, tx, now)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var v = bytesPerSecond, i = 0
        while v >= 1000, i < units.count - 1 { v /= 1000; i += 1 }
        return i == 0 ? "\(Int(v)) \(units[i])/s" : String(format: v < 10 ? "%.1f %@/s" : "%.0f %@/s", v, units[i])
    }

    static func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }
}
