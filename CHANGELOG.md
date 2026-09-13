# Changelog

## 1.5.3 — 2026-09-13

### Cambiado
- **Cero notificaciones del sistema — regla de producto**. Ninguna
  notificación puede aparecer jamás: el aviso de ConBarAI es el punto ámbar
  bajo el notch. Los intentos previos fallaban (osascript abría el Editor de
  Scripts; las nativas publicadas desde procesos CLI —hooks de tmux— se
  atribuían a Editor de Scripts al pulsarlas). `Shell.notify` es un no-op.

## 1.5.2 — 2026-09-13

### Corregido
- **Adiós al "gestor de scripts"**: los avisos (agente pide atención,
  crashes, actualizaciones) iban por `osascript`, que dispara el prompt de
  permisos de Automatización al abrir/cerrar la isla — y sin Acceso a
  Disco Completo no funcionaba. Ahora son notificaciones nativas
  (UserNotifications): el sistema pregunta UNA vez "¿ConBarAI puede enviar
  notificaciones?", como cualquier app de mensajería. Sin AppleScript, sin
  osascript, sin permisos de disco.

## 1.5.1 — 2026-09-13

### Corregido
- **`conbarai update` fallaba al instalar**: el punto de montaje del DMG se
  extraía con grep del plist de hdiutil y arrastraba `</string>` en la ruta
  (ditto no encontraba el .app). Ahora monta en un punto fijo propio y no
  parsea nada. El DMG de la 1.5.0 traía este fallo: actualiza a la 1.5.1.

## 1.5.0 — 2026-09-13

### Añadido
- **Auto-instalación de dependencias (m6)**: si falta `pi` o `tmux`, la isla
  abre una portada que ofrece instalarlos por su canal oficial (Homebrew para
  tmux, npm para pi) con un botón, sin salir de la consola. `conbarai setup`
  y el nuevo `conbarai deps` hacen lo mismo por terminal. Si no hay gestor
  de paquetes, ConBarAI no descarga nada por su cuenta: enlaza a brew.sh o
  nodejs.org para que lo instale el usuario.
- Pie de README actualizado a Apple silicon M1–M6.

## 1.4.0 — 2026-09-13

### Añadido
- **DMG instalable**: `scripts/package-dmg.sh` monta ConBarAI.app (icono
  propio, LSUIElement, firma ad-hoc, skills de serie en el bundle) en un DMG
  drag-to-install. Al primer arranque desde /Applications se auto-configura
  (LaunchAgents, skills, `~/.local/bin/conbarai`) — instalar = arrastrar y
  doble clic.
- **Auto-actualización nativa** (el AppImage de Ubuntu, versión macOS):
  `conbarai update [--check]` consulta GitHub Releases, descarga el DMG
  (solo https contra hosts de GitHub), sustituye el .app con relevo atómico y
  rollback, y relanza los agentes. El tray dispara la actualización solo.
- Icono ConBarAI generado (`scripts/make-icon.swift`): la isla con el punto
  ámbar y el prompt `>_`.
- README de producto en español e inglés con capturas reales
  (`docs/capturas/`), y workflow de GitHub que publica el DMG en cada tag.

## 1.3.0 — 2026-09-13

### Añadido
- Skill **mac-gui-pilot**: bucle ver→actuar→verificar para computer-use
  (screencapture + lectura de imagen, System Events, cliclick como último
  recurso, escala Retina, permisos TCC por acción, sondeos en vez de sleeps).
- Skill **conbarai-ops**: autodiagnóstico del propio ConBarAI (LaunchAgents,
  socket tmux, chequeo de salud en una pasada, síntomas→remedios, operaciones
  seguras y prohibiciones).
- macos-operator crece: sección de bucle visual GUI, integración de cliclick
  (jerarquía semántica primero) y puntero de autodiagnóstico. La consola
  carga las TRES skills al arrancar (verificado en el comando del pane).

## 1.2.0 — 2026-09-13

### Añadido
- **Ajustes de proveedores y modelos** (tray → Ajustes → «Proveedores y
  modelos…»): claves API para OpenAI, Anthropic (Claude), NaN, Z.ai, Kimi
  (Moonshot) y x.ai — guardadas en `~/.config/conbarai/auth` (0600) e
  inyectadas por entorno, jamás en el repo.
- **Modelos en vivo**: «Cargar modelos de la API» consulta el `/models` de
  cada proveedor (Bearer o x-api-header según el caso; solo https contra el
  host oficial) con catálogo estático de respaldo si el endpoint no lista.
- **Modelo predeterminado** por UI: se registra el proveedor en el
  `models.json` de pi (con `"apiKey": "$X_API_KEY"`) y la consola se
  releva sola para aplicarlo. `conbarai providers` muestra el estado por CLI.
- Referencia de los 22 comandos slash de pi en el manual (`conbarai help`,
  tray → Ayuda) y pista compacta en la ventana de Ajustes.
- `conbarai settings` abre la ventana de proveedores sin pasar por el tray.

## 1.1.0 — 2026-09-13

El agente pasa a ser **pi (pi.dev)**, más ligero; OpenCode queda de respaldo.

### Corregido
- **La terminal vivía en un tubo de 2×2**: faltaba el `autoresizingMask` de la
  consola dentro de la isla, así que la vista nunca crecía con la ventana y el
  agente (opencode primero, pi después) renderizaba en dos columnas invisibles.
  Verificado a 64×37 con el TUI completo de pi y captura en `proof/`.
- Autoocultado por defecto DESACTIVADO: hay apps que roban el foco sin parar y
  la isla se plegaba sola segundos después de abrirse. Se pliega a demanda
  (⌥⏎ / ⌘W / clic en el island); el ajuste sigue en el tray.
- Clientes tmux huérfanos desprendidos en cada arranque y salida limpia: un
  cliente muerto con tamaño píldora achicaba el pane para los nuevos.

### Añadido
- Agente pi por defecto en la consola (`pi -c --model nan/deepseek-v4-flash
  --skill macos-operator --offline --no-extensions`), con `-a` para confiar
  los archivos del proyecto y continuación de sesión por carpeta. La isla
  arranca AISLADA del pi global del usuario (sin sus extensiones ni banners);
  toggle en el tray para heredarlas. Selección Auto/Pi/OpenCode en el tray.
  Precalentado: pi arranca al lanzar el panel, no al abrir la isla.
- `~/.pi/agent/models.json` se extiende por fusión con el provider NaN
  (`api.nan.builders`): deepseek-v4-flash, qwen3.6, qwen3.8-flash, glm5.3-flash,
  mimo-v2.5, gemma4. Los providers existentes del usuario se conservan.
- La skill se carga al vuelo con `--skill`: adiós a los symlinks en el workdir.
- Aviso de actividad: `monitor-activity` en el tmux del panel — el punto ámbar
  asoma bajo el island cuando el agente responde con la consola escondida
  (la campana sigue notificando).
- Skill macos-operator reescrita como asistente/operador: caja de mando para
  controlar el Mac (System Events, Shortcuts, defaults, open, Finder, red)
  además de la operación y forense existentes.
- Crash-run sobre `pi -p --no-tools`: análisis sin herramientas, solo
  evidencia incrustada (respaldo con la config read-only de opencode).
- Marca de la casa: splash "Console Bar AI — by 686f6c61" al abrir la isla
  (se desvanece solo) y "Console Bar AI" permanente en la cabecera con el
  acento del tema. Nota técnica: pi borra el scrollback al redimensionarse,
  así que los banners impresos en el terminal mueren en el primer resize —
  la marca vive en la UI de la isla.
- Al plegar, el cliente tmux se desprende y el precalentado crea la sesión
  desacoplada a 100×30: el pane nunca vuelve a triturarse a tamaño píldora
  y el scrollback se conserva.
- Ajustes nuevos: `agent`, `model` y `agent_extensions`. Modo diagnóstico:
  `CONBARAI_SNAPSHOT` (autocaptura de la isla) y `CONBARAI_DEBUG` (log de
  foco/autoocultado). ⌘N = conversación nueva (consola limpia).

## 1.0.0 — 2026-09-12

Primer port nativo a macOS de ubuntu-ConBarAI.

### Añadido
- Isla: NSPanel anclado al notch que colapsa en píldora (punto de estado,
  contador de avisos) y se expande en consola con animación.
- Terminal real vía SwiftTerm + tmux en socket dedicado (`-L conbarai`):
  sesiones `oc`/`oc-<slug>` que sobreviven a todo, `opencode -c` para
  continuar, `remain-on-exit` para reinicios limpios.
- Atajo global ⌥⏎ (Carbon), grabable desde el tray; ⌘W esconde; autoocultar
  al perder foco.
- Tray de barra de menús: sesiones, carpeta de trabajo, temas (Tokyo Night,
  Catppuccin, Dracula, Gruvbox), opacidad, manual integrado estilo man.
- Uso por carpeta leído de `~/.local/share/opencode/opencode.db` en modo
  solo-lectura (tokens + coste) en la cabecera.
- Vigilante de crashes: informes `.ips` de DiagnosticReports, dedupe por
  incidente y por ventana temporal, clasificación crash/OOM/hang/panic,
  reinicios inesperados por `kern.boottime` + shutdown cause, silenciado por
  programa (`conbarai mute`).
- Analizador: evidencia read-only incrustada en el prompt + `opencode run`
  headless → informe en español de 5 secciones guardado en
  `~/.local/state/conbarai/crash/`.
- Skill `macos-operator`: adaptación de ubuntu-operator (brew, launchd,
  log show, diskutil, TCC, playbooks de recuperación, protocolo ConBarAI).
- Instalador/desinstalador + LaunchAgents de usuario; tests unitarios de
  sesiones, atajos, ajustes y clasificación de crashes.
