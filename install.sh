#!/bin/bash
# ConBarAI para macOS — instalador (sin sudo, todo en espacio de usuario).
# Paridad con install.sh de la versión Ubuntu, con launchd en lugar de systemd.
# Nota de seguridad: este instalador NO descarga ni ejecuta scripts remotos;
# si falta una dependencia externa (Homebrew/OpenCode) te manda a la web oficial
# para que la instales tú y vuelvas a lanzar ./install.sh.
set -Eeuo pipeFail

BLUE='\033[1;34m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
say()  { printf "${BLUE}▸${NC} %s\n" "$1"; }
ok()   { printf "${GREEN}✓${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}!${NC} %s\n" "$1"; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_LINK="$HOME/.local/bin/conbarai"
LAUNCH_DIR="$HOME/Library/LaunchAgents"
PANEL_PLIST="$LAUNCH_DIR/com.conbarai.panel.plist"
WATCH_PLIST="$LAUNCH_DIR/com.conbarai.watch.plist"
SETTINGS_DIR="$HOME/.config/conbarai"

step() { printf "\n${BLUE}== %s ==${NC}\n" "$1"; }
missing_dep=0

# ---------------------------------------------------------------- dependencias
step "Comprobando dependencias"

[[ "$(uname -s)" == "Darwin" ]] || { echo "Esto es para macOS."; exit 1; }

if ! xcode-select -p >/dev/null 2>&1; then
  warn "Faltan las Command Line Tools de Xcode (necesarias para compilar)."
  read -r -p "¿Instalarlas ahora? [S/n] " ans
  if [[ "${ans:-s}" =~ ^[nN] ]]; then exit 1; fi
  xcode-select --install
  echo "Vuelve a ejecutar ./install.sh cuando termine la instalación de las CLT."
  exit 0
fi
ok "Command Line Tools presentes"

if ! command -v swift >/dev/null 2>&1; then
  echo "No encuentro swift (¿CLT incompletas?). Ejecuta: xcode-select --install"
  exit 1
fi
ok "Swift listo"

if ! command -v brew >/dev/null 2>&1; then
  warn "Homebrew no está instalado (hace falta para tmux y la fuente)."
  echo "  Instálalo desde la web oficial y vuelve a lanzar ./install.sh: https://brew.sh"
  missing_dep=1
fi

if ! command -v tmux >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    warn "tmux no está instalado (obligatorio: persiste las sesiones)."
    read -r -p "¿Instalarlo con brew? [S/n] " ans
    if [[ ! "${ans:-s}" =~ ^[nN] ]]; then brew install tmux; fi
  else
    missing_dep=1
  fi
fi
command -v tmux >/dev/null 2>&1 && ok "tmux listo"

if ! command -v opencode >/dev/null 2>&1 && ! [[ -x "$HOME/.opencode/bin/opencode" ]] && ! command -v pi >/dev/null 2>&1; then
  warn "No hay agente instalado (pi recomendado, u opencode)."
  echo "  Pi (ligero):      npm install -g @mariozechner/pi-coding-agent"
  echo "  OpenCode:         https://opencode.ai"
  read -r -p "¿Instalar pi con npm? [S/n] " ans
  if [[ ! "${ans:-s}" =~ ^[nN] ]] && command -v npm >/dev/null 2>&1; then
    npm install -g @mariozechner/pi-coding-agent
  fi
fi
if command -v pi >/dev/null 2>&1; then
  ok "pi $(pi --version 2>/dev/null | head -1 | awk '{print $NF}') — agente por defecto"
elif command -v opencode >/dev/null 2>&1 || [[ -x "$HOME/.opencode/bin/opencode" ]]; then
  ok "OpenCode presente (agente de respaldo)"
fi

if [[ "$missing_dep" == "1" ]]; then
  echo
  warn "Faltan dependencias; instala lo de arriba y re-ejecuta ./install.sh"
  exit 1
fi

if ! system_profiler SPFontsDataType 2>/dev/null | grep -q "JetBrainsMono"; then
  warn "Falta la fuente JetBrains Mono Nerd (opcional, pero se ve mejor)."
  read -r -p "¿Instalarla con brew? [S/n] " ans
  if [[ ! "${ans:-s}" =~ ^[nN] ]]; then brew install --cask font-jetbrains-mono-nerd-font; fi
fi

# ------------------------------------------------------------------- compilado
step "Compilando ConBarAI (release)"
swift build -c release
BIN="$REPO_DIR/.build/release/conbarai"
ok "Binario en $BIN"

# ------------------------------------------------------------------ symlink+PATH
step "Instalando el binario"
mkdir -p "$HOME/.local/bin"
ln -sf "$BIN" "$BIN_LINK"
ok "Enlazado en $BIN_LINK"

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *)
    warn "~/.local/bin no está en tu PATH."
    read -r -p "¿Añadirlo a ~/.zprofile? [S/n] " ans
    if [[ ! "${ans:-s}" =~ ^[nN] ]]; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zprofile"
      ok "Añadido a ~/.zprofile (aplica al abrir un terminal nuevo)"
    fi
    ;;
esac

# ---------------------------------------------------------------------- ajustes
step "Ajustes iniciales"
mkdir -p "$SETTINGS_DIR" "$HOME/.local/state/conbarai" "$HOME/.local/share/conbarai"
if [[ ! -f "$SETTINGS_DIR/settings.json" ]]; then
  read -r -p "Carpeta de trabajo por defecto [$HOME/Documents/ConBarAI]: " workdir
  workdir="${workdir:-$HOME/Documents/ConBarAI}"
  mkdir -p "$workdir"
  # Sin comillas dobles ni contrabarras: settings.json es JSON y aquí solo caben rutas.
  workdir="${workdir//\"/}"
  workdir="${workdir//\\/}"
  cat > "$SETTINGS_DIR/settings.json" <<EOF
{
  "autohide" : true,
  "autostart" : true,
  "workdir" : "$workdir",
  "width" : 0.34,
  "height" : 0.62,
  "opacity" : 0.97,
  "keybinding" : "alt+return",
  "theme" : "tokyo-night",
  "font" : "auto",
  "font_size" : 12,
  "continue_session" : true,
  "diag_pos" : "side",
  "update_check" : true,
  "crash_watch" : true,
  "crash_analyze" : true,
  "crash_dedupe" : 60,
  "crash_poll" : 8,
  "island_pill" : true
}
EOF
  chmod 600 "$SETTINGS_DIR/settings.json"
  ok "settings.json creado"
else
  ok "settings.json ya existía (se conserva)"
fi

# ------------------------------------------------------------- opencode NaN
step "OpenCode propio del panel (NaN · deepseek-v4-flash)"
"$BIN" occonfig
if ! grep -q "^NAN_API_KEY=sk-" "$SETTINGS_DIR/auth" 2>/dev/null; then
  printf "API key de NaN (https://api.nan.builders, empieza por sk-): "
  read -rs keyinput
  printf "\n"
  if [[ "$keyinput" == sk-* && ${#keyinput} -gt 8 ]]; then
    printf '%s' "$keyinput" | "$BIN" key set
    unset keyinput
  else
    warn "Key inválida o vacía: el panel usará el opencode del sistema hasta que guardes una."
  fi
fi

# ----------------------------------------------------------------------- skill
step "Instalando la skill macos-operator"
"$BIN" skill install "$REPO_DIR"
ok "Skill canónica en ~/.local/share/conbarai/skills/macos-operator"

# -------------------------------------------------------------------- launchd
step "Registrando autostart (launchd)"
mkdir -p "$LAUNCH_DIR"
[[ -f "$PANEL_PLIST" ]] && launchctl bootout "gui/$(id -u)" "$PANEL_PLIST" 2>/dev/null || true
[[ -f "$WATCH_PLIST" ]] && launchctl bootout "gui/$(id -u)" "$WATCH_PLIST" 2>/dev/null || true

cat > "$PANEL_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.conbarai.panel</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN</string>
        <string>panel</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$HOME/.opencode/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
    <key>RunAtLoad</key><true/>
    <key>ProcessType</key><string>Interactive</string>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict>
</plist>
EOF

cat > "$WATCH_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.conbarai.watch</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN</string>
        <string>watch</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ProcessType</key><string>Background</string>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
    <key>StandardErrorPath</key><string>$HOME/.local/state/conbarai/watch.log</string>
</dict>
</plist>
EOF

launchctl bootstrap "gui/$(id -u)" "$PANEL_PLIST"
launchctl bootstrap "gui/$(id -u)" "$WATCH_PLIST"
ok "LaunchAgents activos: com.conbarai.panel + com.conbarai.watch"

# ----------------------------------------------------------------------- fin
printf "\n${GREEN}ConBarAI instalado.${NC}\n\n"
echo "  • Pulsa ⌥⏎ (o toca la píldora bajo el island) para desplegar la consola."
echo "  • El icono de la barra de menús tiene sesiones, temas y el cambio de atajo."
echo "  • El vigilante de crashes ya está leyendo DiagnosticReports."
echo "  • Ayuda completa: conbarai help"
echo
warn "Si ~/.local/bin no estaba en el PATH, el atajo funciona igual: el panel ya está corriendo."
