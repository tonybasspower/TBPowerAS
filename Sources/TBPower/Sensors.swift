import Foundation
import CSMC
import IOKit.ps
import Metal
import CoreGraphics

struct SensorSnapshot: Equatable {
    var cpuTemp: Double?
    var gpuTemp: Double?
    var batteryTemp: Double?
    var fans: [Int] = []          // RPM attuali
    var fanMax: [Int] = []
    var fanMin: [Int] = []
    var fanManual: [Bool] = []    // F{n}Md == 1
    var chargeLimit: Int?         // Configurazione helper, non un registro percentuale
    var chargePaused: Bool?
    var batteryPercent: Int?
    var onAC: Bool = false
    var charging: Bool = false
    var activeGPU: String?        // GPU che pilota lo schermo interno
    var activeGPUIsIntegrated: Bool?
}

/// Letture non privilegiate (SMC in sola lettura, IOPowerSources, Metal).
enum Sensors {
    // Massimo dei sensori disponibili. Le chiavi cambiano da chip a chip: quelle assenti
    // falliscono la lettura e vengono ignorate (verificate su M1 Pro; M1/M2/M3/M4 dalle
    // tabelle pubbliche di Stats). Nessun sensore valido = "—" nel menu.
    static let cpuKeys = [
        "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0T", "Tp0X", "Tp0b",   // M1
        "Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp0f", "Tp0j",                                   // M2
        "Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E",   // M3
        "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E",
        "Te09", "Te0H", "Tp0V", "Tp0Y", "Tp0e",                                           // M4
    ]
    static let gpuKeys = [
        "Tg05", "Tg0D", "Tg0L", "Tg0T",                                                   // M1
        "Tg0f", "Tg0j",                                                                   // M2
        "Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A",                   // M3
        "Tg0G", "Tg0H", "Tg1U", "Tg1k", "Tg0K", "Tg0d", "Tg0e", "Tg0k",                   // M4
    ]
    static let batteryKeys = ["TB0T", "TB1T", "TB2T"]

    static func read() -> SensorSnapshot {
        var s = SensorSnapshot()
        var conn: smc_conn_t = 0
        if smc_open(&conn) == 0 {
            defer { smc_close(conn) }
            func first(_ keys: [String]) -> Double? {
                for k in keys {
                    var v: Double = 0
                    if smc_read_number(conn, k, &v) == 0, v.isFinite, v > 0, v < 130 { return v }
                }
                return nil
            }
            func hottest(_ keys: [String]) -> Double? {
                keys.compactMap { k -> Double? in
                    var v: Double = 0
                    return smc_read_number(conn, k, &v) == 0 && v.isFinite && v > 0 && v < 130 ? v : nil
                }.max()
            }
            s.cpuTemp = hottest(cpuKeys)
            s.gpuTemp = hottest(gpuKeys)
            s.batteryTemp = first(batteryKeys)
            var n: Double = 0
            let count = smc_read_number(conn, "FNum", &n) == 0 && n.isFinite ? max(0, min(Int(n), 4)) : 0
            for i in 0..<count {
                var rpm: Double = 0, mx: Double = 0
                if smc_read_number(conn, "F\(i)Ac", &rpm) == 0, rpm.isFinite, (0...20000).contains(rpm) { s.fans.append(Int(rpm.rounded())) }
                if smc_read_number(conn, "F\(i)Mx", &mx) == 0, mx.isFinite, (0...20000).contains(mx) { s.fanMax.append(Int(mx.rounded())) }
                var mn: Double = 0, md: Double = 0
                if smc_read_number(conn, "F\(i)Mn", &mn) == 0, mn.isFinite, (0...20000).contains(mn) { s.fanMin.append(Int(mn.rounded())) }
                if smc_read_number(conn, "F\(i)Md", &md) == 0 { s.fanManual.append(md >= 1) }
            }
            var paused: Int32 = 0
            if smc_charge_paused(conn, &paused) == 0 { s.chargePaused = paused != 0 }
        }
        if let text = try? String(contentsOfFile: "/Library/Application Support/TBPowerAS/config", encoding: .utf8) {
            for line in text.split(separator: "\n") {
                let p = line.split(separator: "=")
                if p.count == 2, p[0] == "charge_limit", let v = Int(p[1]), (50...100).contains(v) { s.chargeLimit = v }
            }
        }
        readBattery(into: &s)
        readActiveGPU(into: &s)
        return s
    }

    private static func readBattery(into s: inout SensorSnapshot) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for src in list {
            guard let d = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            if let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 {
                s.batteryPercent = cur * 100 / max
            }
            s.onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            s.charging = (d[kIOPSIsChargingKey] as? Bool) ?? false
        }
    }

    /// GPU attiva = dispositivo Metal che pilota lo schermo interno (o il principale
    /// se il coperchio è chiuso). Non crea contesti grafici, quindi non forza lo
    /// GPU unificata Apple Silicon.
    private static func readActiveGPU(into s: inout SensorSnapshot) {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var n: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &n) == .success, n > 0 else { return }
        let online = Array(ids.prefix(Int(n)))
        let builtin: CGDirectDisplayID? = online.first(where: { CGDisplayIsBuiltin($0) != 0 })
        let display: CGDirectDisplayID = builtin ?? CGMainDisplayID()
        guard let dev = CGDirectDisplayCopyCurrentMetalDevice(display) else { return }
        s.activeGPU = dev.name
        s.activeGPUIsIntegrated = true
    }
}
