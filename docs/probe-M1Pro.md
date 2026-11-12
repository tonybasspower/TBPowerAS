# Probe M1 Pro, 6 novembre 2026 (Europe/Rome)

**Italiano** | [English](#english)

Target: MacBookPro18,3, Apple M1 Pro 14", arm64, macOS 15.3.1.
Tool di probe indipendente (non incluso), compilato con clang e lo stesso client SMC `smc.c`.
Solo smc_open / smc_read / smc_read_number / smc_close; nessuna invocazione write.

| Chiave | Tipo/dimensione | Risultato |
|---|---|---|
| FNum | ui8 / 1 | 2 |
| F0Ac / F1Ac | flt / 4 LE | 0 / 0 RPM |
| F0Mn / F1Mn | flt / 4 LE | 1200 / 1200 RPM |
| F0Mx / F1Mx | flt / 4 LE | 5779 / 6241 RPM |
| F0Md / F1Md | ui8 / 1 | 0 / 0 (auto) |
| F0Tg / F1Tg | flt / 4 LE | 0 / 0 |
| Ftst | — | assente (-11) |
| CH0B / CH0C | hex_ / 1 | raw 00 / 00 |
| CHTE | ui32 / 4 | raw 01000000; decoder SMC convenzionale 16777216 |
| CHWA | — | assente (-11) |
| BCLM | — | assente (-11), solo probe, non usato dall'app AS |
| ACLC | ui8 / 1 | raw 03 |
| CH0I | ui8 / 1 | raw 00 |
| TB0T / TB1T / TB2T | flt / 4 LE | 26.0 / 26.0 / 25.8 °C |
| Tp01 / Tp05 / Tp09 / Tp0D | flt / 4 LE | circa 47.7 / 46.7 / 45.8 / 45.0 °C |
| Tg05 / Tg0D | flt / 4 LE | circa 45.2 / 44.8 °C |

Altre chiavi termiche leggibili: Tp00/02/04/06/08/0A/0C/0E, Tg04/0C.
Sono stati sondati Tp00..Tp3F e Tg00..Tg1F (nomi esadecimali), oltre alle chiavi esplicite.
Tp0T non compreso nella scansione esadecimale: candidato di fallback, non dichiarato verificato.
L'app usa il massimo delle chiavi CPU Tp01/05/09/0D disponibili e GPU Tg05/0D;
batteria primo TB0T/1T/2T valido.

`smc.c` legge correttamente flt little-endian, ui8, ui32 convenzionale e byte raw hex_.
Nella nuova app hex_ monobyte è decodificato anche numericamente; CHTE viene trattato
esclusivamente a byte (non come percentuale o intero big-endian).

`pmset -g cap`: lowpowermode presente; highpowermode assente.
`pmset -g custom`: lowpowermode 0 sia a batteria sia su AC.

Al momento del probe (sola lettura) non erano ancora verificati l'effetto fisico dell'inibizione e il controllo manuale delle ventole.

**Aggiornamento dopo l'installazione dell'helper:** su questo firmware (macOS 15.3.x) le scritture su CH0B/CH0C
vengono ignorate (rilettura `00`, errore -15), mentre **CHTE** ferma davvero la carica. Per questo TBPower AS
usa CHTE quando presente e CH0B/CH0C solo come fallback. Le ventole restano in sola lettura.

---

## English

**Probe M1 Pro, 6 November 2026 (Europe/Rome)**

Target: MacBookPro18,3, Apple M1 Pro 14", arm64, macOS 15.3.1.
Independent probe tool (not bundled), compiled with clang and the same SMC client `smc.c`.
Only smc_open / smc_read / smc_read_number / smc_close; no write calls.

| Key | Type/size | Result |
|---|---|---|
| FNum | ui8 / 1 | 2 |
| F0Ac / F1Ac | flt / 4 LE | 0 / 0 RPM |
| F0Mn / F1Mn | flt / 4 LE | 1200 / 1200 RPM |
| F0Mx / F1Mx | flt / 4 LE | 5779 / 6241 RPM |
| F0Md / F1Md | ui8 / 1 | 0 / 0 (auto) |
| F0Tg / F1Tg | flt / 4 LE | 0 / 0 |
| Ftst | — | absent (-11) |
| CH0B / CH0C | hex_ / 1 | raw 00 / 00 |
| CHTE | ui32 / 4 | raw 01000000; conventional SMC decoder 16777216 |
| CHWA | — | absent (-11) |
| BCLM | — | absent (-11), probe only, not used by the AS app |
| ACLC | ui8 / 1 | raw 03 |
| CH0I | ui8 / 1 | raw 00 |
| TB0T / TB1T / TB2T | flt / 4 LE | 26.0 / 26.0 / 25.8 °C |
| Tp01 / Tp05 / Tp09 / Tp0D | flt / 4 LE | about 47.7 / 46.7 / 45.8 / 45.0 °C |
| Tg05 / Tg0D | flt / 4 LE | about 45.2 / 44.8 °C |

Other readable thermal keys: Tp00/02/04/06/08/0A/0C/0E, Tg04/0C.
Tp00..Tp3F and Tg00..Tg1F were probed (hexadecimal names), plus the explicit keys.
Tp0T was not included in the hexadecimal scan: fallback candidate, not declared verified.
The app uses the maximum of the available CPU keys Tp01/05/09/0D and GPU Tg05/0D;
battery first valid TB0T/1T/2T.

`smc.c` correctly reads little-endian flt, ui8, conventional ui32 and raw hex_ bytes.
In the new app, single-byte hex_ is also decoded numerically; CHTE is treated
exclusively as bytes (not as a percentage or a big-endian integer).

`pmset -g cap`: lowpowermode present; highpowermode absent.
`pmset -g custom`: lowpowermode 0 on both battery and AC.

At the time of the probe (read-only) the physical effect of inhibit and manual fan control had not yet been verified.

**Update after installing the helper:** on this firmware (macOS 15.3.x) writes to CH0B/CH0C
are ignored (reread `00`, error -15), while **CHTE** actually stops charging. That is why TBPower AS
uses CHTE when present and CH0B/CH0C only as a fallback. Fans remain read-only.
