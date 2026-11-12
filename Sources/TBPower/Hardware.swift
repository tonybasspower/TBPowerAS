import Foundation
import CSMC

struct Hardware {
    let fanCount: Int
    let chargeLimitSupported: Bool
    let lowPowerSupported: Bool
    // Manual fan control intentionally withheld until a write test is authorized.
    let fanControlSupported = false
    static let current: Hardware = {
        var fans = 0, charge = false
        var c: smc_conn_t = 0
        if smc_open(&c) == 0 {
            defer { smc_close(c) }
            var n: Double = 0
            if smc_read_number(c, "FNum", &n) == 0, n.isFinite { fans = max(0, min(Int(n), 4)) }
            charge = smc_charge_backend(c) != 0
        }
        let lp = runCapture("/usr/bin/pmset", ["-g", "cap"]).contains("lowpowermode")
        stateLog.notice("Apple Silicon: ventole \(fans), controllo carica \(charge), basso consumo \(lp)")
        return Hardware(fanCount: fans, chargeLimitSupported: charge, lowPowerSupported: lp)
    }()
}
