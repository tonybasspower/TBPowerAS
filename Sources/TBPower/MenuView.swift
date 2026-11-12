import SwiftUI
import AppKit

/// Menu compatto: larghezza fissa 360 pt, padding uniforme 12 pt, sezioni secondarie richiudibili.
struct MenuView: View {
    @EnvironmentObject var c: PowerController
    @AppStorage("ui.openInfo") private var openInfo = false
    @AppStorage(AppLanguage.key) private var language = AppLanguage.system.rawValue
    @State private var copied = false

    static let width: CGFloat = 360
    static var installCmd: String { "cd ~/TBPowerAS && sudo ./install-helper.sh 93" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            warnings
            amphetamineBox
            statusRow
            bigToggle(L("Coperchio chiuso: non andare in stop"), "laptopcomputer", .subheadline,
                      Binding(get: { c.lidClosedNoSleep }, set: { c.setLidClosedNoSleep($0) }))
                .disabled(c.busy || !c.helperInstalled)
            Text("Solo con monitor esterno collegato.").font(.caption2).foregroundStyle(.secondary)
            profiles
            if c.hw.fanCount > 0 {
                Divider()
                HStack {
                    Label(L("Ventole"), systemImage: "fanblades").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(c.sensors.fans.isEmpty ? "—" : c.sensors.fans.map { "\($0)" }.joined(separator: " / ") + " " + L("giri"))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text("Ventole in sola lettura: controllo manuale non ancora verificato.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if c.hw.chargeLimitSupported {
                Divider()
                Label(L("Batteria"), systemImage: "battery.100.bolt").font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    Text(L("Limite di carica")).font(.caption)
                    chargeControls
                }
            }
            Divider()
            section(L("Info"), "info.circle", $openInfo) { infoControls }
            if let e = c.lastError {
                Text(e).font(.caption2).foregroundStyle(.orange).lineLimit(2)
                    .help(e)
            }
            Divider()
            footer
        }
        .padding(12)
        .frame(width: Self.width, alignment: .leading)
    }

    // MARK: Intestazione e stato

    private var header: some View {
        HStack(spacing: 6) {
            Text("TBPower AS").font(.headline)
            Spacer(minLength: 0)
            if c.busy { ProgressView().controlSize(.small) }
            if let p = c.sensors.batteryPercent {
                Label("\(p)%", systemImage: c.sensors.onAC ? "powerplug.fill" : "battery.75")
                    .font(.caption)
            }
        }
    }

    /// Avvisi in un'unica riga; clic = copia il comando di aggiornamento dell'helper.
    @ViewBuilder private var warnings: some View {
        let needHelper = !c.helperInstalled
            || (c.lidClosedNoSleep && !c.helperSupportsNoSleep)
            || (c.amphetamine && !c.helperSupportsAmphetamine)
        if needHelper {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Self.installCmd, forType: .string)
                copied = true
            } label: {
                Label(copied ? L("Comando copiato: incollalo nel Terminale") : L("Aggiorna l'helper (clic per copiare il comando)"),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).lineLimit(1)
            }
            .buttonStyle(.plain).foregroundStyle(.orange)
            .help(Self.installCmd)
        }
        if c.macsFanControlRunning {
            Label(L("Stats / controllo ventole attivo: può interferire"), systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange).lineLimit(1)
        }
        if c.amphetamine {
            Label(L("Anfetamina attiva: schermo e dischi senza stop"), systemImage: "pills.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(.pink).lineLimit(1)
        }
    }

    private var statusRow: some View {
        HStack(spacing: 12) {
            iconStat("thermometer.medium", "CPU", c.sensors.cpuTemp.map { "\(Int($0.rounded()))°" })
            if c.sensors.gpuTemp != nil {
                iconStat("thermometer.medium", "GPU", c.sensors.gpuTemp.map { "\(Int($0.rounded()))°" })
            }
            if c.hw.fanCount > 0 {
                iconStat("fanblades",
                         c.sensors.fanManual.contains(true) ? L("Ventole (man.)") : L("Ventole"),
                         c.sensors.fans.isEmpty ? nil : c.sensors.fans.map(String.init).joined(separator: "/"))
            }
            if let t = c.sensors.batteryTemp {
                iconStat("battery.50", L("Batteria"), "\(Int(t.rounded()))°")
            }
            Spacer(minLength: 0)
        }
        .help(c.sensors.activeGPU ?? "Apple Silicon")
    }

    // MARK: Anfetamina

    private var amphetamineBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            bigToggle(L("Anfetamina"), "pills.fill", .headline,
                      Binding(get: { c.amphetamine }, set: { c.setAmphetamine($0) }))
            Text(L("Schermo acceso e dischi senza stop: le copie non si interrompono."))
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(c.busy || !c.helperInstalled)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(c.amphetamine ? Color.pink.opacity(0.18) : Color.secondary.opacity(0.08)))
    }

    private func bigToggle(_ title: String, _ icon: String, _ font: Font, _ b: Binding<Bool>) -> some View {
        Toggle(isOn: b) {
            Label(title, systemImage: icon).font(font)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
    }

    // MARK: Profilo (sempre visibile)

    private var profiles: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("Profilo attivo")).font(.subheadline.weight(.semibold))
                if c.autoProfile { badge("AUTO", .accentColor) }
                Spacer()
                Label(c.powerSource == .battery ? L("A batteria") : L("Con alimentatore"),
                      systemImage: c.powerSource == .battery ? "battery.75" : "powerplug.fill")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                ForEach(Profile.allCases) { p in
                    Button { c.select(p) } label: {
                        VStack(spacing: 1) {
                            Text(p.buttonTitle)
                                .font(.caption2.weight(c.profile == p ? .semibold : .regular))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                            if let sub = p.buttonSubtitle {
                                Text(sub)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(c.profile == p ? .accentColor : .gray)
                    .disabled(c.busy || !c.helperInstalled)
                    .help(p.detail(for: c.hw))
                }
            }
            autoBlock
        }
    }

    /// Profilo automatico sempre sotto i pulsanti (non più sezioni richiudibile).
    private var autoBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(L("Profilo automatico"), systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                toggle(L("Attivo"), Binding(get: { c.autoProfile }, set: { c.setAutoProfile($0) }),
                       help: L("Cambia profilo quando colleghi o stacchi l'alimentatore."))
            }
            if c.autoProfile {
                Picker(L("Batteria"), selection: Binding(get: { c.batteryProfile }, set: { c.setBatteryProfile($0) })) {
                    ForEach(Profile.allCases) { Text($0.title).tag($0) }
                }.font(.caption)
                Picker(L("Alimentatore"), selection: Binding(get: { c.acProfile }, set: { c.setACProfile($0) })) {
                    ForEach(Profile.allCases) { Text($0.title).tag($0) }
                }.font(.caption)
            }
        }
        .disabled(!c.helperInstalled)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }

    // MARK: Sezioni richiudibili

    private func section<Content: View>(_ title: String, _ icon: String, _ open: Binding<Bool>,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        let inner = content()
        return DisclosureGroup(isExpanded: open) {
            VStack(alignment: .leading, spacing: 4) { inner }
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(title, systemImage: icon).font(.subheadline)
        }
    }

    private var chargeControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Slider(value: $c.chargeLimitDraft, in: 50...100, step: 1)
                Text("\(Int(c.chargeLimitDraft))%").font(.caption.monospacedDigit()).frame(width: 34)
                Button(L("Applica")) { c.applyChargeLimit() }.controlSize(.small)
                    .disabled(c.busy || !c.helperInstalled)
            }
            if let conflict = c.chargeConflict {
                Text(LF("Carica gestita da un altro tool (%@): TBPower AS non interviene. Disattivalo per usare questo limite.", conflict))
                    .font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            } else if let e = c.chargeError {
                Text(e).font(.caption2).foregroundStyle(.orange)
            }
            if c.chargePaused {
                Label(L("Inibizione carica SMC attiva"), systemImage: "pause.circle.fill")
                    .font(.caption2).foregroundStyle(.orange)
            } else if !c.helperSupportsChargePause, c.helperInstalled {
                Text(L("Aggiorna l'helper per la pausa carica a soglia"))
                    .font(.caption2).foregroundStyle(.orange)
            }
        }
        .help(LF("Limite %d%%. Inibizione SMC a soglia; ripresa sotto limite−2. Controllo anche senza app tramite daemon.", Int(c.chargeLimitDraft)))
    }

    // MARK: Piede

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button { OptionsWindow.shared.show(controller: c) } label: {
                Image(systemName: "gearshape")
            }
            .controlSize(.small).help(L("Opzioni"))
            Button(L("Esci")) { NSApplication.shared.terminate(nil) }.controlSize(.small)
        }
    }

    private var infoControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LF("Versione %@", AppInfo.version)).font(.caption)
            Text(L("Licenza MIT · Apple Silicon · ventole in sola lettura"))
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                if let u = AppInfo.projectURL { Link(L("Sito del progetto"), destination: u).font(.caption) }
                if let u = AppInfo.donationURL { Link(L("Offrimi un caffè"), destination: u).font(.caption) }
            }

        }
    }

    // MARK: Utilità

    private func toggle(_ title: String, _ b: Binding<Bool>, help: String) -> some View {
        Toggle(isOn: b) { Text(title).font(.caption) }
            .toggleStyle(.switch).controlSize(.mini)
            .help(help)
    }

    private func stat(_ k: String, _ v: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(k).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Text(v ?? "—").font(.caption.monospacedDigit()).lineLimit(1)
        }
    }

    private func iconStat(_ icon: String, _ k: String, _ v: String?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 0) {
                Text(k).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Text(v ?? "—").font(.caption.monospacedDigit()).lineLimit(1)
            }
        }
    }

    private func badge(_ t: String, _ color: Color) -> some View {
        Text(t).font(.caption2.weight(.bold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.2)))
    }

}
