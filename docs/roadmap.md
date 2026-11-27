# Roadmap

## 1. App macOS "Claude Meter" (prossimo passo)

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

## 3. Distribuzione e aggiornamenti

- Repo `mavrizio/claude-meter` è **privato**: gli amici non possono scaricarne le release.
  Opzioni: repo pubblico separato solo per i binari (es. `claude-meter-releases`), oppure rendere pubbliche
  solo le release. Da decidere.
- GitHub Actions: compilare il firmware (`pio run`) e allegare `firmware.bin` alle release.
- Aggiornamento app: Sparkle o controllo manuale dell'ultima release.

## 4. Firmware — idee

- [ ] **Touch** (XPT2046) per cambiare schermata: dettaglio sessione, storico, impostazioni luminosità.
- [ ] **LED RGB** come allarme discreto (ambra >75%, rosso >90%), con PWM basso.
- [ ] **Retroilluminazione automatica** con LDR su GPIO 34; spegnimento quando il Mac è assente da molto.
- [ ] Proiezione: "a questo ritmo arrivi al 100% alle 15:40".
- [ ] Font personalizzati (lv_font_conv) con lettere accentate.
- [ ] **WiFi** come trasporto alternativo (il Mac invia in LAN, discovery mDNS) — l'utente per ora va bene con USB.
- [ ] **OTA** dalle release GitHub (richiede WiFi e partizioni con due slot app).
