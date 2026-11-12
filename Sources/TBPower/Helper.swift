import Foundation
import os

let helperLog = Logger(subsystem: "com.tbp.tbpower-as", category: "helper")
let stateLog = Logger(subsystem: "com.tbp.tbpower-as", category: "state")

/// Invoca l'helper root tramite `sudo -n`: non chiede MAI la password.
/// Se la regola sudoers manca, fallisce subito con un errore leggibile.
enum Helper {
    static let path = "/Library/Application Support/TBPowerAS/tbpower-as-helper"

    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    /// true se il binario installato contiene il comando (helper vecchi non hanno `nosleep`).
    /// Cache per data di modifica: evita di rileggere il binario a ogni ridisegno del menu.
    private static var cache: [String: Bool] = [:]
    private static var cacheStamp: Date?
    private static let cacheLock = NSLock()
    static func supports(_ command: String) -> Bool {
        cacheLock.lock(); defer { cacheLock.unlock() }
        let stamp = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        if stamp != cacheStamp { cache = [:]; cacheStamp = stamp }
        if let v = cache[command] { return v }
        guard let d = FileManager.default.contents(atPath: path), let needle = command.data(using: .utf8)
        else { return false }
        let v = d.range(of: needle) != nil
        cache[command] = v
        return v
    }

    /// Altro gestore di carica attivo (actuallymentor/battery "maintain"): scrive le stesse
    /// key SMC e si contenderebbe la pausa con TBPower AS.
    static func conflictingChargeTool() -> String? {
        let out = runCapture("/usr/bin/pgrep", ["-fl", "co.palokaj.battery/battery maintain"])
        guard !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let pct = (try? String(contentsOfFile: NSHomeDirectory() + "/.battery/maintain.percentage", encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return pct.map { "battery maintain \($0)%" } ?? "battery maintain"
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    /// Bloccante: chiamare fuori dal main thread.
    static func run(_ args: [String]) -> Result<Void, Failure> {
        let cmd = args.joined(separator: " ")
        helperLog.notice("helper \(cmd, privacy: .public) …")
        let r = runRaw(args)
        switch r {
        case .success:
            helperLog.notice("helper \(cmd, privacy: .public) -> exit 0")
        case .failure(let f):
            helperLog.error("helper \(cmd, privacy: .public) -> FAILED: \(f.description, privacy: .public)")
        }
        return r
    }

    private static func runRaw(_ args: [String]) -> Result<Void, Failure> {
        guard isInstalled else {
            return .failure(Failure(description: L("Helper non installato: reinstalla TBPower o esegui `sudo ./install-helper.sh`.")))
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n", path] + args
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch {
            return .failure(Failure(description: LF("Impossibile avviare sudo: %@", error.localizedDescription)))
        }
        let data = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        if p.terminationStatus == 0 { return .success(()) }
        let msg = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if msg.contains("password is required") || msg.contains("a password") {
            return .failure(Failure(description: L("Regola sudoers mancante: reinstalla TBPower o esegui `sudo ./install-helper.sh`.")))
        }
        let detail = msg.isEmpty ? L("nessun messaggio") : msg
        return .failure(Failure(description: "`\(args.joined(separator: " "))` exit \(p.terminationStatus): \(detail)"))
    }
}

/// Esegue un comando di sistema non privilegiato e ne restituisce lo stdout.
func runCapture(_ path: String, _ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return "" }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: data, encoding: .utf8) ?? ""
}
