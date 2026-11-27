# claude-meter — memoria di progetto

Questo file viene letto automaticamente da Claude Code all'apertura della cartella. Contiene tutto il contesto
necessario per continuare lo sviluppo. Dettagli storici in [docs/storia-e-decisioni.md](docs/storia-e-decisioni.md),
piano di lavoro in [docs/roadmap.md](docs/roadmap.md).

## Cos'è

Display da scrivania (ESP32 + LCD 2.8") che mostra i **limiti d'uso di Claude** (abbonamento Pro/Max/Ultra):
- arco **SESSIONE 5H** (% della finestra di 5 ore) + conto alla rovescia del reset
- arco **SETTIMANA** (% della finestra di 7 giorni) + reset
- pallino bianco "ritmo" sull'arco = dove saresti se distribuissi l'uso uniformemente nella finestra
- scheda in basso: % contesto della sessione, costo $ della sessione, righe +/−
- header: modello, ora locale, pallino stato (grigio = Mac assente, verde = collegato, arancione = Claude attivo <20 s)

Ispirato a https://github.com/KfirLevy258/Blink (Zephyr, licenza non commerciale) ma **riscritto da zero**,
più semplice (Arduino/PlatformIO + LVGL) e con grafica nostra. Non copiare codice da Blink.

L'utente (Maurizio) scrive in italiano: rispondere in italiano. Progetto hobbistico, ma vuole qualità
"da prodotto" (grafica curata, app Mac firmata come per il progetto `../sdclone`).

## Architettura

```
Claude Code ──stdin JSON──► claude-meter-statusline (Swift, dentro l'app)  ──► ~/.claude-meter/state.json
                            [oppure host/statusline.py, versione Python]            │
                                                                                    │ mtime ogni 1 s
                         Claude Meter.app (barra dei menu, macos/) ◄────────────────┘
                         [oppure host/meterd.py, versione Python]
                                   │ USB seriale 115200, NDJSON
                                   ▼
                         ESP32 firmware (LVGL) ──► LCD 320x240
```

Due implementazioni lato Mac, **stesso formato di state.json e stesso protocollo**:
- `macos/` — **app ufficiale** (Swift/SwiftUI), quella da usare e da regalare.
- `host/` — versione Python originale: utile per sviluppo (`meterd.py --demo`), non più installata.
**Mai farle girare insieme**: si contendono la porta USB.

### Limite importante: chi usa solo la chat
I percentuali arrivano **solo** quando Claude Code riceve una risposta (la statusLine gira solo allora).
L'uso fatto su claude.ai / app Desktop / telefono consuma gli stessi limiti ma il display lo vede solo alla
risposta successiva di Claude Code. Conto alla rovescia, ritmo e azzeramento al reset sono calcolati dalla
scheda/app ogni secondo. Per un utente **solo chat** non c'è oggi una fonte ufficiale. Valutate:
- `~/Library/Application Support/Claude/plan-usage-history.json` (Claude Desktop): `{"version":2,"samples":[{"t":ms,"org":…,"u":{"fh":7,"sd":11}}]}`
  — senza credenziali ma solo 1–2 campioni al giorno e nessun `resets_at`: insufficiente per il tempo reale.
- **Fonte "Limiti dal tuo account" (sperimentale, app 0.2.0, sì esplicito dell'utente il 27/11)**:
  `GET https://api.anthropic.com/api/oauth/usage` con `Authorization: Bearer <token OAuth di Claude Code>` e
  `anthropic-beta: oauth-2025-04-20`. Risposta: `five_hour`/`seven_day` = `{"utilization":44.0,
  "resets_at":"2026-11-27T20:00:00.05+00:00"}` (+ molti campi null/interni, `seven_day_breakdown` per
  Claude Code/Chat/Cowork). Stessi numeri di `/usage` e claude.ai: **include chat, Desktop, telefono e il
  pannello VS Code**. Token dal portachiavi, voce `Claude Code-credentials` (`{"claudeAiOauth":{accessToken,
  refreshToken,expiresAt(ms),subscriptionType,…}}`), letto con **`/usr/bin/security`** (già autorizzato
  sulla voce: nessun prompt, e l'autorizzazione non si perde quando Claude Code riscrive la voce).
  **Regole**: mai rinnovare il token (il refresh lo ruota e scollegherebbe Claude Code: se è scaduto si
  aspetta che lo rinnovi Claude Code, dura ~6–8 h), mai salvarlo né loggarlo, inviarlo solo ad
  api.anthropic.com. Non documentato: può cambiare; possibile attrito con i termini consumer (spiegato
  all'utente). **Spenta di default**; intervallo scelto nel pannello (1–30 min, default 2); errori con
  backoff fino a 15 min. I dati del conto sostituiscono solo le due finestre finché sono freschi
  (max(10 min, 2,5 × intervallo)); modello/contesto/costo/righe/"attivo" restano dalla statusLine.
  Codice: `MeterCore/AccountUsage.swift`, `AppModel.pollAccountIfDue`. Per l'amico "solo chat" serve
  comunque Claude Code installato e collegato (e usato ogni tanto, per il rinnovo del token).

**Cache di Claude Desktop (verificate 27/11)**: `Local Storage/leveldb` non contiene dati d'uso; `fcache` (binario,
non JSON) e il blob IndexedDB di claude.ai (compresso, contiene chiavi `seven_day_opus`…) hanno dati d'uso ma
sono aggiornati di rado (fermi alle 16:17, insieme all'ultimo campione di plan-usage-history.json, anche dopo
aver aperto la pagina Usage alle ~16:55). Formati interni e fragili: non usarli come fonte in tempo reale.
**Blink non fa meglio**: stessa statusLine (solo CLI), hook per la sola "luce di attività", queste cache di
Desktop, e opzionale `claude -p /usage` periodico (lui stesso lo segnala come possibile violazione dei termini).

**Valori "vecchi"**: ogni sessione passa i `rate_limits` della **sua** ultima risposta API. Una sessione nel
terminale ferma da mezz'ora, rieseguita per un evento (es. cambio del comando statusLine), riscrive valori di
mezz'ora prima (27/11: 11% mostrato contro 26% reale in Claude Desktop). Gli orari di reset invece sono giusti.
Diagnosi: l'helper scrive una riga per chiamata in `~/.claude-meter/statusline.log`
(ora, session_id, version, 5h, 7d); l'`entrypoint` della sessione (`cli` o `claude-vscode`) si legge nel
transcript `~/.claude/projects/<progetto>/<session_id>.jsonl`.

**Estensione VS Code**: il pannello grafico di Claude Code in VS Code **sembra non eseguire la statusLine**
(27/11: decine di risposte in una sessione VS Code non hanno ricreato state.json; sessione però avviata prima
della configurazione → da confermare con una sessione nuova). La documentazione non ne parla. Gli hook invece
girano anche nell'estensione, ma il loro payload non contiene `rate_limits`. Il `/usage` del pannello è
calcolato in locale e non è leggibile da programmi. Soluzione documentata: impostazione VS Code
`claudeCode.useTerminal` ("Use Terminal") → Claude Code gira come CLI nel terminale integrato e la statusLine
funziona.

- **Fonte dati**: il comando `statusLine` di Claude Code riceve su stdin un JSON con `rate_limits`.
  Nessuna API Anthropic, nessun token: i dati esistono solo sul Mac dove gira Claude Code.
- `rate_limits.five_hour` / `rate_limits.seven_day`: `used_percentage` (0–100, float) e `resets_at`
  (epoch secondi). Presenti **solo** per Pro/Max/Ultra e **solo dopo la prima risposta API** della sessione;
  ogni finestra può mancare; Claude Code la toglie quando `resets_at` è passato.
  Altri campi usati: `model.display_name`, `context_window.used_percentage`, `cost.total_cost_usd`,
  `cost.total_lines_added/removed`. Schema completo: https://code.claude.com/docs/en/statusline
- `statusline.py` conserva i limiti precedenti se il payload nuovo non li ha (sessione appena aperta) e sono
  ancora validi. Scrittura atomica (tempfile + os.replace). Stampa anche una status line colorata nel terminale.
- `meterd.py` tiene la porta **sempre aperta** (aprirla resetta l'ESP32), auto-detect della porta, riconnessione,
  invia quando cambia qualcosa o ogni 2 s. `--demo` = dati finti animati, `--port` = porta esplicita.

### Protocollo seriale (NDJSON, una riga JSON per messaggio, `\n`)
Mac → scheda:
```json
{"t":"u","now":1764240000,"tz":3600,"ok":true,"fh":[23.5,1764250000],"sd":[41.2,1764500000],
 "ctx":8,"cost":0.42,"la":156,"lr":23,"m":"Opus","age":12}
```
`now` epoch (la scheda non ha RTC: tiene l'offset da millis), `tz` = offset locale in secondi,
`ok` = esiste state.json, `fh`/`sd` = [pct, resets_at] o assenti, `age` = secondi dall'ultimo update di Claude Code.
Scheda → Mac: `{"t":"hello","fw":"0.1.0"}` al boot e ogni 5 s finché non è collegata.
La scheda considera il link perso dopo 8 s senza messaggi.

## Hardware

- Scheda: **ESP32-2432S028R "Cheap Yellow Display"** — ESP32-D0WD-V3, 4 MB flash, USB-seriale **CH340**.
- Sul Mac dell'utente compare come `/dev/cu.wchusbserial11240` (driver WCH) e `/dev/cu.usbserial-11240`
  (driver Apple): sono **lo stesso dispositivo**, usarne uno solo. Su un Mac senza driver WCH c'è solo `usbserial-*`.
- LCD ILI9341 (driver TFT_eSPI `ILI9341_2_DRIVER`), SPI su HSPI: MISO 12, MOSI 13, SCLK 14, CS 15, DC 2,
  RST −1, backlight GPIO 21 (HIGH = acceso). SPI 40 MHz (se schermo bianco: scendere a 27 MHz).
  Rotazione 1 = orizzontale. Verificato dall'utente: orientamento e colori corretti.
- Touch XPT2046: CLK 25, MOSI 32, MISO 39, CS 33, IRQ 36 (bus SPI separato, VSPI). Driver nostro in
  `src/touch.cpp`: solo pressione (Z), niente coordinate né calibrazione; IRQ non usato.
- LED RGB on-board attivo basso: R 4, G 16, B 17. PWM LEDC canali 1–3 (il canale 0 resta per la
  retroilluminazione). Il verde domina: l'ambra è quasi tutto rosso.
- LDR (sensore luce) su GPIO 34 (non ancora usato).

## Firmware (`firmware/`)

- PlatformIO, `platform = espressif32@7.1.3` (Arduino core 2.0.17), `board = esp32dev`, partizioni `huge_app.csv`
  (nessuna OTA: per l'OTA bisognerà passare a uno schema con due slot app, es. `min_spiffs.csv`).
- Librerie: TFT_eSPI 2.5.43 (configurata tutta da `build_flags`, nessun User_Setup.h), **LVGL 9.3.0**,
  ArduinoJson 7.2.1. Config LVGL minimale in `include/lv_conf.h`.
- `src/main.cpp`: display/flush LVGL, parser seriale NDJSON, stato `UiData`, timeout link.
- `src/led.cpp`: LED come allarme sulla % peggiore fra 5h e 7d: spento <75%, ambra fisso 75–90%, rosso che
  "respira" ≥90%; spento se il Mac non è collegato. Soglie/intensità in costanti in cima al file.
  **Tocco lungo** = silenzia l'allarme attuale (icona nell'header + messaggio); si riarma da solo se peggiora
  (ambra→rosso) o se torna <75%; un altro tocco lungo lo riattiva.
- `src/touch.cpp`: `touch_poll()` → TAP (al rilascio) = `ui_next_page()`, LONG (0,8 s, mentre è premuto) =
  silenzia LED. Isteresi sulla pressione, 350 ms di blocco fra tap.
- `src/ui.cpp` / `include/ui.h`: tutta la grafica. Due pagine a tutto schermo che scorrono sotto l'header
  fisso (pallini pagina al centro): **Archi** e **Dettaglio** (per finestra: ora esatta del reset, ritmo e
  scarto +/−, proiezione lineare "100% alle HH:MM" / "~N% al reset", barra con tacca del ritmo). Archi 270° (135°→45°) range 0..1000, due archi "glow"
  semitrasparenti sotto a quello principale, colore sfumato verde→ambra→rosso (`level_color`),
  animazioni ease-in-out 900 ms, animazione intro (sweep 0→100→valore).
- Font: Montserrat built-in 12/14/16/20/40 — **contengono solo ASCII + simboli LV_SYMBOL**: niente lettere
  accentate (scrivere "piu" non "più") né "−" unicode.

### Comandi
```bash
cd firmware
pio run                                                    # compila
pio run -t upload --upload-port /dev/cu.wchusbserial11240  # flash
PLATFORMIO_BUILD_FLAGS="-DCM_DEBUG_HEAP" pio run -t upload # build con telemetria heap ogni 1 s su seriale
pio run -t compiledb                                       # rigenera compile_commands.json per clangd
```
Il daemon (LaunchAgent) tiene occupata la porta: per flashare fermarlo prima
(`launchctl bootout gui/$(id -u)/com.claude-meter.meterd`) e poi rilanciare `host/install.sh`
(o `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.claude-meter.meterd.plist`).

Decodificare un crash: catturare il "Backtrace:" dalla seriale e
`~/.platformio/packages/toolchain-xtensa-esp32/bin/xtensa-esp32-elf-addr2line -pfiaC -e .pio/build/cyd/firmware.elf <indirizzi>`.

### Insidie già incontrate (non ripetere)
1. **LVGL 9.2.2 ha un memory leak** in `lv_draw_sw_arc.c`: con archi `arc_rounded` il `circle_mask_param`
   non viene liberato → ~10 KB/s persi durante le animazioni → crash `StoreProhibited` in `circ_calc_aa4`
   dopo ~20 s. Risolto passando a **LVGL 9.3.0**. Non tornare a 9.2.x.
2. `LV_USE_STDLIB_MALLOC LV_STDLIB_CLIB`: LVGL usa l'heap ESP32 (~297 KB liberi, stabile) invece del pool fisso.
3. Gli errori clang in VS Code ("Arduino.h not found") spariscono solo con `compile_commands.json`
   (gitignored, 13 MB, rigenerabile con `pio run -t compiledb`).
4. Aprire la seriale resetta l'ESP32 (circuito auto-reset su DTR/RTS): il daemon deve restare connesso;
   impostare `dtr=False, rts=False` prima di `open()`.
6. **Icona nella barra dei menu invisibile**: sul MacBook Pro con la tacca, se ci sono molte icone quelle in
   eccesso finiscono dietro la tacca (e macOS 26 può nasconderle dalle impostazioni Barra dei menu). Per questo
   l'app **mostra il pannello in una finestra quando viene aperta** (non al login), una seconda copia risveglia
   la prima ed esce (`SingleInstance`), e la porta seriale è aperta con `TIOCEXCL`: con l'app attiva
   `pio run -t upload` fallisce con "Resource busy" → prima "Sospendi collegamento".
   Su macOS 26 le finestre delle icone di stato appartengono a "Control Centre": CGWindowList non dice di chi sono.
   Mai usare `osascript ... keystroke` nei test: richiede Accessibilità e colpisce l'app in primo piano.
8. **LVGL: contenitori `LV_SIZE_CONTENT` in flex non sempre si ridimensionano** al cambio del testo dei figli:
   nel fw 0.2.0 modello e ora nell'header venivano tagliati a sinistra. Header e pallini ora hanno
   dimensioni fisse. Per elementi allineati a destra usare un box di larghezza fissa.
7. Certificato Developer ID usato: scade **01/02/2027** → rinnovarlo prima delle release successive.
5. `FileManager.homeDirectoryForCurrentUser` **ignora `$HOME`**: un test con `HOME=/tmp/x` aveva scritto dati
   finti nel vero `~/.claude-meter/state.json`. `MeterPaths.home` ora usa `$HOME`. Nei test usare sempre
   una HOME temporanea **e verificare** che `~/.claude-meter/` reale non cambi.

## App macOS (`macos/`)

Swift Package (swift-tools 5.9, macOS 14+), modellato su `../sdclone`.
- `Sources/MeterCore/` (libreria, testata): `AccountUsage` (fonte sperimentale dal conto, vedi sopra),
  `UsageState` (state.json + parsing del payload statusLine, conserva
  i limiti precedenti validi), `DeviceMessage` (riga NDJSON + `key` senza campi temporali), `SerialPort`
  (termios raw 115200, `rank()` scarta il gemello `cu.usbserial-X` se c'è `cu.wchusbserialX`), `DeviceLink`
  (thread in background: apre una porta, **parla solo dopo l'hello** del firmware, porte mute saltate per 60 s,
  invia al cambio o ogni 2 s, pausa), `ClaudeSettings` (stato/installa/rimuove `statusLine` con backup;
  JSON non valido = mai toccato), `MeterFormat`, `Version` (unica fonte della versione).
- `Sources/claude-meter-statusline/` — helper per Claude Code, va in `Contents/MacOS/` accanto all'app.
- `Sources/ClaudeMeterApp/` — `MenuBarExtra` (.window): icona gauge SF Symbol + "23% · 41%"; pannello con
  `RingGauge` (stessi colori/ritmo del display), statistiche, card di configurazione Claude Code
  (missing / oursOutdated / other / unreadable), avvio al login (`SMAppService.mainApp`), sospendi collegamento
  (per flashare il firmware), dati demo, rimuovi configurazione. `LSUIElement` = niente icona nel Dock.
  `beginActivity` evita App Nap. `NSLog("claude-meter link: …")` per i cambi di stato del collegamento.
- `scripts/build-app.sh` → `build/Claude Meter.app` (bundle id `com.mavrizio.claudemeter`; firma ad-hoc,
  oppure `SIGN_ID=… UNIVERSAL=1` per Developer ID). `scripts/make-icon.swift` → `Resources/AppIcon.icns`.
  `scripts/release.sh [--no-notarize]` → `build/release/ClaudeMeter-<ver>.dmg` universale, firmato, con
  Leggimi.txt; notarizza col profilo `sdclone-notary`. Nel portachiavi ci sono **due** certificati Developer ID
  con lo stesso nome: lo script sceglie per hash SHA-1 quello che scade più tardi (il nome sarebbe ambiguo).

```bash
cd macos
swift build && swift test                       # 13 test MeterCore
scripts/build-app.sh                            # crea build/Claude Meter.app
open "build/Claude Meter.app"
.build/debug/ClaudeMeterApp --snapshot /tmp/p   # PNG del pannello (chiaro/scuro) con dati demo, senza USB
```
Per flashare il firmware: "Sospendi collegamento" nel pannello (o chiudere l'app), poi `pio run -t upload`.

## Host Python (`host/`) — legacy / sviluppo

- `statusline.py` — nessuna dipendenza esterna. Comando registrato in `~/.claude/settings.json`:
  `"/Users/maurizio/Documents/GitHub/claude-meter/host/.venv/bin/python" ".../host/statusline.py"`.
- `meterd.py` — richiede `pyserial` (nel venv `host/.venv`, gitignored, ricreato da install.sh).
- `install.sh` — crea venv, fa backup di settings.json (`settings.json.bak-claude-meter-<data>`), aggiunge
  `statusLine`, installa e avvia LaunchAgent `com.claude-meter.meterd`
  (`~/Library/LaunchAgents/com.claude-meter.meterd.plist`, KeepAlive, log in `~/.claude-meter/meterd.log`).
- `uninstall.sh` — rimuove LaunchAgent e statusLine (solo se è la nostra).
- Stato runtime: `~/.claude-meter/state.json`, `~/.claude-meter/meterd.log`.
- Il venv usa il Python di Homebrew: se brew aggiorna Python e il daemon smette di partire → rilanciare install.sh.

## Stato attuale (27 nov 2026)

- ✅ Firmware v0.1.0 funzionante sulla scheda, grafica approvata dall'utente.
- ✅ Firmware **v0.2.1** (27/11) sulla scheda: LED allarme (silenziabile col tocco lungo) + touch con pagina
  Dettaglio, verificato dall'utente. Luminosità automatica scartata (LDR inutilizzabile, vedi roadmap).
- ✅ Dati reali collegati e verificati dall'utente (prima con Python).
- ✅ Repo GitHub **privato** `mavrizio/claude-meter`.
- ✅ App macOS v0.1.0 (build 1): finestra all'apertura, istanza unica, porta esclusiva, registro statusline.
- ✅ **DMG 0.1.0 notarizzato** (Accepted, id 06371e9b) in `macos/build/release/ClaudeMeter-0.1.0.dmg`
  (non in git; rigenerabile con `scripts/release.sh`).
- Stato sul Mac dell'utente (27/11 ore 17:10): LaunchAgent Python rimosso; **app 0.1.0 installata in
  `/Applications/Claude Meter.app`** dal DMG notarizzato, **"Avvia al login" attivo** (SMAppService, abilitato);
  la `statusLine` punta a `/Applications/Claude Meter.app/Contents/MacOS/claude-meter-statusline`
  (backup `settings.json.bak-claude-meter-20261127-170829`). La copia in `macos/build/` resta solo per
  sviluppo: **mai aprirla insieme a quella installata** (porta USB esclusiva). Se si prova una build di
  sviluppo, il pannello mostrerà "Aggiorna" (percorso diverso): ricordarsi di ripuntare a /Applications.
  ⚠️ `scripts/build-app.sh` cancella e ricrea `build/Claude Meter.app`: chiudere prima l'app di sviluppo.
- Verificato: il display si aggiorna **solo da Claude Code nel terminale**; il pannello VS Code non esegue la
  statusLine. L'utente valuta `claudeCode.useTerminal`.
- ⏭ Prossimi, da decidere con l'utente:
  1. ~~installare l'app in /Applications e attivare "Avvia al login"~~ ✅ fatto 27/11;
  2. provare il DMG su un altro Mac (kit regalo per l'amico);
  3. ~~fonte dati per chi usa solo la chat~~ ✅ opzione "Limiti dal tuo account" nell'app 0.2.0;
  4. idee firmware (~~touch, LED, silenzia LED~~ ✅ 0.2.x; luminosità automatica scartata) e app (notifiche >90%). Vedi [docs/roadmap.md](docs/roadmap.md).

## Convenzioni

- Commenti nel codice in inglese, documentazione e UI in italiano.
- Commit con trailer `Co-Authored-By: Claude …` (lo aggiunge Claude Code).
- Mai committare `.pio/`, `.venv/`, `compile_commands.json`, segreti.
- L'utente ha certificato **Developer ID Application: Maurizio Tolfa (MA876MF3QY)** e profilo notarytool
  `sdclone-notary` nel portachiavi: riusarli per firmare/notarizzare l'app (modello: `../sdclone/scripts/`).
