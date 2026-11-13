import SwiftUI
import AppKit
import Combine
import ServiceManagement

// Compatibilità: TBPower AS gira da macOS 11 Big Sur in poi e si compila con Swift 5.5+.
// Su macOS 13+ usa MenuBarExtra (SwiftUI); su macOS 11/12 una NSStatusItem con popover.

extension View {
    /// `.formStyle(.grouped)` esiste solo da macOS 13 (e nell'SDK di Swift 5.7+).
    @ViewBuilder func groupedFormStyle() -> some View {
        #if compiler(>=5.7)
        if #available(macOS 13.0, *) { self.formStyle(.grouped) } else { self.padding(12) }
        #else
        self.padding(12)
        #endif
    }

    /// `.tint` esiste da macOS 12; su macOS 11 si usa `accentColor`.
    @ViewBuilder func tintCompat(_ color: Color) -> some View {
        if #available(macOS 12.0, *) { self.tint(color) } else { self.accentColor(color) }
    }
}

@main
enum TBPowerMain {
    static func main() {
        // TBPOWER_LEGACY_UI=1 forza la barra "classica" anche su macOS 13+ (per test).
        let forceLegacy = ProcessInfo.processInfo.environment["TBPOWER_LEGACY_UI"] == "1"
        #if compiler(>=5.7)
        if #available(macOS 13.0, *), !forceLegacy {
            TBPowerApp.main()
            return
        }
        #endif
        do {
            let app = NSApplication.shared
            let delegate = LegacyStatusApp()
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            withExtendedLifetime(delegate) { app.run() }
        }
    }
}

/// Barra dei menu per macOS 11/12 (MenuBarExtra non esiste): NSStatusItem + NSPopover
/// con lo stesso MenuView SwiftUI e la stessa icona di MenuBarLabel.
@MainActor
final class LegacyStatusApp: NSObject, NSApplicationDelegate {
    private var controller: PowerController!
    private var stats: SystemStats!
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var hosting: NSHostingController<AnyView>!
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = PowerController()
        stats = SystemStats()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        hosting = NSHostingController(rootView: AnyView(MenuView().environmentObject(controller)))
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = hosting
        updateIcon()
        // objectWillChange arriva PRIMA del cambiamento: aggiorna al giro successivo del run loop.
        controller.objectWillChange.merge(with: stats.objectWillChange)
            .merge(with: NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).map { _ in () })
            .throttle(for: .milliseconds(300), scheduler: RunLoop.main, latest: true)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateIcon()
                if self.popover.isShown { self.fitPopover() }
            }
            .store(in: &bag)
    }

    private func updateIcon() {
        item.button?.image = MenuBarLabel.image(c: controller, stats: stats)
    }

    private func fitPopover() {
        hosting.view.layoutSubtreeIfNeeded()
        let size = hosting.view.fittingSize
        if size.width > 0, size.height > 0, size != popover.contentSize { popover.contentSize = size }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            fitPopover()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

/// Avvio al login: SMAppService su macOS 13+, LaunchAgent utente su macOS 11/12.
enum LoginItem {
    private static let label = "com.tbp.tbpower-as.login"
    private static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return FileManager.default.fileExists(atPath: agentURL.path)
    }

    static func set(_ on: Bool) throws {
        if #available(macOS 13.0, *) {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return
        }
        if on {
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath],
                "RunAtLoad": true,
            ]
            try FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: agentURL)
        } else if FileManager.default.fileExists(atPath: agentURL.path) {
            try FileManager.default.removeItem(at: agentURL)
        }
    }
}
