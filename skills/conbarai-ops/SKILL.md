---
name: conbarai-ops
description: 'Operación y autodiagnóstico del propio ConBarAI en macOS — la consola-isla, su agente pi, el tmux dedicado, los LaunchAgents, los proveedores/modelos y el vigilante de crashes. Se activa cuando el usuario pregunta por el estado de la consola, la isla no responde, el agente no arranca o cambia de modelo, o hay que reinstalar, actualizar o limpiar ConBarAI.'
---

# conbarai-ops

El médico de cabecera de la propia consola. Regla heredada de macos-operator:
**diagnosticar antes de tocar, y saber deshacer**.

## 1. Mapa de la casa

| Pieza | Dónde vive |
|---|---|
| Panel (isla + tray + atajos) | proceso `conbarai panel`, LaunchAgent `com.conbarai.panel` |
| Vigilante de crashes | proceso `conbarai watch`, LaunchAgent `com.conbarai.watch` |
| Agente | pi (pi.dev) dentro de tmux, **socket dedicado** `conbarai` |
| Ajustes | `~/.config/conbarai/settings.json` (0600) |
| Claves API | `~/.config/conbarai/auth` (0600, `PROVEEDOR_API_KEY=…`) |
| Config pi (providers NaN etc.) | `~/.pi/agent/models.json` (se fusiona, no se pisa) |
| tmux conf + hooks | `~/.config/conbarai/tmux.conf`, `~/.local/state/conbarai/alert-hook.zsh` |
| Estado: avisos/crashes | `~/.local/state/conbarai/` |
| Skills cargadas | `~/.local/share/conbarai/skills/` (copia canónica) |
| Log de debug | `/tmp/conbarai-panel.log` (solo si se arrancó con CONBARAI_DEBUG=1) |

## 2. Chequeo de salud (una pasada)

```bash
pgrep -fl "conbarai panel" || echo "PANEL CAÍDO"
launchctl print gui/$(id -u)/com.conbarai.panel 2>/dev/null | grep -E "state|last exit"
tmux -L conbarai ls                       # sesiones oc/oc-*
tmux -L conbarai display-message -p -t oc '#{window_width}x#{window_height}'
tail -20 /tmp/conbarai-panel.log 2>/dev/null
conbarai providers                        # claves y modelo por defecto
```

Síntomas clásicos:

| Síntoma | Causa probable | Remedio |
|---|---|---|
| Isla no abre | panel muerto | `launchctl kickstart -k gui/$(id -u)/com.conbarai.panel` o `.build/release/conbarai panel &` |
| Se abre y se pliega sola | autohide activo + foco robado | Ajustes → autoocultar off (ya por defecto) |
| No se puede escribir | foco/first responder | clic dentro de la consola; ⌥⏎ de nuevo |
| TUI triturado (columnas de 2 chars) | cliente tmux huérfano achicando el pane | `tmux -L conbarai detach-client -a` (el arranque ya lo hace) |
| El agente no arranca | pi no en PATH / clave ausente | `which pi`; `conbarai providers` |
| Modelo no cambia | settings.json viejo | Ajustes → Proveedores → predeterminado |
| Sin avisos ámbar | hooks no registrados | el attach los re-registra: ⌘N o reiniciar consola |

## 3. Operaciones seguras

- **Reiniciar consola** (mantiene charla): tray → «Reiniciar agente».
- **Conversación nueva**: ⌘N. La anterior se recupera con `pi -r` dentro.
- **Reiniciar el panel** sin perder sesiones: kickstart del LaunchAgent — las
  charlas viven en el servidor tmux, no en el panel.
- **Actualizar tras recompilar**: `swift build -c release` + kickstart del
  panel; el watcher se releva solo (KeepAlive).

## 4. Lo que NO se hace sin preguntar

- `tmux -L conbarai kill-server` — mata TODAS las conversaciones.
- Editar a mano `~/.pi/agent/models.json` entero — se fusiona por software;
  tocar solo el bloque del proveedor propio si acaso.
- Borrar `~/.local/state/conbarai/crash/` — son los informes del usuario.
- `pkill` del panel sin kickstart posterior — deja al usuario sin isla.

## 5. Datos y diagnóstico rápido

```bash
conbarai --version && conbarai providers && conbarai occonfig | head -5
ls -la ~/.config/conbarai/                # perms 0600 en settings y auth
stat -f "%Lp %N" ~/.pi/agent/models.json  # 600 esperable
tmux -L conbarai list-panes -a -F '#{session_name} #{window_width}x#{window_height} #{pane_current_command}'
```

Todo estado intermedio (avisos, pending de análisis, watch.json) es
reconstruible: se puede borrar con seguridad salvo los informes citados.
