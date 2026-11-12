import SwiftUI
import AppKit

/// Finestra Opzioni: NSWindow propria (affidabile da MenuBarExtra su macOS 13, app LSUIElement).
final class OptionsWindow {
    static let shared = OptionsWindow()
    private var window: NSWindow?

    func show(controller: PowerController) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 360),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: OptionsView().environmentObject(controller))
            w.center()
            window = w
        }
        window?.title = L("Opzioni")
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct OptionsView: View {
    @EnvironmentObject var c: PowerController
    @AppStorage(AppLanguage.key) private var language = AppLanguage.system.rawValue
    @AppStorage(BarPref.logoStyle) private var logoStyle = LogoStyle.initial
    @AppStorage(BarPref.cpuTemp) private var cpuTemp = true
    @AppStorage(BarPref.cpuUsage) private var cpuUsage = false
    @AppStorage(BarPref.ram) private var ram = false
    @AppStorage(BarPref.ramPercent) private var ramPercent = false
    @AppStorage(BarPref.gpuTemp) private var gpuTemp = false
    @AppStorage(BarPref.net) private var net = false

    var body: some View {
        Form {
            Section {
                Picker(L("Lingua"), selection: $language) {
                    ForEach(AppLanguage.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Toggle(L("Avvia al login"), isOn: Binding(get: { c.launchAtLogin }, set: { c.launchAtLogin = $0 }))
            }
            Section(L("Barra dei menu")) {
                Picker(L("Logo"), selection: $logoStyle) {
                    Text(L("Chip")).tag(LogoStyle.chip.rawValue)
                    Text(L("Mela TBP")).tag(LogoStyle.apple.rawValue)
                    Text(L("Nessuno")).tag(LogoStyle.none.rawValue)
                }
                Toggle(L("Temperatura CPU"), isOn: $cpuTemp)
                Toggle(L("Utilizzo CPU %"), isOn: $cpuUsage)
                Toggle(L("RAM usata"), isOn: $ram)
                if ram {
                    Picker(L("Mostra RAM in"), selection: $ramPercent) {
                        Text("GB").tag(false); Text("%").tag(true)
                    }.pickerStyle(.segmented).padding(.leading, 16)
                }
                Toggle(L("Temperatura GPU"), isOn: $gpuTemp)
                Toggle(L("Traffico di rete (download/upload)"), isOn: $net)
                Text(L("Se tutto è spento resta visibile la mela."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Contenuto della barra dei menu.
struct MenuBarLabel: View {
    @ObservedObject var c: PowerController
    @ObservedObject var stats: SystemStats
    @AppStorage(BarPref.logoStyle) private var logoStyle = LogoStyle.initial
    @AppStorage(BarPref.cpuTemp) private var cpuTemp = true
    @AppStorage(BarPref.cpuUsage) private var cpuUsage = false
    @AppStorage(BarPref.ram) private var ram = false
    @AppStorage(BarPref.ramPercent) private var ramPercent = false
    @AppStorage(BarPref.gpuTemp) private var gpuTemp = false
    @AppStorage(BarPref.net) private var net = false

    var body: some View {
        // MenuBarExtra mostra in modo affidabile solo un'immagine singola: componiamo
        // glifo + icona termica + testo in un'unica NSImage template (chiaro/scuro automatico).
        Image(nsImage: MenuBarLabel.render(style: LogoStyle(rawValue: logoStyle) ?? .chip,
                                           limiting: false, text: items.joined(separator: " ")))
    }

    static func render(style: LogoStyle, limiting: Bool, text: String) -> NSImage {
        var glyph: NSImage? = nil
        switch style {
        case .chip: glyph = TBPowerApp.chipGlyph
        case .apple: glyph = TBPowerApp.appleGlyph
        case .none: glyph = nil
        }
        if glyph == nil && text.isEmpty { glyph = TBPowerApp.chipGlyph ?? NSImage(systemSymbolName: "cpu", accessibilityDescription: "TBPower AS") }
        var thermo: NSImage? = nil
        if limiting, let t = NSImage(systemSymbolName: "thermometer.sun.fill", accessibilityDescription: nil) {
            thermo = t.withSymbolConfiguration(.init(pointSize: 13, weight: .regular)) ?? t
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let str = NSAttributedString(string: text, attributes: attrs)
        let ts = text.isEmpty ? .zero : str.size()
        let H: CGFloat = 22, gap: CGFloat = 4
        var w: CGFloat = 0
        for i in [glyph, thermo] { if let i = i { w += i.size.width + gap } }
        w += ts.width; if text.isEmpty && w > 0 { w -= gap }
        let img = NSImage(size: NSSize(width: max(ceil(w), 1), height: H), flipped: false) { _ in
            var x: CGFloat = 0
            for i in [glyph, thermo] {
                guard let i = i else { continue }
                i.draw(in: NSRect(x: x, y: (H - i.size.height) / 2, width: i.size.width, height: i.size.height))
                x += i.size.width + gap
            }
            if !text.isEmpty { str.draw(at: NSPoint(x: x, y: (H - ts.height) / 2)) }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = text.isEmpty ? "TBPower AS" : "TBPower AS " + text
        return img
    }

    private var items: [String] {
        var a: [String] = []
        if cpuTemp, let t = c.sensors.cpuTemp { a.append("\(Int(t.rounded()))°") }
        if cpuUsage, let u = stats.cpuPercent { a.append("\(Int(u.rounded()))%") }
        if ram {
            if ramPercent, let p = stats.ramPercent { a.append("M\(Int(p.rounded()))%") }
            else if !ramPercent, let g = stats.ramUsedGB { a.append(String(format: "%.1fG", g)) }
        }
        if gpuTemp, let t = c.sensors.gpuTemp { a.append("G\(Int(t.rounded()))°") }
        if net { a.append("↓\(SystemStats.rate(stats.downBps)) ↑\(SystemStats.rate(stats.upBps))") }
        return a
    }
}

enum LogoStyle: String {
    case chip, apple, none
    /// Default Chip; chi aveva spento il vecchio interruttore "Logo" parte da Nessuno.
    static var initial: String {
        if UserDefaults.standard.object(forKey: BarPref.logo) != nil,
           !UserDefaults.standard.bool(forKey: BarPref.logo) { return LogoStyle.none.rawValue }
        return LogoStyle.chip.rawValue
    }
}
