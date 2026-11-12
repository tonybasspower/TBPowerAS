import Foundation
import Darwin

/// CPU %, RAM usata e traffico di rete (somma interfacce non loopback), aggiornati ogni 2 s.
final class SystemStats: ObservableObject {
    @Published private(set) var cpuPercent: Double?
    @Published private(set) var ramUsedGB: Double?
    @Published private(set) var ramPercent: Double?
    @Published private(set) var downBps: Double?
    @Published private(set) var upBps: Double?

    private var prevTicks: [(UInt32, UInt32, UInt32, UInt32)] = []
    private var prevNet: (UInt64, UInt64, Date)?
    private var timer: Timer?

    init() {
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
    }

    private func sample() {
        cpuPercent = readCPU()
        readRAM()
        readNet()
    }

    private func readCPU() -> Double? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info = info else { return nil }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)) }
        var ticks: [(UInt32, UInt32, UInt32, UInt32)] = []
        for i in 0..<Int(count) {
            let b = i * Int(CPU_STATE_MAX)
            ticks.append((UInt32(bitPattern: info[b + Int(CPU_STATE_USER)]), UInt32(bitPattern: info[b + Int(CPU_STATE_SYSTEM)]),
                          UInt32(bitPattern: info[b + Int(CPU_STATE_NICE)]), UInt32(bitPattern: info[b + Int(CPU_STATE_IDLE)])))
        }
        defer { prevTicks = ticks }
        guard prevTicks.count == ticks.count else { return nil }
        var busy: UInt64 = 0, total: UInt64 = 0
        for (a, p) in zip(ticks, prevTicks) {
            let u = UInt64(a.0 &- p.0), s = UInt64(a.1 &- p.1), n = UInt64(a.2 &- p.2), idle = UInt64(a.3 &- p.3)
            busy += u + s + n; total += u + s + n + idle
        }
        return total > 0 ? Double(busy) / Double(total) * 100 : nil
    }

    private func readRAM() {
        var stats = vm_statistics64()
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size) }
        }
        guard r == KERN_SUCCESS else { return }
        let page = Double(vm_kernel_page_size)
        // Come Monitoraggio Attività: app (interne - purgeable) + wired + compressa.
        let used = (Double(stats.internal_page_count) - Double(stats.purgeable_count) + Double(stats.wire_count)
                    + Double(stats.compressor_page_count)) * page
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        ramUsedGB = used / 1_073_741_824
        ramPercent = total > 0 ? used / total * 100 : nil
    }

    private func readNet() {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return }
        defer { freeifaddrs(ifap) }
        var inB: UInt64 = 0, outB: UInt64 = 0
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = p {
            let flags = Int32(ifa.pointee.ifa_flags)
            if let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
               flags & IFF_LOOPBACK == 0, flags & IFF_UP != 0, let data = ifa.pointee.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                inB += UInt64(d.ifi_ibytes); outB += UInt64(d.ifi_obytes)
            }
            p = ifa.pointee.ifa_next
        }
        let now = Date()
        if let (pi, po, pt) = prevNet {
            let dt = now.timeIntervalSince(pt)
            if dt > 0 {
                // I contatori sono a 32 bit: un wrap dà un delta negativo, che si scarta.
                downBps = inB >= pi ? Double(inB - pi) / dt : downBps
                upBps = outB >= po ? Double(outB - po) / dt : upBps
            }
        }
        prevNet = (inB, outB, now)
    }

    static func rate(_ bps: Double?) -> String {
        guard let b = bps else { return "—" }
        if b >= 1_048_576 { return String(format: "%.1fM", b / 1_048_576) }
        return String(format: "%.0fK", b / 1024)
    }
}

/// Preferenze della barra dei menu.
enum BarPref {
    static let logo = "bar.logo", logoStyle = "bar.logoStyle", cpuTemp = "bar.cpuTemp", cpuUsage = "bar.cpuUsage"
    static let ram = "bar.ram", ramPercent = "bar.ramPercent", gpuTemp = "bar.gpuTemp", net = "bar.net"
}
