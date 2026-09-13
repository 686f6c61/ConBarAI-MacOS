---
name: mac-gui-pilot
description: 'Piloto de GUI para macOS — el bucle ver→actuar→verificar para controlar cualquier aplicación con capturas de pantalla, System Events y cliclick (input sintético). Se activa cuando hay que operar interfaces gráficas (pulsar botones, rellenar formularios, arrastrar, automatizar apps sin soporte de scripting) o verificar visualmente el resultado de una acción.'
---

# mac-gui-pilot

Táctica de computer-use para macOS. La política (qué se puede y qué no tocar)
vive en `macos-operator`; aquí es el cómo.

Regla de oro: **nunca actúes a ciegas**. Cada acción GUI se ejecuta dentro de
un bucle cerrado:

```
OBSERVAR → PLANIFICAR → ACTUAR → VERIFICAR → (repetir)
```

## 1. Observar

```bash
screencapture -x /tmp/gui-$(date +%s).png      # pantalla completa, sin sonido
screencapture -x -R20,40,600,400 /tmp/region.png  # región (x,y,w,h en puntos)
screencapture -x -l$(osascript -e 'tell app "Safari" to id of window 1' 2>/dev/null) /tmp/win.png
```

Luego MIRA la captura: refiénciala como archivo en tu propio mensaje
(`@/tmp/gui-....png`) — el modelo en uso acepta imágenes. Describe qué
controles ves antes de tocar nada.

**Escala Retina**: las capturas vienen a 2× — un píxel de la imagen = 0,5
puntos de pantalla. Para clicar el botón visto en (x_px, y_px), las
coordenadas de pantalla son (x_px/2, y_px/2) en una pantalla estándar.
Verifícalo la primera vez con un elemento de posición conocida (icono de la
esquina).

**Multi-pantalla**: `screencapture -D <n>` captura la pantalla n (1 = principal
con la barra de menús). Las coordenadas de cliclick son globales: suma el
origen de la pantalla destino.

## 2. Planificar: jerarquía de acceso (de mejor a peor)

1. **Interfaz de la app** (URLs, AppleScript propio): `open -a Safari URL`,
   `tell app "Finder" to …` — sin UI, sin permisos, verificable.
2. **System Events (Accessibility)**: elementos por nombre/rol, no por píxeles.
   Requiere permiso de Accesibilidad para el proceso padre (ConBarAI).
3. **cliclick / coordenadas**: último recurso, cuando la app no expone nada
   (canvas, juegos, algunos Electron). Siempre anclado a una captura reciente.

## 3. Actuar

### System Events primero

```bash
osascript <<'EOF'
tell application "System Events" to tell process "Notas"
  click button "Nuevo" of group 1 of toolbar 1 of window 1
  keystroke "Hola"
end tell
EOF
```

Trucos: `UI elements of window 1` y `entire contents` para explorar el árbol;
`value of attribute "AXDescription"` cuando no hay nombre; `perform action
"AXPress"` como click universal.

### cliclick cuando no queda otra

```bash
cliclick c:500,300            # clic simple en x=500 y=300
cliclick dc:500,300           # doble clic
cliclick dd:500,300 du:600,300  # arrastrar de (500,300) a (600,300)
cliclick t:"hola mundo"       # escribir texto
cliclick kd:cmd t:c ku:cmd    # ⌘C
cliclick m:100,200            # mover el ratón
cliclick w:400                # esperar 400 ms entre acciones
```

Nunca compongas clics de una captura con más de unos segundos: la UI cambia.
Re-captura si dudaste.

## 4. Verificar (obligatorio)

Después de cada acción con consecuencias:

```bash
screencapture -x /tmp/gui-after.png
```

Y comprueba lo esperable: el diálogo se cerró, el texto aparece, la ventana
cambió. Métodos objetivos cuando el modelo no pueda mirar:

- `cmp -s antes.png después.png && echo "sin cambios"` — identical = sospecha.
- Región acotada con `-R` alrededor del elemento tocado.
- Estado por AppleScript: `exists sheet 1 of window 1`, `value of text field…`.

**Sondear, no dormir**: esperas con bucle corto hasta que la condición se
cumpla (máx ~10 s), no `sleep 5` fijos:

```bash
for i in {1..20}; do
  osascript -e 'tell app "System Events" to exists window 1 of process "X"' \
    && break; sleep 0.5
done
```

## 5. Permisos (TCC) — qué pide cada cosa

| Acción | Permiso que necesita el proceso padre |
|---|---|
| `screencapture` con contenido de ventanas | Grabación de Pantalla |
| System Events (AX) | Accesibilidad |
| Controlar otra app por AppleScript | Automatización (diálogo por app) |
| `cliclick` (eventos sintéticos) | Accesibilidad |
| Carpetas ajenas al panel (Documentos/Escritorio/Descargas) | Archivos y carpetas |

Si algo falla en silencio, comprueba primero Privacidad y seguridad — y guiar
al usuario para concederlo; jamás intentar saltárselo.

## 6. Prohibido

- Clics a ciegas sin captura reciente que los justifique.
- `sleep` fijos largos en lugar de sondear.
- Lanzar apps que nadie pidió.
- Escribir texto sensible visible en pantalla sin pedir confirmación.
- Dar por buena una acción sin la captura de verificación.
