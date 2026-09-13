import Foundation

/// Análisis forense de un crash: recopila evidencia con una lista cerrada de
/// comandos de solo lectura y pide a OpenCode (headless) un informe en español.
/// El agente NO ejecuta nada: toda la evidencia va incrustada en el prompt.
/// La salida estándar de la ejecución ES el informe guardado (paridad con Ubuntu).
enum CrashAnalyzer {
    /// Lista cerrada de diagnóstico; nada de ediciones ni red para el análisis.
    static let allowlist: [(label: String, cmd: String)] = [
        ("Sistema", "/usr/bin/sw_vers; /usr/sbin/system_profiler SPHardwareDataType 2>/dev/null | grep -E 'Model|Chip|Cores|Memory'"),
        ("Kernel", "/usr/sbin/sysctl kern.ostype kern.osrelease hw.memsize hw.model; /usr/bin/uname -a"),
        ("Presión de memoria", "/usr/sbin/sysctl vm.vm_page_free_count vm.pages; /usr/sbin/memory_pressure -Q 2>/dev/null || true"),
        ("Energía (portátil/batería)", "/usr/bin/pmset -g"),
        ("Disco", "/bin/df -h / /System/Volumes/Data 2>/dev/null | head -6"),
        ("Procesos con más RAM", "/bin/ps axo rss,pid,comm | /usr/bin/sort -rn | head -12"),
        ("Carga", "/usr/bin/uptime"),
        ("Logs alrededor del fallo", "/usr/bin/log show --last 30m --style compact --predicate 'process == \"__PROC__\"' 2>/dev/null | tail -60"),
    ]

    static func cli(_ args: [String]) {
        var file: String?
        var parse = args.dropFirst()
        while let a = parse.popFirst() {
            if a == "--file" { file = parse.popFirst() }
        }
        guard let file else {
            print("uso: conbarai crash-run --file <informe.ips>")
            exit(64)
        }
        guard let event = CrashEvent.parse(file: file) else {
            print("conbarai crash-run: no pude parsear \(file)")
            exit(1)
        }
        guard let report = analyze(event: event) else {
            print("conbarai crash-run: opencode no está disponible o no respondió; ejecuta `curl -fsSL https://opencode.ai/install | bash` y reintenta")
            CrashWatcher.appendPending(file)
            exit(1)
        }
        let path = save(report: report, event: event)
        print(path)
        Shell.notify("Informe de crash listo: \((path as NSString).lastPathComponent)")
    }

    static func analyze(event: CrashEvent) -> String? {
        switch Agent.resolve(setting: nil) {
        case .pi:
            return analyzeWithPi(event: event)
        case .opencode:
            return analyzeWithOpenCode(event: event)
        case nil:
            return nil
        }
    }

    /// pi -p con TODO desactivado: el agente solo razona sobre la evidencia
    /// incrustada (más estricto incluso que el allowlist de Ubuntu) y con la
    /// skill macos-operator cargada para el formato del informe.
    static func analyzeWithPi(event: CrashEvent) -> String? {
        guard let pi = Shell.piPath() else { return nil }
        let ipsExcerpt = excerpt(of: event.file, maxLines: 90)
        let evidence = collectEvidence(for: event)
        let prompt = crashPrompt(event: event, ipsExcerpt: ipsExcerpt, evidence: evidence)

        var args = ["-p", "--no-tools", "--no-extensions", "--no-context-files",
                    "--no-session", "--model", "nan/deepseek-v4-flash"]
        if FileManager.default.fileExists(atPath: "\(Paths.skillsDir)/\(Paths.bundledSkill)/SKILL.md") {
            args += ["--skill", "\(Paths.skillsDir)/\(Paths.bundledSkill)"]
        }
        args.append(prompt)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: pi)
        p.arguments = args
        p.currentDirectoryURL = URL(fileURLWithPath: Paths.crashDir)
        var env = ProcessInfo.processInfo.environment
        if let key = OpenCodeConfig.apiKey() { env["NAN_API_KEY"] = key }
        p.environment = env
        let outPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice

        do { try p.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(300)
        while p.isRunning && Date() < deadline { usleep(200_000) }
        if p.isRunning {
            p.terminate()
            return nil
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let out = String(data: data, encoding: .utf8),
              out.trimmingCharacters(in: .whitespacesAndNewlines).count > 80 else { return nil }
        return out
    }

    /// Respaldo con opencode run y su config read-only (conbarai-crash.json).
    static func analyzeWithOpenCode(event: CrashEvent) -> String? {
        guard let opencode = Shell.opencodePath() else { return nil }
        let ipsExcerpt = excerpt(of: event.file, maxLines: 90)
        let evidence = collectEvidence(for: event)
        let prompt = crashPrompt(event: event, ipsExcerpt: ipsExcerpt, evidence: evidence)

        // opencode run con SU config de crashes: NaN, skill cargada y permisos
        // denegados salvo la allowlist read-only (paridad con conbarai-crash.json).
        let workDir = Paths.crashDir
        try? FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
        let crashConfig = OpenCodeConfig.ensureCrashConfig()
        var env = ProcessInfo.processInfo.environment
        env["OPENCODE_CONFIG"] = crashConfig
        if let key = OpenCodeConfig.apiKey() { env["NAN_API_KEY"] = key }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: opencode)
        p.arguments = ["run", "--pure", prompt]
        p.currentDirectoryURL = URL(fileURLWithPath: workDir)
        p.environment = env
        let outPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice

        do { try p.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(300)
        while p.isRunning && Date() < deadline { usleep(200_000) }
        if p.isRunning {
            p.terminate()
            return nil
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let out = String(data: data, encoding: .utf8),
              out.trimmingCharacters(in: .whitespacesAndNewlines).count > 80 else { return nil }
        return out
    }

    /// Prompt forense común (las reglas y el formato de 5 secciones).
    static func crashPrompt(event: CrashEvent, ipsExcerpt: String, evidence: String) -> String {
        """
        Eres un analista forense de macOS trabajando para ConBarAI. Analiza este fallo
        y escribe el informe final en ESPAÑOL.

        REGLAS FIJAS:
        - No tienes herramientas: TODA la evidencia está abajo.
        - No inventes símbolos, versiones ni causas: si no está en la evidencia, márcalo como hipótesis.
        - Separa hechos probados de inferencias.
        - Si el fallo es del propio sistema (no de una app del usuario), dilo claramente.
        - El arreglo debe ser reversible: cada paso con su comando de deshacer.
        - Responde únicamente con el informe, sin preámbulos.

        FORMATO (5 secciones, exactamente estos títulos):
        ## Qué pasó
        ## Evidencia
        ## Causa probable
        ## Arreglo (con rollbacks)
        ## Cómo evitarlo

        === INFORME DEL SISTEMA (.ips, extracto) ===
        \(ipsExcerpt)

        === RESUMEN PARSEADO ===
        \(event.summary)

        === DIAGNÓSTICO DEL SISTEMA (solo lectura, recogido ahora) ===
        \(evidence)
        """
    }

    /// Lee el .ips en bruto acotado (las pilas completas no caben en el prompt).
    static func excerpt(of file: String, maxLines: Int) -> String {
        guard let raw = try? String(contentsOfFile: file, encoding: .utf8) else { return "(ilegible)" }
        return raw.split(separator: "\n").prefix(maxLines).joined(separator: "\n")
    }

    /// Ejecuta la lista cerrada de comandos read-only y concatena su salida.
    static func collectEvidence(for event: CrashEvent) -> String {
        var blocks: [String] = []
        // Neutraliza comillas, $ y backticks antes de interpolar en el predicate.
        let proc = event.procName.replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "`", with: "")
        for entry in allowlist {
            let cmd = entry.cmd.replacingOccurrences(of: "__PROC__", with: proc)
            let r = Shell.run(cmd, timeout: 120)
            let body = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                blocks.append("### \(entry.label)\n\(String(body.prefix(4000)))")
            }
        }
        return blocks.joined(separator: "\n\n")
    }

    static func save(report: String, event: CrashEvent) -> String {
        Paths.ensureStateDirs()
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        let safe = Sessions.slug(event.procName)
        let path = "\(Paths.crashDir)/\(f.string(from: event.faultingTime ?? Date()))-\(safe).md"
        let header = """
        <!-- ConBarAI crash-run · fuente: \(event.file) -->
        <!-- incident: \(event.incidentID) -->

        """
        FileManager.default.createFile(atPath: path,
                                       contents: (header + report).data(using: .utf8),
                                       attributes: [.posixPermissions: 0o600])
        return path
    }
}
