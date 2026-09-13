import Foundation

enum Help {
    static let manual = """
    CONBARAI(1)                 Manual de usuario                CONBARAI(1)

    NOMBRE
        conbarai — consola de OpenCode que se esconde debajo del island del Mac

    SINOPSIS
        conbarai [panel | watch | crash-run | alert | skill | usage | help]

    DESCRIPCIÓN
        ConBarAI es el port nativo de macOS de la versión Ubuntu. Una consola
        con el agente pi (pi.dev) —o OpenCode de respaldo— se esconde DENTRO
        de la zona del notch (negro sobre negro: no se ve) y se despliega con
        el atajo global (por defecto ⌥⏎) o con un clic sobre el propio
        island. Solo asoma un punto ámbar debajo del notch cuando el agente
        pide atención o responde con la isla escondida. Las sesiones corren
        dentro de tmux con socket dedicado (conbarai), así que sobreviven a
        esconder el panel, cerrarlo o reiniciar.

        Sin ventanas nuevas, sin perder el flujo.

    SUBCOMANDOS
        panel            Arranca la isla (Lanzado por launchd en el autostart).
        watch            Vigilante de crashes (LaunchAgent aparte).
        crash-run        Analiza un informe .ips y escribe un informe en español.
                         Uso: conbarai crash-run --file <ruta.ips>
        alert            Uso interno del hook tmux: conbarai alert <sesión>.
        skill            Gestiona la skill macos-operator:
                         conbarai skill install | link <carpeta> | list
        usage            Muestra tokens y coste de la carpeta actual.
        help             Este manual.
        --version        Versión instalada.

    COMANDOS SLASH (dentro de la consola, anteponiendo /)
        /new            Sesión nueva (equivale a ⌘N).
        /model          Selector de modelo (también Ctrl+L).
        /thinking       Nivel de razonamiento (off…max).
        /scoped-models  Elegir modelos para ciclar con Ctrl+P.
        /compact        Compactar el contexto a mano.
        /resume         Reanudar otra sesión anterior.
        /fork           Bifurcar la sesión desde un mensaje previo.
        /clone          Duplicar la sesión en el punto actual.
        /tree           Navegar el árbol de la sesión (ramas).
        /session        Info y estadísticas de la sesión.
        /name           Poner nombre a la sesión.
        /copy           Copiar el último mensaje del agente.
        /export         Exportar sesión (HTML o .jsonl).
        /import         Importar y reanudar desde JSONL.
        /share          Compartir sesión como gist secreto de GitHub.
        /settings       Menú de ajustes de pi.
        /login /logout  Autenticación de proveedores en pi.
        /trust          Recordar la decisión de confianza del proyecto.
        /reload         Recargar extensiones/skills/temas/contexto.
        /hotkeys        Todos los atajos de teclado de pi.
        /changelog      Novedades de la versión de pi.
        Nota: los comandos de extensiones (Alfred-Pi: /providers, /doctor,
        /domains, /usage, /stack…) solo cargan si activas «Cargar tus
        extensiones de pi» en Ajustes.

    ATAJOS
        ⌥⏎ (configurable)  Mostrar/ocultar la consola.
        Clic en el island   Mostrar/ocultar la consola.
        ⌘N o ⌘K             Conversación nueva: contexto, pantalla y scrollback
                            limpios (pi repinta su historial desde memoria, así
                            que limpiar solo la pantalla no persiste). La
                            conversación anterior se recupera con "pi -r".
        ⌘W                  Esconder la consola (Esc queda para las TUI).

    ARCHIVOS
        ~/.config/conbarai/settings.json     Ajustes (0600): agente, modelo…
        ~/.config/conbarai/auth              Claves API (0600): NAN, OpenAI,
                                             Claude, Z.ai, Kimi, x.ai. Se
                                             gestionan en Ajustes →
                                             «Proveedores y modelos…».
        ~/.pi/agent/models.json              Provider NaN fusionado (pi).
        ~/.config/conbarai/opencode.json     Config OpenCode de respaldo.
        ~/.config/conbarai/tmux.conf         Configuración tmux del panel.
        ~/.local/state/conbarai/             Estado, avisos y crashes.
        ~/.local/share/conbarai/skills/      Skill macos-operator (copia canónica).

    CRASHES
        El vigilante observa ~/Library/Logs/DiagnosticReports (los informes .ips
        del sistema). Ante un fallo deduplica, respeta silenciados por programa
        y, si está activado, genera un informe con OpenCode en modo solo
        lectura. Los informes quedan en ~/.local/state/conbarai/crash/.

    VÉASE TAMBIÉN
        tmux(1), opencode(1), launchctl(1)

    ConBarAI \(Paths.version) · macOS · MIT
    """
}
