#!/bin/bash
# Builds the distributable version: universal app signed with Developer ID, DMG, Apple notarization.
#
#   scripts/release.sh                  sign, build the DMG, notarize it and staple the ticket
#   scripts/release.sh --no-notarize    everything except notarization (for testing)
#   SIGN_ID=- scripts/release.sh --no-notarize    no certificate (ad-hoc: NOT distributable)
#
# Notarization uses the keychain profile "sdclone-notary" (same Apple account as SD Clone).
# Override with NOTARY_PROFILE=... ; to create one:
#   xcrun notarytool store-credentials <name> --apple-id YOUR@EMAIL --team-id TEAMID
#
# Output in build/release/: "Claude Meter.app", ClaudeMeter-<version>.dmg and .sha256.
set -euo pipefail
cd "$(dirname "$0")/.."

NOTARIZE=1
[ "${1:-}" = "--no-notarize" ] && NOTARIZE=0
PROFILE="${NOTARY_PROFILE:-sdclone-notary}"

VERSION=$(sed -n 's/.*marketing = "\(.*\)".*/\1/p' Sources/MeterCore/Version.swift)
OUT="build/release"
DMG="$OUT/ClaudeMeter-$VERSION.dmg"

# Certificate: explicit SIGN_ID, otherwise the "Developer ID Application" identity that expires last.
# Picked by SHA-1 hash: the keychain may hold two certificates with the same name, and codesign
# refuses an ambiguous name.
if [ -z "${SIGN_ID:-}" ]; then
    BEST="" BEST_END=0
    while read -r HASH; do
        END=$(security find-certificate -a -Z -p -c "Developer ID Application" 2>/dev/null \
            | awk -v h="$HASH" '/^SHA-1 hash:/{keep=($3==h)} keep' \
            | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
        [ -n "$END" ] || continue
        END_TS=$(date -j -f "%b %d %T %Y %Z" "$END" +%s 2>/dev/null || echo 0)
        if [ "$END_TS" -gt "$BEST_END" ]; then BEST="$HASH"; BEST_END="$END_TS"; fi
    done < <(security find-identity -v -p codesigning | awk '/Developer ID Application/{print $2}')
    [ -n "$BEST" ] || { echo "Nessun certificato 'Developer ID Application' valido nel portachiavi." >&2; exit 1; }
    SIGN_ID="$BEST"
    echo "Firma con: $(security find-identity -v -p codesigning | awk -v h="$SIGN_ID" '$2==h' | sed 's/.*"\(.*\)"/\1/') [$SIGN_ID, scade $(date -r "$BEST_END" +%d/%m/%Y)]"
else
    echo "Firma con: $SIGN_ID"
fi

rm -rf "$OUT"
mkdir -p "$OUT"
APP_DIR="$OUT" UNIVERSAL=1 SIGN_ID="$SIGN_ID" scripts/build-app.sh release
[ "$SIGN_ID" = "-" ] && codesign --force --deep --sign - "$OUT/Claude Meter.app" >/dev/null
APP="$OUT/Claude Meter.app"
lipo -archs "$APP/Contents/MacOS/ClaudeMeter"
lipo -archs "$APP/Contents/MacOS/claude-meter-statusline"

# DMG: the app, an Applications link and a short read-me.
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applicazioni"
cat > "$STAGE/Leggimi.txt" <<TXT
Claude Meter $VERSION

1. Trascina "Claude Meter" nella cartella Applicazioni e aprilo:
   compare un'icona a forma di indicatore nella barra dei menu, in alto a destra.
2. Clicca l'icona e premi "Configura": Claude Meter aggiunge la barra di stato
   a Claude Code (~/.claude/settings.json, con backup).
3. Collega il display con un cavo USB dati (non solo ricarica).
4. Apri Claude Code nel terminale ("claude"), anche dentro VS Code, e invia un
   messaggio: i limiti compaiono dopo la prima risposta.
5. Nel pannello attiva "Avvia al login".
6. Facoltativo: "Limiti dal tuo account (sperimentale)" mostra anche l'uso fatto
   dalla chat (claude.ai, app Desktop, telefono). Vedi sotto.

Requisiti: macOS 14 o successivo, Claude Code con abbonamento Pro, Max o Ultra.

Privacy: di base Claude Meter non usa Internet e i dati restano sul tuo Mac.
Solo se attivi "Limiti dal tuo account", ogni pochi minuti chiede le percentuali
d'uso ad Anthropic (lo stesso servizio, non documentato, usato da /usage di Claude
Code), con l'accesso di Claude Code salvato nel portachiavi. L'accesso non viene
copiato, salvato o inviato altrove. Il servizio potrebbe cambiare: in quel caso
l'opzione smette di funzionare e si torna ai dati di Claude Code.
Per disinstallare: nel pannello, menu "..." > "Rimuovi configurazione da Claude Code",
poi trascina l'app nel Cestino.
TXT
hdiutil create -volname "Claude Meter $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
[ "$SIGN_ID" = "-" ] || codesign --force --timestamp --sign "$SIGN_ID" "$DMG"

if [ "$NOTARIZE" = 1 ] && [ "$SIGN_ID" != "-" ]; then
    echo "Invio ad Apple per la notarizzazione (di solito pochi minuti)..."
    xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature -v "$DMG"
else
    echo "Notarizzazione saltata: il DMG NON e' pronto per la distribuzione."
fi

(cd "$OUT" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "Pronto: $DMG"
cat "$DMG.sha256"
