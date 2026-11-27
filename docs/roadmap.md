# Roadmap

## 0. Fonte dati per chi usa solo la chat (decisa: C, opzionale)

L'amico a cui regalare il display usa quasi solo la chat (claude.ai / app Desktop), quindi la statusLine di
Claude Code non parte mai. Opzioni (dettagli in CLAUDE.md, "Limite importante"):
- **A. Solo Claude Code** (attuale, ufficiale): per lui il display resterebbe vuoto.
- **B. Storico locale di Claude Desktop** (`plan-usage-history.json`): niente credenziali, ma campioni rari e
  senza orario di reset. Al massimo come indicazione "ultimo valore noto".
- **C. Endpoint interno di utilizzo** usato dalle app Anthropic: tempo reale, ma non documentato, richiede le
  credenziali dell'utente e l'uso automatico potrebbe violare i termini consumer. Blink lo evita.
L'app ha fonti modulari (state.json oggi): aggiungerne una non richiede di riscrivere UI o protocollo.

**Decisione 27/11**: l'utente ha scelto C come **opzione sperimentale spenta di default** ("Limiti dal tuo
account" nel pannello, intervallo regolabile). Implementata nell'app 0.2.0; dettagli e regole in CLAUDE.md.

## 1. App macOS "Claude Meter" — v0.1.0 fatta, da rifinire

Fatto: MenuBarExtra, pannello con anelli, collegamento USB con handshake, configurazione guidata statusLine,
helper Swift, avvio al login, sospensione, demo, icona, build-app.sh, 9 test.
Da fare:
- [x] `scripts/release.sh`: universale, firma Developer ID, DMG con Leggimi (provato con --no-notarize).
- [x] Prima notarizzazione (27/11, ClaudeMeter-0.1.0.dmg, Accepted, id 06371e9b). [ ] Prova del DMG su un altro Mac.
- [ ] Verificare il pulsante "Aggiorna/Configura" del pannello (il 27/11 settings.json non è cambiato).
- [ ] Installazione in /Applications e prova dell'avvio al login sul Mac di Maurizio.
- [ ] Notifica quando un limite supera 90% (UserNotifications).
- [ ] Concatenare una statusLine preesistente invece di sostituirla.
- [ ] Rilevare inserimento/rimozione USB con IOKit invece del polling ogni 1–2 s.
- [ ] Aggiornamento firmware via USB dall'app.

### Progetto originale (riferimento)

Obiettivo: poter regalare il dispositivo a un amico con Mac e Claude Pro/Max **senza Python, terminale o script**.
Modello: il progetto `../sdclone` (Swift Package, SwiftUI, `scripts/build-app.sh`, `scripts/release.sh` con
firma Developer ID + notarizzazione + DMG, icona generata da `scripts/make-icon.swift`).

### Cosa fa l'app
- **App della barra dei menu** (SwiftUI `MenuBarExtra`): nella barra "5h 23% · 7d 41%"; nel pannello due
  anelli come sul display, reset, stato del dispositivo, pulsanti.
- **Configurazione guidata al primo avvio**: spiega cosa fa e, col consenso, aggiunge la `statusLine` a
  `~/.claude/settings.json` (backup prima; se ne esiste già una, avvisa e propone di concatenarla).
- **Helper statusline** in Swift dentro il bundle (`Claude Meter.app/Contents/MacOS/claude-meter-statusline`):
  porta di `host/statusline.py`, così non serve Python.
- **Seriale nativa** (POSIX `termios` + `IOKit` per rilevare inserimento/rimozione), stesso protocollo NDJSON;
  sostituisce `meterd.py`.
- **Avvio al login** con `SMAppService.mainApp` (niente LaunchAgent a mano).
- Disinstallazione pulita dal menu (toglie la statusLine).
- Più avanti: aggiornamento firmware via USB dall'app (protocollo ROM bootloader ESP32 o esptool incluso).

### Migrazione sul Mac di Maurizio
Quando l'app è pronta: `host/uninstall.sh`, poi l'app installa la sua statusLine. `host/` resta come
riferimento/strumenti di sviluppo (`meterd.py --demo` utile per provare la grafica).

## 2. Kit regalo per un amico

Da fornire:
1. **Dispositivo CYD già flashato** con il firmware (lo flashiamo noi: l'amico non deve installare nulla).
2. **Cavo USB dati** (non solo ricarica!) adatto al suo Mac (spesso serve USB-C ↔ micro-USB).
3. **Claude Meter.dmg** firmato e notarizzato (certificato Developer ID già disponibile).

Requisiti lato amico: macOS 14+, **Claude Code CLI** con abbonamento Pro/Max/Ultra (i limiti non arrivano con
chiave API). Driver CH340: incluso in macOS (compare come `/dev/cu.usbserial-*`), niente da installare.
Nota: la statusLine è aggiornata dalla CLI `claude`; da verificare se anche l'estensione VS Code la esegue.

## 3. Distribuzione e aggiornamenti — **da fare prima del kit regalo**

Deciso il 27/11: un solo canale di aggiornamento, **il firmware viaggia dentro l'app**. Va fatto prima di
consegnare la seconda unità, altrimenti ogni correzione richiede di riprendere Mac o scheda dell'amico.

- [ ] **Aggiornamento app con Sparkle 2** (pacchetto SwiftPM): l'app legge un feed pubblico (appcast),
  propone "È disponibile la versione X", scarica, verifica firma EdDSA + notarizzazione, sostituisce e riavvia.
  Chiave EdDSA generata una volta (privata nel portachiavi, pubblica in Info.plist). `release.sh` genera il
  feed (`generate_appcast`). Opzione nel pannello per disattivare il controllo; citarlo nel Leggimi (privacy).
- [ ] **Firmware dentro l'app**: `firmware.bin` in `Contents/Resources`; il display dichiara la versione
  nell'hello; se è più vecchia il pannello mostra "Aggiorna il display" e l'app la carica via USB con il
  protocollo del ROM bootloader ESP32 (scritto in Swift, nessun esptool/Python sull'altro Mac). Reset in
  bootloader via DTR/RTS. Sicuro: il ROM bootloader non si cancella, un caricamento interrotto si ripete.
  Serve solo l'app a 0x10000 se bootloader e partizioni non cambiano. Nessuna OTA Wi-Fi: `huge_app.csv` va bene.
- [x] **Dove pubblicare** DMG e feed: il repo `mavrizio/claude-meter` è **pubblico** dal 27/11 (licenza MIT):
  DMG come GitHub Release, feed Sparkle come asset della release o su GitHub Pages.
- [ ] GitHub Actions (facoltativo): compilare firmware e app ad ogni tag. La notarizzazione richiede le
  credenziali Apple: più semplice continuare a fare le release in locale con `release.sh`.
- Stima: ~mezza giornata Sparkle, ~1 giornata caricamento firmware dall'app.

## 4. Firmware — idee

- [x] **Touch** (XPT2046) per cambiare schermata — fw 0.2.0: tocco = pagina Dettaglio. Da fare: storico,
  impostazioni. Tocco lungo = silenzia il LED (fw 0.2.1).
- [x] **LED RGB** come allarme discreto (ambra >75%, rosso >90%), con PWM basso — fw 0.2.0.
- [—] **Retroilluminazione automatica** con LDR su GPIO 34 — **scartata dall'utente** (27/11, "non mi serve").
  Misurato: l'LDR legge 0–13 (su 4095, ADC a 0 dB) sia con luce normale sia con la scheda coperta e lo
  schermo spento. Difetto noto della CYD: il circuito di fabbrica vede solo "luce piena" salvo buio assoluto;
  si sistema solo in hardware (togliere R19, R15 → 47 kΩ, 0603) o schermando il sensore dalla retroilluminazione.
  Fonti: forum.arduino.cc/t/cheap-yellow-display-ldr-sensor/1347942, witnessmenow/ESP32-Cheap-Yellow-Display Mods.
- [x] Proiezione: "a questo ritmo arrivi al 100% alle 15:40" — nella pagina Dettaglio (fw 0.2.0).
- [ ] Font personalizzati (lv_font_conv) con lettere accentate.
- [ ] **WiFi** come trasporto alternativo (il Mac invia in LAN, discovery mDNS) — l'utente per ora va bene con USB.
- [ ] **OTA** dalle release GitHub (richiede WiFi e partizioni con due slot app).
