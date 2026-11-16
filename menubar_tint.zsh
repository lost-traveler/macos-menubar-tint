#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
SWIFT_SRC="$SCRIPT_DIR/menubar_tint_overlay.swift"
BIN_PATH="/tmp/menubar_tint_overlay"
PID_FILE="/tmp/menubar_tint.pid"

stop_overlay() {
  if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null || true)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
      kill "$OLD_PID" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
  fi
  pkill -f "$BIN_PATH" 2>/dev/null || true
}

if [ $# -ge 1 ]; then
  ARG1="$1"
else
  read "ARG1?Código hex (ej. #FF5500) o 'off' para quitar la barra: "
fi

case "${ARG1:l}" in
  off|stop|quit|disable|quitar|0)
    stop_overlay
    echo "Capa de color de la barra de menús eliminada."
    exit 0
    ;;
esac

HEX="${ARG1#\#}"
if [[ ! "$HEX" =~ ^[0-9A-Fa-f]{6}$ ]]; then
  echo "Error: '$ARG1' no es un código hexadecimal válido (ej. #FF5500) ni 'off'."
  exit 1
fi

ALPHA="${2:-1.0}"
if ! awk "BEGIN { exit !($ALPHA >= 0.05 && $ALPHA <= 1.0) }"; then
  echo "Error: la opacidad debe estar entre 0.05 y 1.0 (valor recibido: $ALPHA)."
  exit 1
fi

R_FLOAT=$(awk "BEGIN { printf \"%.6f\", $((16#${HEX[1,2]})) / 255 }")
G_FLOAT=$(awk "BEGIN { printf \"%.6f\", $((16#${HEX[3,4]})) / 255 }")
B_FLOAT=$(awk "BEGIN { printf \"%.6f\", $((16#${HEX[5,6]})) / 255 }")

if [ ! -x "$BIN_PATH" ] || [ "$SWIFT_SRC" -nt "$BIN_PATH" ]; then
  echo "Compilando overlay nativo (solo la primera vez)..."
  swiftc -O "$SWIFT_SRC" -o "$BIN_PATH"
fi

stop_overlay

nohup "$BIN_PATH" "$R_FLOAT" "$G_FLOAT" "$B_FLOAT" "$ALPHA" >/dev/null 2>&1 &
echo $! > "$PID_FILE"

echo "Capa aplicada en la barra de menús (#${HEX:u}, opacidad $ALPHA)."
echo "Para quitarla en cualquier momento: ${0:t} off"
