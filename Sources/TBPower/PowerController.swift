import Foundation
import SwiftUI
import ServiceManagement
import IOKit.ps
import AppKit
import CoreGraphics
import CSMC

#if !arch(arm64)
#error("TBPower AS richiede Apple Silicon")
#endif

enum Profile: String, CaseIterable, Identifiable {
    case risparmio, normale
    var id: String { rawValue }
    var title: String { self == .risparmio ? L("Risparmio") : L("Normale") }
    var buttonTitle: String { title }
    var buttonSubtitle: String? { nil }
    var lowPower: Bool { self == .risparmio }
    func detail(for hw: Hardware) -> String {
        self == .risparmio ? "Basso consumo attivo" : "Prestazioni standard Apple Silicon"
    }
}
enum PowerSource { case battery, ac }

@MainActor
final class PowerController: ObservableObject {
    let hw = Hardware.current
    @Published var sensors = SensorSnapshot()
    @Published private(set) var busy = false
    @Published var lastError: String?
    @Published var chargeLimitDraft: Double = 93
    @Published private(set) var chargePaused = false
    @Published private(set) var powerSource: PowerSource = .ac
    @Published private(set) var profile: Profile = Profile(rawValue: UserDefaults.standard.string(forKey: "profile") ?? "") ?? .normale
    @Published var autoProfile = UserDefaults.standard.bool(forKey: "autoProfile")
    @Published var batteryProfile: Profile = Profile(rawValue: UserDefaults.standard.string(forKey: "batteryProfile") ?? "") ?? .risparmio
    @Published var acProfile: Profile = Profile(rawValue: UserDefaults.standard.string(forKey: "acProfile") ?? "") ?? .normale
    @Published var amphetamine = UserDefaults.standard.bool(forKey: "amphetamine")
    @Published var lidClosedNoSleep = UserDefaults.standard.bool(forKey: "lidClosedNoSleep")
    @Published private(set) var externalDisplay = false
    @Published private(set) var macsFanControlRunning = false
    /// Altro tool che controlla la carica (es. "battery maintain 70%"): TBPower AS non interviene.
    @Published private(set) var chargeConflict: String?
    @Published private(set) var chargeError: String?
    var helperInstalled: Bool { Helper.isInstalled }
    var helperSupportsNoSleep: Bool { Helper.supports("nosleep 0|1") }
    var helperSupportsAmphetamine: Bool { Helper.supports("amphetamine 0|1") }
    var helperSupportsChargePause: Bool { Helper.supports("charge-pause 0|1") }
    var wantNoSleep: Bool { lidClosedNoSleep && externalDisplay }
    private var timer: Timer?
    private let work = DispatchQueue(label: "tbpower-as.work")
    private var refreshing = false
    private var pending = 0
    private var loadedLimit = false
    private var ticks = 0
    private var pausePending = false
    // Backoff sui fallimenti della pausa carica: niente tentativi a raffica.
    private var chargeFailures = 0
    private var nextChargeAttempt = Date.distantPast
    private var lastChargeRequest: Bool?

    init() {
        stateLog.notice("avvio TBPower AS arm64")
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in
            // Charge control continues in the LaunchDaemon; restore sleep settings on exit.
            if Helper.isInstalled {
                _ = Helper.run(["nosleep", "0"])
                _ = Helper.run(["amphetamine", "0"])
            }
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [self] in self?.refresh() }
        }
    }

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        let checkConflict = ticks % 15 == 0
        work.async {
            let s = Sensors.read()
            var ids = [CGDirectDisplayID](repeating: 0, count: 16)
            var n: UInt32 = 0
            let ext = CGGetOnlineDisplayList(16, &ids, &n) == .success && ids.prefix(Int(n)).contains { CGDisplayIsBuiltin($0) == 0 }
            let conflict: String?? = checkConflict ? .some(Helper.conflictingChargeTool()) : .none
            DispatchQueue.main.async {
                self.refreshing = false
                let first = self.ticks == 0
                let source: PowerSource = s.onAC ? .ac : .battery
                let changed = source != self.powerSource || ext != self.externalDisplay
                // Pubblica solo i cambiamenti reali: meno ridisegni SwiftUI.
                if self.sensors != s { self.sensors = s }
                if self.powerSource != source { self.powerSource = source }
                if self.externalDisplay != ext { self.externalDisplay = ext }
                let paused = s.chargePaused ?? false
                if self.chargePaused != paused { self.chargePaused = paused }
                if case .some(let c) = conflict, c != self.chargeConflict { self.chargeConflict = c }
                if !self.loadedLimit, let limit = s.chargeLimit {
                    self.loadedLimit = true
                    self.chargeLimitDraft = Double(limit)
                }
                let mfc = NSWorkspace.shared.runningApplications.contains {
                    let name = $0.localizedName ?? ""
                    return name.localizedCaseInsensitiveContains("Macs Fan Control") || name == "Stats"
                }
                if self.macsFanControlRunning != mfc { self.macsFanControlRunning = mfc }
                self.ticks += 1
                // Periodic profile repair also handles helper installation while the app is open.
                if first || changed || self.ticks % 15 == 0 {
                    if self.autoProfile { self.profile = source == .ac ? self.acProfile : self.batteryProfile }
                    if self.helperInstalled, !self.busy { self.applyCurrent() }
                }
                self.enforceChargeLimit()
            }
        }
    }

    func select(_ p: Profile) {
        autoProfile = false
        UserDefaults.standard.set(false, forKey: "autoProfile")
        profile = p
        applyCurrent()
    }
    func setAutoProfile(_ on: Bool) {
        autoProfile = on
        UserDefaults.standard.set(on, forKey: "autoProfile")
        if on { profile = powerSource == .battery ? batteryProfile : acProfile; applyCurrent() }
    }
    func setBatteryProfile(_ p: Profile) {
        batteryProfile = p; UserDefaults.standard.set(p.rawValue, forKey: "batteryProfile")
        if autoProfile && powerSource == .battery { profile = p; applyCurrent() }
    }
    func setACProfile(_ p: Profile) {
        acProfile = p; UserDefaults.standard.set(p.rawValue, forKey: "acProfile")
        if autoProfile && powerSource == .ac { profile = p; applyCurrent() }
    }
    func setLidClosedNoSleep(_ on: Bool) {
        lidClosedNoSleep = on; UserDefaults.standard.set(on, forKey: "lidClosedNoSleep")
        perform([["nosleep", wantNoSleep ? "1" : "0"]])
    }
    func setAmphetamine(_ on: Bool) {
        amphetamine = on; UserDefaults.standard.set(on, forKey: "amphetamine")
        perform([["amphetamine", on ? "1" : "0"]])
    }
    func applyCurrent() {
        UserDefaults.standard.set(profile.rawValue, forKey: "profile")
        var steps = [["nosleep", wantNoSleep ? "1" : "0"], ["amphetamine", amphetamine ? "1" : "0"]]
        if hw.lowPowerSupported { steps.insert(["lowpower", profile.lowPower ? "1" : "0"], at: 0) }
        perform(steps)
    }
    func applyChargeLimit() {
        let n = Int(chargeLimitDraft.rounded())
        guard hw.chargeLimitSupported, (50...100).contains(n) else { return }
        // charge-limit only saves config. enforce then evaluates the newly saved value.
        // Nuovo limite esplicito: azzera il backoff e riprova subito.
        chargeFailures = 0; nextChargeAttempt = .distantPast; lastChargeRequest = nil
        perform([["charge-limit", String(n)]]) { [weak self] _ in self?.enforceChargeLimit() }
    }
    private func enforceChargeLimit() {
        guard helperInstalled, hw.chargeLimitSupported, !busy, !pausePending, chargeConflict == nil,
              Date() >= nextChargeAttempt,
              let target = sensors.chargeLimit, let pct = sensors.batteryPercent,
              let paused = sensors.chargePaused else { return }
        // Never use the unsaved slider draft to control charging.
        let action = smc_charge_action(Int32(target), Int32(pct), sensors.onAC ? 1 : 0, paused ? 1 : 0)
        guard action >= 0 else { return }
        let want = action == 1
        pausePending = true
        lastChargeRequest = want
        perform([["charge-pause", want ? "1" : "0"]], refreshAfter: false) { [weak self] ok in
            guard let self = self else { return }
            self.pausePending = false
            if ok {
                self.chargeFailures = 0
                self.nextChargeAttempt = .distantPast
                if self.chargeError != nil { self.chargeError = nil }
            } else {
                // 15 s, 30 s, 60 s … fino a 5 min: un errore non deve generare un ciclo.
                self.chargeFailures += 1
                let delay = min(300.0, 15.0 * pow(2.0, Double(self.chargeFailures - 1)))
                self.nextChargeAttempt = Date().addingTimeInterval(delay)
                let msg = LF("Pausa carica non riuscita, nuovo tentativo tra %d s", Int(delay))
                if self.chargeError != msg { self.chargeError = msg }
            }
        }
    }
    private func perform(_ steps: [[String]], refreshAfter: Bool = true, completion: ((Bool) -> Void)? = nil) {
        guard helperInstalled else {
            let e = "Helper AS non installato: sudo ./install-helper.sh 93"
            if lastError != e { lastError = e }
            completion?(false); return
        }
        pending += 1; busy = true
        work.async {
            var errors: [String] = []
            for step in steps {
                if case .failure(let e) = Helper.run(step) { errors.append(e.description) }
            }
            let result = errors.joined(separator: "\n")
            let ok = errors.isEmpty
            DispatchQueue.main.async {
                self.pending -= 1
                let b = self.pending > 0
                if self.busy != b { self.busy = b }
                let e: String? = result.isEmpty ? nil : result
                if self.lastError != e { self.lastError = e }
                completion?(ok)
                if refreshAfter { self.refresh() }
            }
        }
    }
    var launchAtLogin: Bool {
        get { LoginItem.isEnabled }
        set {
            do { try LoginItem.set(newValue) } catch { lastError = error.localizedDescription }
            objectWillChange.send()
        }
    }
}
