#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
SWIFT_SRC="$SCRIPT_DIR/menubar_tint_overlay.swift"
BIN_DIR="$HOME/.local/bin"
BIN_PATH="$BIN_DIR/menubar_tint_overlay"
PID_FILE="/tmp/menubar_tint.pid"
PLIST_LABEL="com.macos.menubar-tint"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$PLIST_DIR/$PLIST_LABEL.plist"
GUI_DOMAIN="gui/$(id -u)"

stop_overlay() {
  local remove_autostart="${1:-false}"

  launchctl bootout "$GUI_DOMAIN/$PLIST_LABEL" 2>/dev/null || true
  if [ "$remove_autostart" = "true" ]; then
    rm -f "$PLIST_PATH"
  fi

  if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null || true)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
      kill "$OLD_PID" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
  fi
  pkill -f "$BIN_PATH" 2>/dev/null || true
  pkill -f "/tmp/menubar_tint_overlay" 2>/dev/null || true
}

write_launch_agent() {
  local r="$1" g="$2" b="$3" a="$4"
  mkdir -p "$PLIST_DIR"
  cat << EOF > "$PLIST_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$PLIST_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$BIN_PATH</string>
    <string>$r</string>
    <string>$g</string>
    <string>$b</string>
    <string>$a</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
</dict>
</plist>
EOF
}

if [ $# -ge 1 ]; then
  ARG1="$1"
else
  read "ARG1?Código hex (ej. #FF5500) o 'off' para quitar la barra y el inicio automático: "
fi

case "${ARG1:l}" in
  off|stop|quit|disable|quitar|0)
    stop_overlay "true"
    echo "Capa de color eliminada y desactivada del inicio del sistema."
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

mkdir -p "$BIN_DIR"
if [ ! -x "$BIN_PATH" ] || [ "$SWIFT_SRC" -nt "$BIN_PATH" ]; then
  echo "Compilando overlay nativo en $BIN_PATH..."
  swiftc -O "$SWIFT_SRC" -o "$BIN_PATH"
fi

stop_overlay "false"
write_launch_agent "$R_FLOAT" "$G_FLOAT" "$B_FLOAT" "$ALPHA"

if launchctl bootstrap "$GUI_DOMAIN" "$PLIST_PATH" 2>/dev/null; then
  echo "Capa aplicada en la barra de menús (#${HEX:u}, opacidad $ALPHA) y configurada para iniciar al arrancar macOS."
else
  nohup "$BIN_PATH" "$R_FLOAT" "$G_FLOAT" "$B_FLOAT" "$ALPHA" >/dev/null 2>&1 &
  echo $! > "$PID_FILE"
  echo "Capa aplicada (#${HEX:u}, opacidad $ALPHA). LaunchAgent guardado en $PLIST_PATH para el próximo inicio."
fi

echo "Para quitarla y desactivar el inicio automático: ${0:t} off"
