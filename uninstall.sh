#!/bin/bash
# Desinstala ConBarAI de macOS (launchd + binario + skill).
# Pregunta antes de tocar datos de sesión y ajustes.
set -Eeuo pipefail

BLUE='\033[1;34m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
say()  { printf "${BLUE}▸${NC} %s\n" "$1"; }
ok()   { printf "${GREEN}✓${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}!${NC} %s\n" "$1"; }

UID_G="$(id -u)"
LAUNCH_DIR="$HOME/Library/LaunchAgents"

say "Deteniendo servicios"
for label in com.conbarai.panel com.conbarai.watch; do
  launchctl bootout "gui/$UID_G/$label" 2>/dev/null && ok "$label detenido" || warn "$label no estaba activo"
  rm -f "$LAUNCH_DIR/$label.plist"
done
ok "LaunchAgents eliminados"

say "Cerrando sesiones tmux de ConBarAI"
if command -v tmux >/dev/null 2>&1; then
  tmux -L conbarai kill-server 2>/dev/null && ok "servidor tmux conbarai cerrado" \
    || warn "no había servidor"
fi

rm -f "$HOME/.local/bin/conbarai"
ok "Binario desinstalado"

read -r -p "¿Borrar también ajustes y estado (~/.config/conbarai, ~/.local/state/conbarai, skill)? [s/N] " ans
if [[ "${ans:-n}" =~ ^[sS] ]]; then
  # Solo rutas fijas y conocidas, dentro del home del usuario actual.
  for target in "$HOME/.config/conbarai" "$HOME/.local/state/conbarai" "$HOME/.local/share/conbarai"; do
    case "$target" in
      "$HOME/.config/conbarai"|"$HOME/.local/state/conbarai"|"$HOME/.local/share/conbarai")
        [[ -n "$HOME" && "$HOME" != "/" && -d "$target" ]] && rm -rf "$target"
        ;;
    esac
  done
  ok "Datos eliminados"
else
  ok "Datos conservados (informes de crash incluidos)"
fi

printf "${GREEN}ConBarAI desinstalado.${NC}\n"
