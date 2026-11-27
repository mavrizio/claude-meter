# Storia e decisioni

Diario del progetto, in ordine cronologico. Serve a capire *perché* le cose sono come sono.

## 27 novembre 2026 — prima sessione

### Punto di partenza
- Maurizio ha una CYD (ESP32-2432S028, LCD 2.8") collegata via USB al Mac e ha visto il progetto
  [Blink](https://github.com/KfirLevy258/Blink): due quadranti con l'uso di Claude Code.
- Analisi di Blink: firmware Zephyr + LVGL + MCUboot, daemon Python sul Mac che legge la `statusLine` di
  Claude Code e parla alla scheda in NDJSON su seriale; opzionale WiFi; licenza PolyForm Noncommercial.
  Non usa API né token di Anthropic.

### Decisione: strada B, versione nostra
Opzioni presentate: (A) usare Blink così com'è, (B) rifarlo semplice con strumenti già installati.
Scelta **B**: PlatformIO + Arduino + TFT_eSPI + LVGL, script Python sul Mac. Motivi: codice comprensibile e
modificabile, niente toolchain Zephyr, licenza libera, grafica personalizzabile ("possiamo fare di meglio").

### Ambiente verificato
- Scheda ESP32-D0WD-V3, 4 MB flash, CH340 su `/dev/cu.wchusbserial11240`.
- Già installati: esptool 5.2, PlatformIO 6.2 (espressif32 7.1.3 = Arduino core 2.0.17), arduino-cli, Python 3.14
  (Homebrew), Claude Code 2.1.302, Xcode 26.4.1, gh (account `mavrizio`).

### Scelte grafiche (oltre Blink)
- Archi con antialiasing e alone "glow" (due archi semitrasparenti più larghi sotto quello principale).
- Colore che sfuma con continuità verde → ambra (50–75%) → rosso (75–92%).
- **Indicatore di ritmo**: pallino sull'arco nella posizione "tempo trascorso / durata finestra".
  Se l'arco colorato lo supera, stai consumando più in fretta del ritmo sostenibile.
- Animazioni dei valori e animazione di avvio.
- Tema scuro (#0D0D0F), accento arancione #D97757.

### Bug trovato: memory leak LVGL 9.2.2
Primo test con la demo: la scheda si riavviava ogni ~20 s (`Guru Meditation StoreProhibited` in
`circ_calc_aa4`). Telemetria heap: −10 KB/s anche senza messaggi, solo per le animazioni.
Causa: in LVGL 9.2.2 `lv_draw_sw_arc()` inizializza `circle_mask_param` per le estremità arrotondate e non
lo libera mai. Corretto in **9.3.0** (verificato nel sorgente). Dopo l'aggiornamento heap stabile a ~297 KB
per 45 s di animazioni continue. Lasciata la build `-DCM_DEBUG_HEAP` per diagnosi future.

### Collegamento dati reali
- Installati `statusLine` in `~/.claude/settings.json` (non ce n'era una prima; backup fatto) e LaunchAgent.
- Verificato dall'utente: funziona con i suoi dati reali.

### Domande dell'utente e risposte
1. **USB o WiFi?** I dati nascono sempre sul Mac (Claude Code). Non esiste un'API ufficiale che la scheda possa
   interrogare da sola per i limiti dell'abbonamento; usare il token OAuth di Claude Code dalla scheda sarebbe
   non documentato e insicuro. Il *trasporto* però può essere USB (attuale), WiFi in LAN (Mac → scheda),
   o cloud/MQTT (anche fuori casa, più computer). L'utente: "mi va bene anche il cavo USB".
2. **GitHub + aggiornamento remoto?** Sì: repo (creato **privato**) + in futuro OTA dalle Release.
   Nota: con repo privato la scheda (o l'app dell'amico) non può scaricare release senza token →
   per distribuire servirà un canale pubblico per i soli binari (vedi roadmap).
3. **Regalarlo a un amico?** Vedi roadmap: dispositivo pre-flashato + cavo dati + app macOS firmata.
4. **Memoria nel progetto**: questo file, `CLAUDE.md`, `docs/roadmap.md`, workspace `claude-meter.code-workspace`.

### App macOS (stessa giornata, sera)
- Richiesta: app Mac come per sdclone, dentro la stessa cartella (`macos/`), per regalare il display.
- **Domanda dell'utente**: "per rinfrescare il display devo inviare un messaggio su Claude: sarà così anche
  dopo? Il mio amico usa la chat". Risposta: sì, i percentuali arrivano solo quando Claude Code riceve una
  risposta; l'uso dalla chat non è visibile finché Claude Code non risponde di nuovo. Indagate le alternative
  (storico locale di Claude Desktop: troppo rado; endpoint interno: non documentato e con credenziali).
  Decisione rimandata all'utente; l'app è progettata con fonti modulari.
- Architettura app: MeterCore (testata) + helper statusLine Swift + app SwiftUI MenuBarExtra. Stesso
  state.json e stesso protocollo della versione Python → compatibili, migrazione senza perdere dati.
- Handshake: l'app parla a una porta solo dopo l'`hello` del firmware, per non disturbare altre schede
  USB-seriale (Maurizio sviluppa molti firmware) e salta per 60 s le porte mute.
- Verifica visiva del pannello senza poter cliccare la barra dei menu: opzione `--snapshot` che disegna il
  pannello con dati demo in PNG chiaro/scuro.
- **Errore commesso e corretto**: testando l'helper con `HOME=<cartella temporanea>`, i dati finti sono finiti
  nel vero `~/.claude-meter/state.json` perché `homeDirectoryForCurrentUser` ignora `$HOME`. File rimosso
  (si ripopola al primo messaggio di Claude Code), `MeterPaths.home` ora rispetta `$HOME`.
- Migrazione sul Mac di Maurizio: LaunchAgent Python fermato e plist rimosso; app avviata da
  `macos/build/`, collegata al display (hello in ~4 s). statusLine ancora sullo script Python finché
  l'utente non clicca "Aggiorna" nel pannello.

### release.sh e la chat dentro VS Code
- `release.sh` creato sul modello di sdclone; scelta del certificato per hash perché nel portachiavi ci sono
  due "Developer ID Application: Maurizio Tolfa" identici. DMG universale firmato, provato senza notarizzare.
- Maurizio usa soprattutto **la chat di Claude Code dentro VS Code** (il pannello dell'estensione).
  Verifica: dopo la cancellazione di state.json, decine di risposte nel pannello VS Code non l'hanno ricreato
  → il pannello non sembra eseguire la statusLine (da confermare con una sessione nuova). I transcript
  `~/.claude/projects/*.jsonl` non contengono i rate limit. Soluzione proposta: `claudeCode.useTerminal`.
- Il pulsante "Aggiorna" del pannello non ha modificato settings.json (nessun nuovo backup): da chiarire.
