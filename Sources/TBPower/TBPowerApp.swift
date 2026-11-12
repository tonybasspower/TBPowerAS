import SwiftUI

@main
struct TBPowerApp: App {
    @StateObject private var controller = PowerController()
    @StateObject private var stats = SystemStats()



    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(controller)
        } label: {
            MenuBarLabel(c: controller, stats: stats)
        }
        .menuBarExtraStyle(.window)
    }

    /// Glifi template monocromatici (macOS li colora per barra chiara/scura), alti 18 pt.
    static let appleGlyph: NSImage? = glyph("MenuBarIcon")
    static let chipGlyph: NSImage? = glyph("MenuBarChip")

    private static func glyph(_ name: String) -> NSImage? {
        // Caricamento esplicito dai Resources (image(forResource:) può fallire con @2x separati).
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let img = NSImage(contentsOf: url) else {
            stateLog.error("glifo \(name, privacy: .public) mancante nel bundle")
            return nil
        }
        if let url2 = Bundle.main.url(forResource: name + "@2x", withExtension: "png"),
           let rep2 = NSImageRep(contentsOf: url2) {
            rep2.size = img.size
            img.addRepresentation(rep2)
        }
        let h: CGFloat = 18
        img.size = NSSize(width: (img.size.width / img.size.height * h).rounded(), height: h)
        img.isTemplate = true
        img.accessibilityDescription = "TBPower AS"
        return img
    }
}
