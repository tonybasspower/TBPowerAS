# TBPower AS

**Italiano** | [English](README.en.md)

**TBPower AS** è un'app per la barra dei menu di macOS per i Mac **Apple Silicon**
(M1, M2, M3, M4…): profili energetici, profilo automatico, **Anfetamina**, temperature,
ventole (in lettura) e soprattutto un **limite di carica della batteria** che funziona
anche ad app chiusa.

> 💻 **Hai un MacBook Pro Intel?** Usa il repo fratello
> **[TBPower (Intel)](https://github.com/tonybasspower/TBPower)**: turbo, GPU Radeon, ventole manuali.
> Le due app sono separate e non vanno mescolate.


---

## Indice

1. [Funzioni](#funzioni)
2. [Come funziona il limite di carica](#come-funziona-il-limite-di-carica)
3. [Requisiti](#requisiti) · [Compatibilità](#compatibilità)
4. [Scaricare e compilare](#scaricare-e-compilare)
5. [Installazione (helper, una sola volta con sudo)](#installazione)
6. [Avvio](#avvio)
7. [Il menu, voce per voce](#il-menu-voce-per-voce)
8. [Disinstallazione completa](#disinstallazione-completa)
9. [Risoluzione problemi](#risoluzione-problemi)
10. [Sicurezza: cosa fa come root](#sicurezza-cosa-fa-come-root)
11. [Donazione](#donazione)
12. [Licenza e crediti](#licenza-e-crediti)

---

## Funzioni

| Funzione | Note |
|---|---|
| **Profili Risparmio / Normale** | Risparmio = *Modalità basso consumo* (`pmset lowpowermode 1`); Normale = `lowpowermode 0` |
| **Profilo automatico** | Profilo diverso a batteria e con alimentatore, cambio automatico quando colleghi/stacchi |
| **Anfetamina** | Schermo e dischi senza stop (copie lunghe, download); ripristina i timer `pmset` quando la spegni o esci |
| **Coperchio chiuso: non andare in stop** | Solo con monitor esterno collegato (`pmset disablesleep`) |
| **Temperature** | CPU (max di `Tp01/Tp05/Tp09/Tp0D`, fallback `Tp0T`), GPU (`Tg05/Tg0D`), batteria (`TB0T/TB1T/TB2T`) |
| **Ventole in sola lettura** | Giri attuali dalle chiavi SMC `F0Ac/F1Ac`; **nessuna** scrittura sulle ventole |
| **Limite di carica** 50–100 % | Inibizione carica via SMC `CHTE` (fallback `CH0B`/`CH0C`), isteresi 2 %, daemon ogni 15 s |
| **Rilevamento conflitti** | Se gira `battery maintain` (actuallymentor) TBPower AS non tocca la carica e lo segnala |
| **Barra dei menu** | Logo, temp. CPU, CPU %, RAM, temp. GPU, traffico di rete (Opzioni ⚙︎) |
| **Italiano / English**, avvio al login | Nessuna password dopo l'installazione |

Su Apple Silicon **non** ci sono Turbo Boost né GPU commutabile: per questo mancano i
profili "turbo" e "Massime" della versione Intel (sull'M1 Pro 14" macOS non espone
`highpowermode`).

Testata su **MacBook Pro 14" M1 Pro (MacBookPro18,3)** con **macOS 15.3.1**.
Altri modelli/firmware dovrebbero funzionare, ma lo SMC non è documentato da Apple:
verifica sempre che la carica si fermi davvero (vedi sotto).

## Come funziona il limite di carica

Su Apple Silicon la vecchia chiave `BCLM` non esiste. TBPower AS **blocca la carica**
(inibizione SMC) quando arrivi al limite e la **riabilita** quando scendi di 2 punti:

- percentuale ≥ limite **e** alimentatore collegato → carica **inibita** (resti alimentato dalla presa, la batteria non sale);
- percentuale ≤ limite − 2 → carica **riabilitata** (es. limite 80: si ferma a 80, riparte a 78);
- limite 100 % oppure alimentatore scollegato → l'inibizione viene sempre tolta;
- non forza mai la scarica e non spegne l'alimentatore.

Chiavi SMC, scelte **in base a quali esistono** (non alla versione di macOS):

1. **`CHTE`** (`ui32`, 4 byte): pausa `01 00 00 00`, ripresa `00 00 00 00`. Preferita: sull'M1 Pro con
   macOS 15.3 è l'unica che ferma davvero la carica.
2. **`CH0B` + `CH0C`** (`hex_`, 1 byte): pausa `02`, ripresa `00` su entrambe. Fallback per firmware più vecchi.
3. Nessuna delle due con tipo/dimensione attesi → **nessuna scrittura**.

Ogni scrittura viene **riletta**; se non "attecchisce" (errore `-15`) l'helper prova a riabilitare la carica
(*fail-open*) e segnala l'errore.

Chi applica la regola:
- **l'app**, mentre è aperta, controlla ogni ~2 secondi;
- il **LaunchDaemon** `com.tbp.tbpower-as.chargelimit` esegue `tbpower-as-helper enforce`
  **all'avvio e ogni 15 secondi**, anche ad app chiusa e prima del login.

## Requisiti

- Mac **Apple Silicon** (arm64), macOS **11 Big Sur o successivo** (vedi [Compatibilità](#compatibilità)).
- **Command Line Tools** di Xcode (Swift 5.5+; provata con 6.1.2). Xcode completo **non** serve:
  ```sh
  xcode-select --install
  ```
- Un account amministratore (serve `sudo` **una sola volta** per l'helper).
- **Nessun altro limitatore di carica attivo** (battery, AlDente, batt…): vedi [Risoluzione problemi](#risoluzione-problemi).

## Compatibilità

TBPower AS rileva l'hardware **all'avvio** e nasconde ciò che il Mac non ha: niente crash, niente
tentativi ripetuti. Tutti i Mac **Apple Silicon** (M1, M2, M3, M4 e varianti Pro/Max/Ultra) con
macOS **11 Big Sur o successivo**.

| Funzione | Dove funziona | Se manca |
|---|---|---|
| Barra dei menu | macOS 13+ con `MenuBarExtra`; macOS 11–12 con icona classica + popover | — |
| Avvio al login | macOS 13+ `SMAppService`; macOS 11–12 LaunchAgent utente (`~/Library/LaunchAgents/com.tbp.tbpower-as.login.plist`) | — |
| Limite di carica (pausa a soglia) | SMC con `CHTE` (firmware recenti, preferita) oppure `CH0B`/`CH0C` (firmware più vecchi) | Riga *Limite di carica non supportato su questo Mac* |
| Ventole (sola lettura, 2 righe in barra) | Mac con ventole (`FNum` > 0): MacBook Pro, Mac mini, iMac, Mac Studio | Sezione e opzioni nascoste (MacBook Air fanless) |
| Temperature CPU/GPU | Chiavi SMC per M1 (`Tp0x`/`Tg0x`), M2 (`Tp1x`, `Tg0f/j`), M3 (`Te0x`/`Tf0x`, `Tf1x/2x`), M4 (`Te0x`/`Tp0x`, `Tg0x/1x`): si usa la più calda | Mostra "—" |
| Basso consumo (`lowpowermode`) | macOS 12+ (Mac che lo espongono in `pmset`) | Ignorato dai profili |
| Anfetamina, profilo automatico, statistiche | Tutti | — |

Provata su **MacBook Pro 14" M1 Pro** (macOS 15.3.1, Swift 6.1.2), anche con l'interfaccia macOS 11/12
forzata via `TBPOWER_LEGACY_UI=1`. M2/M3/M4, MacBook Air e macOS 11/12 reali: supportati dal
rilevamento ma non ancora provati su quelle macchine.

## Scaricare e compilare

Clona nella cartella Inizio (`~/TBPowerAS`): è il percorso che l'app suggerisce quando c'è da aggiornare l'helper.

```sh
cd ~
git clone https://github.com/tonybasspower/TBPowerAS.git
cd TBPowerAS
./build-app.sh            # come utente normale, NON con sudo
```

In alternativa: *Code › Download ZIP* su GitHub, estrai in `~/TBPowerAS` ed entra nella cartella dal Terminale.

`build-app.sh` compila **solo arm64** con `clang` + `swiftc` (senza SwiftPM, così funziona anche con
Command Line Tools "difficili"), crea l'icona e firma ad-hoc. Risultato:

- `build/TBPower AS.app` — l'app (eseguibile `TBPowerAS`, bundle id `com.tbp.tbpower-as`)
- `build/tbpower-as-helper` — l'helper root

Test opzionale del protocollo di carica (mock, nessun accesso all'hardware):

```sh
cc -Wall -Wextra -Werror -I Sources/CSMC/include Sources/CSMC/charge.c tests/charge-test.c -o /tmp/charge-test
/tmp/charge-test
```

Diagnostica senza sudo e senza scritture:

```sh
./build/tbpower-as-helper charge-supported && echo "SMC carica supportato"
./build/tbpower-as-helper status        # backend=2 (CHTE) | 1 (CH0B/CH0C) | 0, conflict, paused, limit
```

## Installazione

```sh
sudo ./install-helper.sh 80     # 80 = limite di carica in % (50–100, default 93)
```

Cosa fa, nell'ordine:

| Passo | Cosa | Percorso |
|---|---|---|
| 1 | Controlla: root, Mac Apple Silicon, utente normale, limite 50–100, helper arm64 già compilato | — |
| 2 | Cartella di supporto (root:wheel 755) | `/Library/Application Support/TBPowerAS/` |
| 3 | Ferma solo il **proprio** daemon (se c'era) | — |
| 4 | Helper root (root:wheel 755) e script di disinstallazione | `…/TBPowerAS/tbpower-as-helper`, `…/TBPowerAS/uninstall.sh` |
| 5 | Verifica che lo SMC supporti l'inibizione carica (altrimenti si ferma **senza** creare la regola sudo) | — |
| 6 | Regola sudo **solo per l'helper**, senza password | `/etc/sudoers.d/tbpower-as` |
| 7 | Salva il limite **solo alla prima installazione** (poi lo cambi dall'app) | `…/TBPowerAS/config` (`charge_limit=80`) |
| 8 | `reapply`: riabilita la carica (stato pulito) | — |
| 9 | LaunchDaemon (avvio + ogni 15 s) | `/Library/LaunchDaemons/com.tbp.tbpower-as.chargelimit.plist`, log `/var/log/tbpower-as-chargelimit.log` |
| 10 | L'app | `/Applications/TBPower AS.app` |

Non installa né rimuove nient'altro (nessuna migrazione da altre app). Per aggiornare: `git pull`,
`./build-app.sh`, poi di nuovo `sudo ./install-helper.sh <limite>`.

Verifica:

```sh
"/Library/Application Support/TBPowerAS/tbpower-as-helper" status
cat "/Library/Application Support/TBPowerAS/config"
sudo launchctl print system/com.tbp.tbpower-as.chargelimit | head
```

Archivio locale opzionale: `./package.sh` → `dist/TBPowerAS-arm64.tar.gz` (non pubblica nulla).

## Avvio

```sh
open "/Applications/TBPower AS.app"
```

L'icona compare nella barra dei menu (niente Dock). Per l'avvio automatico: **Opzioni ⚙︎ › Avvia al login**.

**Prova consigliata**: imposta un limite *sotto* la carica attuale (es. batteria all'88 % → limite 80),
lascia l'alimentatore collegato e controlla che nel menu compaia *Inibizione carica SMC attiva* e che in
*Impostazioni › Batteria* la batteria non stia caricando. `status` deve mostrare `paused=1`.

## Il menu, voce per voce

**Intestazione e avvisi**
- *Aggiorna l'helper* — clic per copiare `cd ~/TBPowerAS && sudo ./install-helper.sh 93` (cambia il numero se vuoi).
- *Stats / controllo ventole attivo* — un'altra app che gestisce ventole/sensori potrebbe interferire.
- *Anfetamina attiva* — promemoria.
- Riga sensori: temperatura CPU, GPU, batteria e giri ventole.

**Anfetamina** — schermo acceso e dischi senza stop; spegnendola (o uscendo) tornano i timer di prima.

**Coperchio chiuso: non andare in stop** — con monitor esterno il Mac resta sveglio a coperchio chiuso.

**Profilo attivo** — *Risparmio* (basso consumo) / *Normale*; sotto vedi se sei *A batteria* o *Con alimentatore*.

**Profilo automatico** — *Attivo* + profilo per **Batteria** e per **Alimentatore**
(default: Risparmio a batteria, Normale con alimentatore).

**Ventole** — giri attuali, sola lettura.

**Batteria › Limite di carica** — cursore 50–100 % e *Applica* (il cursore da solo non cambia nulla).
- *Inibizione carica SMC attiva* = carica ferma al limite.
- *Carica gestita da un altro tool (battery maintain …)* = TBPower AS non interviene finché quel tool è attivo.
- Eventuali errori dell'helper; dopo un errore l'app riprova con attese crescenti (fino a 5 minuti), senza bloccarsi.

**Info** — versione, licenza, *Sito del progetto*, *☕ Offrimi un caffè*.

**Piede** — ⚙︎ *Opzioni* (lingua, avvio al login, cosa mostrare nella barra: logo chip / mela TBP / nessuno,
temp. CPU, CPU %, RAM in GB o %, temp. GPU, rete e, sui Mac con ventole, *Velocità ventole sotto la
temperatura CPU* — due righe compatte tipo `62°` / `2400 rpm`, ventola più veloce, spenta di default) ed *Esci*. Uscendo, stop e Anfetamina tornano normali;
il limite di carica resta attivo grazie al daemon.

## Disinstallazione completa

1. Nel Terminale:
   ```sh
   sudo "/Library/Application Support/TBPowerAS/uninstall.sh"
   ```
   oppure, dalla cartella del repo: `sudo ./Support/uninstall.sh`.

   Lo script chiude l'app, ferma e rimuove il LaunchDaemon (e il log), **riabilita la carica**
   (`charge-pause 0`), rimette stop normale e Anfetamina off, poi cancella `/etc/sudoers.d/tbpower-as`,
   `/Applications/TBPower AS.app` e `/Library/Application Support/TBPowerAS/`.
2. Se usavi *Risparmio*: `sudo pmset -a lowpowermode 0`.
3. Opzionale, preferenze: `defaults delete com.tbp.tbpower-as`.
4. Togli TBPower AS da *Impostazioni di Sistema › Generali › Elementi di login* se è ancora lì.

Manuale (se lo script non c'è):
```sh
sudo launchctl bootout system/com.tbp.tbpower-as.chargelimit
sudo "/Library/Application Support/TBPowerAS/tbpower-as-helper" charge-pause 0
sudo rm -f /Library/LaunchDaemons/com.tbp.tbpower-as.chargelimit.plist /etc/sudoers.d/tbpower-as
sudo rm -rf "/Applications/TBPower AS.app" "/Library/Application Support/TBPowerAS"
```

## Risoluzione problemi

**La carica è ferma e voglio farla ripartire subito**
```sh
sudo "/Library/Application Support/TBPowerAS/tbpower-as-helper" charge-pause 0
```
Il daemon però riapplica il limite entro 15 s. Per togliere il limite del tutto:
```sh
sudo "/Library/Application Support/TBPowerAS/tbpower-as-helper" charge-limit 100
```
(oppure 100 % dall'app). Senza daemon nessuno inibisce la carica: lo script di disinstallazione
esegue comunque `charge-pause 0` prima di rimuovere l'helper.

**Conflitto con `battery` (actuallymentor)** — se il menu dice *Carica gestita da un altro tool*,
`battery maintain` è attivo e scrive le stesse chiavi. Fermalo e disinstallalo:
```sh
battery maintain stop
battery uninstall
```
**AlDente / batt / altri limitatori** — esci dall'app e disinstallala (compreso il suo helper): due
programmi che inibiscono la carica si contendono le stesse chiavi SMC.

**La batteria non sale ma TBPower AS non è in pausa** (`status` → `paused=0`) — è macOS. Controlla:
```sh
ioreg -rn AppleSmartBattery | grep -E '"NotChargingReason"|"ChargerInhibitReason"|"MaxCapacity"|"CurrentCapacity"'
```
`ChargerInhibitReason` è l'inibizione impostata da TBPower AS; un `NotChargingReason` diverso da 0 con
`ChargerInhibitReason` a 0 indica che è il sistema a non caricare: **Carica ottimizzata** /
*Gestione salute batteria* (Impostazioni › Batteria › ⓘ), batteria calda, alimentatore debole.
Se vuoi che decida solo TBPower AS, disattiva *Carica ottimizzata*.

**Errore `-15` / `inibizione carica fallita`** — il firmware ignora la chiave scelta. Aggiorna all'ultima
versione (CHTE ha la precedenza) e reinstalla l'helper. Se persiste, apri una issue con l'output di `status`.

**`SMC carica non supportato`** durante l'installazione — questo modello/firmware non espone né `CHTE`
né `CH0B/CH0C`: il limite di carica non è disponibile (la regola sudo non viene creata).

**L'app non risponde / CPU alta** — chiudila con `killall TBPowerAS`, aggiorna e reinstalla.

**macOS blocca l'app** — è firmata ad-hoc. Se l'hai compilata tu di solito non succede; altrimenti
clic destro › Apri oppure `xattr -dr com.apple.quarantine "/Applications/TBPower AS.app"`.

**Log** — `/var/log/tbpower-as-chargelimit.log` (il codice di uscita 2 = conflitto con `battery maintain`).

## Sicurezza: cosa fa come root

- L'app gira **come utente normale**. Le azioni privilegiate passano da
  `/Library/Application Support/TBPowerAS/tbpower-as-helper` (root:wheel 755).
- `/etc/sudoers.d/tbpower-as` consente **solo quel binario** senza password (regola verificata con `visudo`).
- Comandi ammessi (lista chiusa, argomenti validati, altrimenti codice 64):
  `charge-limit <50-100>` (salva solo il config), `charge-pause 0|1`, `lowpower 0|1`, `nosleep 0|1`,
  `amphetamine 0|1`, `enforce`, `reapply` (riabilita la carica), e in sola lettura anche senza sudo
  `charge-supported`, `status`.
- **Nessun comando per le ventole**, nessun kext, nessuna scarica forzata.
- Le scritture SMC riguardano **solo** l'inibizione carica (`CHTE` o `CH0B/CH0C`), con rilettura e
  ripristino *fail-open*; app e daemon sono serializzati da un lock (`helper.lock`).
- Esegue solo `/usr/bin/pmset` e `/usr/bin/pgrep` con percorso assoluto, senza shell, ambiente ripulito.
- Nessuna rete, nessuna telemetria.
- **Usala a tuo rischio**: lo SMC non è documentato da Apple e può cambiare con gli aggiornamenti.

## Donazione

TBPower AS è gratuita. Se ti è utile, offrimi un caffè:

**[☕ Offrimi un caffè (2 €)](https://paypal.me/tonybasspower/2EUR)**

## Licenza e crediti

- TBPower AS: **MIT** — © 2026 Tony Basspower, vedi [`LICENSE`](LICENSE) (stessa licenza di TBPower Intel).
- Protocollo SMC di carica implementato in modo indipendente verificando i valori pubblici di
  [charlie0129/batt](https://github.com/charlie0129/batt) (GPL-2.0, **nessun codice copiato**) e
  [actuallymentor/battery](https://github.com/actuallymentor/battery) (MIT). Vedi
  [`Support/Licenses/THIRD-PARTY-NOTICES.md`](Support/Licenses/THIRD-PARTY-NOTICES.md).
- Dati del probe hardware: [`docs/probe-M1Pro.md`](docs/probe-M1Pro.md).
- Non affiliato ad Apple. *Apple Silicon, Mac e macOS sono marchi di Apple Inc.*
- Versione Intel: **[TBPower](https://github.com/tonybasspower/TBPower)**.
