#!/usr/bin/env bash
# instalar.sh - instala el binario compilado de el_tioNel en este VPS.
# Uso:  sudo bash instalar.sh            (busca ./el_tioNel-bin en esta carpeta)
#       sudo bash instalar.sh /ruta/al/el_tioNel-bin
set -u
BIN="${1:-./el_tioNel-bin}"
SBIN="/usr/local/sbin"; UBIN="/usr/local/bin"
DEST="$SBIN/el_tioNel-panel"; LINK="$UBIN/el_tioNel"

[ "$(id -u)" -eq 0 ] || { echo "Ejecuta esto como root (sudo bash instalar.sh)"; exit 1; }
[ -f "$BIN" ] || { echo "No encuentro el binario: $BIN"; exit 1; }
file "$BIN" 2>/dev/null | grep -qi 'ELF' || { echo "Eso no parece un binario valido (ELF): $BIN"; exit 1; }

mkdir -p "$SBIN" "$UBIN"
install -m 755 "$BIN" "$DEST" || { echo "No pude copiar a $DEST"; exit 1; }
ln -sfn "$DEST" "$LINK"       || { echo "No pude crear el enlace $LINK"; exit 1; }

echo "Instalado. Para abrir el panel escribe:  el_tioNel"
