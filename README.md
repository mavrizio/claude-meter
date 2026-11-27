# claude-meter

Display da scrivania che mostra i limiti d'uso di Claude (sessione 5 ore e settimana) su una
ESP32 "Cheap Yellow Display" da 2.8", alimentato dalla `statusLine` di Claude Code.

```
firmware/   PlatformIO + LVGL 9.3 per ESP32-2432S028
host/       statusline.py (Claude Code) + meterd.py (daemon seriale) + install/uninstall
docs/       storia delle decisioni e roadmap
```

## Installazione (sviluppo)

```bash
cd firmware && pio run -t upload        # flash della scheda
cd ../host && ./install.sh              # statusLine + daemon al login
```

Poi apri `claude` nel terminale e invia un messaggio: i quadranti si riempiono dopo la prima risposta.
Prova la grafica senza Claude: `host/.venv/bin/python host/meterd.py --demo` (fermando prima il daemon).

Requisiti: abbonamento Claude Pro/Max/Ultra (i limiti non esistono con chiave API).

Contesto completo per lo sviluppo: [CLAUDE.md](CLAUDE.md).

## Licenza

[MIT](LICENSE). Progetto indipendente, non affiliato ad Anthropic. Ispirato a
[Blink](https://github.com/KfirLevy258/Blink), ma riscritto da zero.
