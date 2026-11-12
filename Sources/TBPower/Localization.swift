import Foundation

/// Localizzazione minima: chiave = testo italiano, dizionario inglese.
/// La lingua è in UserDefaults ("app.language": "it" | "en"); default = lingua di sistema.
enum AppLanguage: String, CaseIterable, Identifiable {
    case it, en
    var id: String { rawValue }
    var label: String { self == .it ? "Italiano" : "English" }

    static let key = "app.language"
    static var system: AppLanguage {
        (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("it") ? .it : .en
    }
    static var current: AppLanguage {
        UserDefaults.standard.string(forKey: key).flatMap(AppLanguage.init(rawValue:)) ?? system
    }
}

/// Traduce un testo italiano nella lingua corrente.
func L(_ it: String) -> String {
    AppLanguage.current == .it ? it : (english[it] ?? it)
}

/// Come L, con segnaposto in stile printf (%@, %d).
func LF(_ it: String, _ args: CVarArg...) -> String {
    String(format: L(it), arguments: args)
}

private let english: [String: String] = [
    // Intestazione, avvisi
    "Comando copiato: incollalo nel Terminale": "Command copied: paste it into Terminal",
    "Aggiorna l'helper (clic per copiare il comando)": "Update the helper (click to copy the command)",
    "Helper non installato: reinstalla TBPower (clic per i dettagli)": "Helper not installed: reinstall TBPower (click for details)",
    "Macs Fan Control attivo: può interferire": "Macs Fan Control is running: it may interfere",
    "CPU > 95 °C: ventole al massimo": "CPU > 95 °C: fans at maximum",
    "Anfetamina attiva: schermo e dischi senza stop": "Amphetamine on: display and disks stay awake",
    "Anfetamina": "Amphetamine",
    "Schermo acceso e dischi senza stop: le copie non si interrompono.": "Keeps the display on and disks from sleeping so copies don't stop.",
    // Stato
    "Ventole": "Fans",
    "Ventole (man.)": "Fans (man.)",
    "giri": "rpm",
    "Batteria": "Battery",
    "batt %@ · alim %@": "batt %@ · AC %@",
    // GPU
    "Coperchio chiuso: non andare in stop": "Lid closed: don't sleep",
    "integrata": "integrated",
    "dedicata": "discrete",
    // Profili
    "Profilo": "Profile",
    "A batteria": "On battery",
    "Profilo attivo": "Active profile",
    "Carica in pausa (limite raggiunto)": "Charging paused (limit reached)",
    "Aggiorna l'helper per la pausa carica a soglia": "Update the helper for charge-pause at limit",
    "prestazioni": "performance",
    "Normale": "Normal",
    "Con alimentatore": "On power adapter",
    "Basso consumo": "Low Power",
    "Risparmio": "Power saving",
    "Massime prestazioni": "Maximum performance",
    // Ventole
    "Auto": "Auto",
    "Automatiche": "Automatic",
    "Fisse 2800 giri": "Fixed 2800 rpm",
    "Massime": "Maximum",
    "%@ giri": "%@ rpm",
    "2800 giri": "2800 rpm",
    "Max": "Max",
    "Personale": "Custom",
    "Ventole: automatiche, fisse 2800 giri, massime o personale": "Fans: automatic, fixed 2800 rpm, maximum or custom",
    "Giri del profilo Personale (%d–%d)": "Custom profile speed (%d–%d rpm)",
    "Applica": "Apply",
    // Batteria
    "Limite di carica": "Charge limit",
    "Attuale: %@. Riapplicato a ogni avvio.": "Current: %@. Re-applied at every boot.",
    // Sezioni
    "Profilo automatico": "Automatic profile",
    "Attivo": "Enabled",
    "Cambia profilo quando colleghi o stacchi l'alimentatore.": "Switches profile when you plug or unplug the power adapter.",
    "Alimentatore": "Power adapter",
    "Regola termica": "Thermal rule",
    "Spegni sopra %d °C": "Turn off above %d °C",
    "Riaccendi sotto %d °C": "Turn back on below %d °C",
    "Info": "About",
    "Versione %@": "Version %@",
    "Sito del progetto": "Project website",
    "Offrimi un caffè": "Buy me a coffee",
    "Supporta il progetto": "Support the project",
    "Disinstalla…": "Uninstall…",
    "Comando di disinstallazione copiato: incollalo nel Terminale": "Uninstall command copied: paste it into Terminal",
    // Piede
    "Avvia al login": "Launch at login",
    "Esci": "Quit",
    "Lingua": "Language",
    "Opzioni": "Options",
    "Barra dei menu": "Menu bar",
    "Logo (mela TBP)": "Logo (TBP apple)",
    "Mela TBP": "TBP apple",
    "Nessuno": "None",
    "Temperatura CPU": "CPU temperature",
    "Utilizzo CPU %": "CPU usage %",
    "RAM usata": "RAM used",
    "Mostra RAM in": "Show RAM as",
    "Temperatura GPU": "GPU temperature",
    "Traffico di rete (download/upload)": "Network traffic (download/upload)",
    "Se tutto è spento resta visibile la mela.": "If everything is off, the apple stays visible.",
    // Errori
    "Helper non installato: reinstalla TBPower o esegui `sudo ./install-helper.sh`.": "Helper not installed: reinstall TBPower or run `sudo ./install-helper.sh`.",
    "Regola sudoers mancante: reinstalla TBPower o esegui `sudo ./install-helper.sh`.": "Missing sudoers rule: reinstall TBPower or run `sudo ./install-helper.sh`.",
    "Impossibile avviare sudo: %@": "Cannot start sudo: %@",
    "nessun messaggio": "no message",
    "Stato non applicato: %@ (nuovo tentativo tra %d s)": "State not applied: %@ (retrying in %d s)",
    "Avvio al login: %@": "Launch at login: %@",
]

/// Metadati mostrati nel pannello Info.
enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
    /// Repo pubblico.
    static let projectURLString = "https://github.com/tonybasspower/TBPowerAS"
    /// Donazione PayPal “Offrimi un caffè” (€2).
    static let donationURLString = "https://paypal.me/tonybasspower/2EUR"
    static var projectURL: URL? { projectURLString.isEmpty ? nil : URL(string: projectURLString) }
    static var donationURL: URL? { donationURLString.isEmpty ? nil : URL(string: donationURLString) }
}
