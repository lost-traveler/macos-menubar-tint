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
  local r="$1" g="$2" b="$3" a="$4" m="$5"
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
    <string>$m</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
</dict>
</plist>
EOF
}

ensure_icloud_downloaded() {
  if [[ "$SWIFT_SRC" == *"com~apple~CloudDocs"* ]] && command -v brctl >/dev/null 2>&1; then
    if [ ! -f "$SWIFT_SRC" ] && [ -f "$SCRIPT_DIR/.${SWIFT_SRC:t}.icloud" ]; then
      echo "Downloading $SWIFT_SRC from iCloud Drive..."
      brctl download "$SWIFT_SRC" 2>/dev/null || true
      local tries=0
      while [ ! -f "$SWIFT_SRC" ] && [ $tries -lt 20 ]; do
        sleep 0.5
        tries=$((tries + 1))
      done
    else
      brctl download "$SWIFT_SRC" 2>/dev/null || true
    fi
  fi
}

parse_mode_token() {
  local token="${1:l}"
  case "$token" in
    1|auto|--auto) echo "auto" ;;
    2|dark|multiply|--dark|--multiply) echo "dark" ;;
    3|light|screen|--light|--screen) echo "light" ;;
    *) return 1 ;;
  esac
}

ALPHA="1.0"
MODE="auto"

if [ $# -ge 1 ]; then
  ARG1="$1"
  shift

  case "${ARG1:l}" in
    off|stop|quit|disable|quitar|0)
      stop_overlay "true"
      echo "Menu bar tint overlay removed and disabled from login startup."
      exit 0
      ;;
  esac

  while [ $# -ge 1 ]; do
    token="$1"
    shift
    if parsed=$(parse_mode_token "$token" 2>/dev/null); then
      MODE="$parsed"
    elif [[ "$token" == "--mode" ]] && [ $# -ge 1 ]; then
      MODE=$(parse_mode_token "$1") || {
        echo "Error: invalid mode '$1'. Use auto, dark, or light."
        exit 1
      }
      shift
    elif [[ "$token" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      ALPHA="$token"
    else
      echo "Error: unrecognized argument '$token'. Expected opacity (0.05-1.0) or mode (auto, dark, light)."
      exit 1
    fi
  done
else
  read "ARG1?Enter a hex color (e.g. #FF5500) or 'off' to remove the overlay and auto-start: "
  case "${ARG1:l}" in
    off|stop|quit|disable|quitar|0)
      stop_overlay "true"
      echo "Menu bar tint overlay removed and disabled from login startup."
      exit 0
      ;;
  esac

  read "ALPHA_INPUT?Enter opacity/intensity (0.05 - 1.0, press Enter for 1.0): "
  if [ -n "$ALPHA_INPUT" ]; then
    ALPHA="$ALPHA_INPUT"
  fi

  echo ""
  echo "Select blend mode:"
  echo "  [1] auto  (Default) - Samples the top strip of your wallpaper and falls back to macOS Dark/Light Mode."
  echo "                        Ideal for most setups and automatic Dark/Light switching."
  echo "  [2] dark  (multiply) - Tints white menu bar text/icons while keeping pure black backgrounds untouched."
  echo "                        Ideal for Dark Mode with a black menu bar or dark wallpaper."
  echo "  [3] light (screen)   - Tints black menu bar text/icons while keeping pure white backgrounds untouched."
  echo "                        Ideal for Light Mode with a white/bright menu bar background."
  read "MODE_INPUT?Choose mode [1/2/3 or auto/dark/light, Enter for auto]: "
  if [ -n "$MODE_INPUT" ]; then
    MODE=$(parse_mode_token "$MODE_INPUT") || {
      echo "Error: invalid mode '$MODE_INPUT'. Choose 1 (auto), 2 (dark), or 3 (light)."
      exit 1
    }
  fi
fi

HEX="${ARG1#\#}"
if [[ ! "$HEX" =~ ^[0-9A-Fa-f]{6}$ ]]; then
  echo "Error: '$ARG1' is not a valid 6-digit hex color (e.g. #FF5500) or 'off'."
  exit 1
fi

if ! LC_ALL=C awk "BEGIN { exit !($ALPHA >= 0.05 && $ALPHA <= 1.0) }"; then
  echo "Error: opacity must be between 0.05 and 1.0 (received: $ALPHA)."
  exit 1
fi

R_FLOAT=$(LC_ALL=C awk "BEGIN { printf \"%.6f\", $((16#${HEX[1,2]})) / 255 }")
G_FLOAT=$(LC_ALL=C awk "BEGIN { printf \"%.6f\", $((16#${HEX[3,4]})) / 255 }")
B_FLOAT=$(LC_ALL=C awk "BEGIN { printf \"%.6f\", $((16#${HEX[5,6]})) / 255 }")

ensure_icloud_downloaded

mkdir -p "$BIN_DIR"
if [ ! -x "$BIN_PATH" ] || [ "$SWIFT_SRC" -nt "$BIN_PATH" ]; then
  echo "Compiling native overlay to $BIN_PATH..."
  swiftc -O "$SWIFT_SRC" -o "$BIN_PATH"
fi

stop_overlay "false"
write_launch_agent "$R_FLOAT" "$G_FLOAT" "$B_FLOAT" "$ALPHA" "$MODE"

if launchctl bootstrap "$GUI_DOMAIN" "$PLIST_PATH" 2>/dev/null; then
  echo "Menu bar tint applied (#${HEX:u}, opacity $ALPHA, mode $MODE) and enabled at login."
else
  nohup "$BIN_PATH" "$R_FLOAT" "$G_FLOAT" "$B_FLOAT" "$ALPHA" "$MODE" >/dev/null 2>&1 &
  echo $! > "$PID_FILE"
  echo "Menu bar tint applied (#${HEX:u}, opacity $ALPHA, mode $MODE). LaunchAgent saved to $PLIST_PATH for next login."
fi

echo "To remove the overlay and disable auto-start: ${0:t} off"
