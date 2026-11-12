// TBPower AS: root helper with a closed command allowlist. Apple Silicon only.
import Foundation
import Darwin
import IOKit.ps
import CSMC
#if !arch(arm64)
#error("TBPower AS richiede arm64")
#endif
let supportDir = "/Library/Application Support/TBPowerAS"
let configPath = supportDir + "/config"
enum Exit: Int32 { case ok = 0, failure = 1, conflict = 2, usage = 64, notRoot = 77 }
func fail(_ msg: String, _ code: Exit = .failure) -> Never {
    FileHandle.standardError.write(("tbpower-as-helper: " + msg + "\n").data(using: .utf8)!)
    exit(code.rawValue)
}
func usage() -> Never {
    fail("uso: tbpower-as-helper charge-limit <50-100> | charge-pause 0|1 | lowpower 0|1 | nosleep 0|1 | amphetamine 0|1 | enforce | reapply | charge-supported | status", .usage)
}
/// Esegue un binario di sistema con path assoluto, senza shell e con ambiente vuoto.
@discardableResult
func run(_ path: String, _ args: [String], allowFailure: Bool = false) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    p.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
    p.standardInput = FileHandle.nullDevice
    do { try p.run() } catch { fail("impossibile eseguire \(path): \(error)") }
    p.waitUntilExit()
    if p.terminationStatus != 0 && !allowFailure {
        fail("\(path) \(args.joined(separator: " ")) è terminato con codice \(p.terminationStatus)")
    }
    return p.terminationStatus
}

func parsePercent(_ s: String) -> UInt8? {
    // Solo cifre ASCII, 2-3 caratteri, nessun segno/spazio.
    guard (2...3).contains(s.utf8.count), s.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
          let v = Int(s), (50...100).contains(v) else { return nil }
    return UInt8(v)
}

func saveConfig(chargeLimit: UInt8) {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: supportDir, isDirectory: &isDir), isDir.boolValue else {
        fail("\(supportDir) mancante: eseguire install-helper.sh")
    }
    let tmp = supportDir + "/.config.tmp"
    let body = "charge_limit=\(chargeLimit)\n"
    guard fm.createFile(atPath: tmp, contents: body.data(using: .utf8),
                        attributes: [.posixPermissions: 0o644, .ownerAccountID: 0, .groupOwnerAccountID: 0])
    else { fail("impossibile scrivere \(tmp)") }
    guard rename(tmp, configPath) == 0 else { fail("impossibile aggiornare \(configPath)") }
}

func loadSavedChargeLimit() -> UInt8? {
    guard let data = FileManager.default.contents(atPath: configPath),
          let text = String(data: data, encoding: .utf8) else { return nil }
    for line in text.split(separator: "\n") {
        let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
        if parts.count == 2, parts[0] == "charge_limit" { return parsePercent(parts[1]) }
    }
    return nil
}

let amphetamineRestorePath = supportDir + "/amphetamine-restore"

struct SleepTimers {
    var displaysleep: Int
    var disksleep: Int
    var sleep: Int
}

func parsePmsetTimers() -> (battery: SleepTimers, ac: SleepTimers) {
    let out = {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-g", "custom"]
        p.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }()
    var section = ""
    var batt = SleepTimers(displaysleep: 10, disksleep: 10, sleep: 1)
    var ac = SleepTimers(displaysleep: 10, disksleep: 10, sleep: 1)
    for raw in out.split(separator: "\n") {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasSuffix(":") { section = line; continue }
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count >= 2, let v = Int(parts[1]) else { continue }
        let key = String(parts[0])
        func apply(_ t: inout SleepTimers) {
            switch key {
            case "displaysleep": t.displaysleep = v
            case "disksleep": t.disksleep = v
            case "sleep": t.sleep = v
            default: break
            }
        }
        if section.hasPrefix("Battery") { apply(&batt) }
        else if section.hasPrefix("AC") { apply(&ac) }
    }
    return (batt, ac)
}

func amphetamineActiveOnDisk() -> Bool {
    guard let data = FileManager.default.contents(atPath: amphetamineRestorePath),
          let text = String(data: data, encoding: .utf8) else { return false }
    return text.split(separator: "\n").contains(where: { $0 == "active=1" })
}

func saveAmphetamineRestore(battery: SleepTimers, ac: SleepTimers) {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: supportDir, isDirectory: &isDir), isDir.boolValue else {
        fail("\(supportDir) mancante: eseguire install-helper.sh")
    }
    let body = """
    active=1
    battery_displaysleep=\(battery.displaysleep)
    battery_disksleep=\(battery.disksleep)
    battery_sleep=\(battery.sleep)
    ac_displaysleep=\(ac.displaysleep)
    ac_disksleep=\(ac.disksleep)
    ac_sleep=\(ac.sleep)

    """
    let tmp = supportDir + "/.amphetamine-restore.tmp"
    guard fm.createFile(atPath: tmp, contents: body.data(using: .utf8),
                        attributes: [.posixPermissions: 0o644, .ownerAccountID: 0, .groupOwnerAccountID: 0])
    else { fail("impossibile scrivere \(tmp)") }
    guard rename(tmp, amphetamineRestorePath) == 0 else { fail("impossibile aggiornare \(amphetamineRestorePath)") }
}

func loadAmphetamineRestore() -> (battery: SleepTimers, ac: SleepTimers)? {
    guard let data = FileManager.default.contents(atPath: amphetamineRestorePath),
          let text = String(data: data, encoding: .utf8) else { return nil }
    var map: [String: Int] = [:]
    for line in text.split(separator: "\n") {
        let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2, let v = Int(parts[1]) else { continue }
        map[parts[0]] = v
    }
    guard let bd = map["battery_displaysleep"], let bk = map["battery_disksleep"], let bs = map["battery_sleep"],
          let ad = map["ac_displaysleep"], let ak = map["ac_disksleep"], let asl = map["ac_sleep"]
    else { return nil }
    return (SleepTimers(displaysleep: bd, disksleep: bk, sleep: bs),
            SleepTimers(displaysleep: ad, disksleep: ak, sleep: asl))
}

func applyTimers(flag: String, _ t: SleepTimers) {
    run("/usr/bin/pmset", [flag, "displaysleep", String(t.displaysleep),
                           "disksleep", String(t.disksleep),
                           "sleep", String(t.sleep)])
}

func setAmphetamine(on: Bool) {
    if on {
        if !amphetamineActiveOnDisk() {
            let cur = parsePmsetTimers()
            saveAmphetamineRestore(battery: cur.battery, ac: cur.ac)
        } else {
            // già attiva: aggiorna solo il flag active
            if let saved = loadAmphetamineRestore() {
                saveAmphetamineRestore(battery: saved.battery, ac: saved.ac)
            }
        }
        let zero = SleepTimers(displaysleep: 0, disksleep: 0, sleep: 0)
        applyTimers(flag: "-b", zero)
        applyTimers(flag: "-c", zero)
    } else {
        guard amphetamineActiveOnDisk() else { return }
        let saved = loadAmphetamineRestore()
            ?? (SleepTimers(displaysleep: 10, disksleep: 10, sleep: 1),
                SleepTimers(displaysleep: 10, disksleep: 10, sleep: 1))
        applyTimers(flag: "-b", saved.battery)
        applyTimers(flag: "-c", saved.ac)
        try? FileManager.default.removeItem(atPath: amphetamineRestorePath)
    }
}


func withSMC<T>(_ body: (smc_conn_t) -> T) -> T {
    var c: smc_conn_t = 0
    guard smc_open(&c) == 0 else { fail("AppleSMC non disponibile") }
    defer { smc_close(c) }
    return body(c)
}
func setPaused(_ pause: Bool) {
    withSMC { c in
        let r = smc_charge_set_paused(c, pause ? 1 : 0)
        guard r == 0 else { fail("inibizione carica fallita (\(r)); verificare stato alimentazione") }
    }
}
func battery() -> (percent: Int, ac: Bool)? {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
    for src in list {
        guard let d = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any],
              d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              let cur = d[kIOPSCurrentCapacityKey] as? Int,
              let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
        return (cur * 100 / max, d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
    }
    return nil
}
/// actuallymentor/battery "maintain" scrive le stesse key (CHTE/CH0B/CH0C): due gestori
/// si contenderebbero la pausa, quindi enforce non interviene finché è attivo.
func conflictingChargeTool() -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    p.arguments = ["-f", "co.palokaj.battery/battery maintain"]
    p.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return false }
    p.waitUntilExit()
    return p.terminationStatus == 0
}
// Shared policy with the app: no active discharge, 2-point hysteresis.
func enforce() {
    if conflictingChargeTool() { fail("carica gestita da 'battery maintain': nessuna azione", .conflict) }
    guard let limit = loadSavedChargeLimit() else { setPaused(false); fail("config limite mancante: carica riabilitata") }
    guard let b = battery() else { setPaused(false); fail("batteria non leggibile: carica riabilitata") }
    let paused = withSMC { c -> Bool in
        var p: Int32 = 0
        guard smc_charge_paused(c, &p) == 0 else { fail("stato carica non leggibile") }
        return p != 0
    }
    let action = smc_charge_action(Int32(limit), Int32(b.percent), b.ac ? 1 : 0, paused ? 1 : 0)
    if action >= 0 { setPaused(action == 1) }
}
let args = Array(CommandLine.arguments.dropFirst())
// Read-only diagnostics explicitly available without sudo.
if args == ["charge-supported"] { exit(withSMC { smc_charge_backend($0) != 0 } ? 0 : 3) }
if args == ["status"] {
    withSMC { c in
        var p: Int32 = 0
        let result = smc_charge_paused(c, &p)
        print("backend=\(smc_charge_backend(c)) conflict=\(conflictingChargeTool() ? 1 : 0) paused=\(result == 0 ? String(p) : "unknown") limit=\(loadSavedChargeLimit().map(String.init) ?? "none")")
    }
    exit(0)
}
guard geteuid() == 0 else { fail("richiede root tramite helper installato", .notRoot) }
umask(0o022)
// Serialize app and daemon mutations, including the two-key transaction and config files.
let lockFD = open(supportDir + "/helper.lock", O_CREAT | O_RDWR | O_NOFOLLOW, mode_t(0o600))
guard lockFD >= 0, flock(lockFD, LOCK_EX) == 0 else { fail("lock helper non disponibile: installare helper AS") }
defer { _ = flock(lockFD, LOCK_UN); close(lockFD) }
switch (args.first, args.count) {
case ("charge-limit", 2):
    guard let v = parsePercent(args[1]) else { usage() }
    // Persist config only: the periodic daemon/app applies inhibition at the threshold.
    saveConfig(chargeLimit: v)
case ("charge-pause", 2):
    guard args[1] == "0" || args[1] == "1" else { usage() }
    setPaused(args[1] == "1")
case ("lowpower", 2):
    guard args[1] == "0" || args[1] == "1" else { usage() }
    run("/usr/bin/pmset", ["-a", "lowpowermode", args[1]])
case ("nosleep", 2):
    guard args[1] == "0" || args[1] == "1" else { usage() }
    run("/usr/bin/pmset", ["-a", "disablesleep", args[1]])
case ("amphetamine", 2):
    guard args[1] == "0" || args[1] == "1" else { usage() }
    setAmphetamine(on: args[1] == "1")
case ("reapply", 1): setPaused(false) // Explicit recovery command, fail-open.
case ("enforce", 1): enforce() // LaunchDaemon on boot and every 15 seconds.
default: usage()
}
exit(0)
