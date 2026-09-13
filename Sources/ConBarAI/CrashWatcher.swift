import Foundation

/// Vigilante de fallos: lee los informes .ips de ~/Library/Logs/DiagnosticReports
/// (y del sistema), deduplica, respeta silenciados por programa, detecta OOM,
/// cuelgues y reinicios inesperados, y lanza el análisis con IA.
/// Es el equivalente macOS de oc-crash-watch + journald.
enum CrashWatcher {
    struct WatchState: Codable {
        var seen: [String: Double] = [:]          // incident_id → epoch (se poda a 7 días)
        var lastEvents: [String: Double] = [:]    // proc+clase → epoch (ventana de dedupe)
        var lastBoot = ""
    }

    static func runForever() {
        Paths.ensureStateDirs()
        let settings = Settings.load()
        guard settings.crash_watch else {
            print("conbarai watch: crash_watch=false en settings.json; no hay nada que vigilar")
            exit(0)
        }
        var state = loadState()
        state = reconcileBoot(state: state)

        // Primera pasada en silencio: lo que ya estaba no se notifica.
        scan(state: &state, settings: settings, notifyNew: false)

        // Refresco periódico + eventos de directorio para reaccionar al instante.
        let timer = Timer(timeInterval: settings.crash_poll, repeats: true) { _ in
            var s = loadState()
            s = reconcileBoot(state: s)
            let fresh = Settings.load()
            scan(state: &s, settings: fresh, notifyNew: fresh.crash_watch)
        }
        RunLoop.main.add(timer, forMode: .default)
        watchDirectory(Paths.userCrashReportsDir)
        watchDirectory(Paths.systemCrashReportsDir)

        FileHandle.standardError.write("conbarai watch: vigilando DiagnosticReports\n".data(using: .utf8)!)
        RunLoop.main.run()
    }

    private static func watchDirectory(_ path: String) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            try? fm.createDirectory(atPath: path, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        }
        let rawfd = open(path, O_EVTONLY)
        guard rawfd >= 0 else { return }
        let fd = rawfd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write], queue: .main)
        source.setEventHandler {
            source.suspend()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                var s = loadState()
                let fresh = Settings.load()
                scan(state: &s, settings: fresh, notifyNew: fresh.crash_watch)
                source.resume()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
    }

    // MARK: - Escaneo

    static func scan(state: inout WatchState, settings: Settings, notifyNew: Bool) {
        let now = Date().timeIntervalSince1970
        state.seen = state.seen.filter { now - $0.value < 7 * 86400 }
        state.lastEvents = state.lastEvents.filter { now - $0.value < 86400 }

        var files = crashFiles(in: Paths.userCrashReportsDir) + crashFiles(in: Paths.systemCrashReportsDir)
        files.sort { $0.modDate < $1.modDate }
        guard !files.isEmpty else { saveState(state); return }

        for f in files {
            guard now - f.modDate < 3600 * 24 * 2 else { continue } // solo recientes
            guard let event = CrashEvent.parse(file: f.path) else { continue }

            if let seen = state.seen[event.incidentID], now - seen < 7 * 86400 { continue }

            let dedupeKey = "\(event.procName)|\(event.kind.rawValue)"
            if let last = state.lastEvents[dedupeKey], now - last < settings.crash_dedupe {
                state.seen[event.incidentID] = now
                continue
            }
            state.seen[event.incidentID] = now
            state.lastEvents[dedupeKey] = now

            guard notifyNew else { continue }
            if isMuted(event.procName) { continue }
            handle(event: event, settings: settings)
        }
        saveState(state)
    }

    private struct CrashFile {
        let path: String
        let modDate: TimeInterval
    }

    private static func crashFiles(in dir: String) -> [CrashFile] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        var out: [CrashFile] = []
        for n in names {
            // .spin/.diag/.tailspin/.ips.sync son diagnóstico, no fallos fatales.
            guard n.hasSuffix(".ips") || n.hasSuffix(".panic") else { continue }
            let p = "\(dir)/\(n)"
            let mod = (try? fm.attributesOfItem(atPath: p)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            out.append(CrashFile(path: p, modDate: mod))
        }
        return out
    }

    private static func handle(event: CrashEvent, settings: Settings) {
        switch event.kind {
        case .oom:
            Shell.notify("OOM: el sistema mató a \(event.procName) por falta de memoria")
        case .hang:
            Shell.notify("\(event.procName) se quedó colgado (informe de hang)")
        case .panic:
            Shell.notify("Kernel panic registrado: \(event.incidentID)")
        case .crash:
            Shell.notify("\(event.procName) petó (\(event.signal ?? event.exceptionType ?? "fallo"))")
        }

        guard settings.crash_analyze, let bin = resolvedSelf() else { return }
        let ok = Shell.spawnDetached(bin, ["crash-run", "--file", event.file])
        if !ok { appendPending(event.file) }
    }

    private static func resolvedSelf() -> String? {
        let p = Paths.selfBinaryPath()
        return FileManager.default.isExecutableFile(atPath: p) ? p : Shell.which("conbarai")
    }

    // MARK: - Silenciados y pendientes

    static func isMuted(_ procName: String) -> Bool {
        let safe = Sessions.slug(procName)
        return FileManager.default.fileExists(atPath: "\(Paths.crashIgnoreDir)/\(safe)")
    }

    static func setMuted(_ procName: String, muted: Bool) {
        Paths.ensureStateDirs()
        let safe = Sessions.slug(procName)
        let path = "\(Paths.crashIgnoreDir)/\(safe)"
        if muted {
            FileManager.default.createFile(atPath: path, contents: Data(),
                                           attributes: [.posixPermissions: 0o600])
        } else {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    static func appendPending(_ file: String) {
        var pending = (try? JSONDecoder().decode([String].self,
                        from: Data(contentsOf: URL(fileURLWithPath: Paths.crashPendingFile)))) ?? []
        if !pending.contains(file) { pending.append(file) }
        if let data = try? JSONEncoder().encode(pending) {
            FileManager.default.createFile(atPath: Paths.crashPendingFile, contents: data,
                                           attributes: [.posixPermissions: 0o600])
        }
    }

    // MARK: - Estado y arranques

    static func loadState() -> WatchState {
        guard let data = FileManager.default.contents(atPath: Paths.crashWatchFile),
              let s = try? JSONDecoder().decode(WatchState.self, from: data) else { return WatchState() }
        return s
    }

    static func saveState(_ s: WatchState) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: Paths.crashDir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        if let data = try? JSONEncoder().encode(s) {
            fm.createFile(atPath: Paths.crashWatchFile, contents: data,
                          attributes: [.posixPermissions: 0o600])
        }
    }

    /// Detecta reinicios comparando kern.boottime; si el apagado previo no fue
    /// limpio, lo avisa (código de "Previous shutdown cause" anómalo).
    static func reconcileBoot(state: WatchState) -> WatchState {
        var s = state
        let r = Shell.run("/usr/sbin/sysctl -n kern.boottime", timeout: 5)
        let boot = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !boot.isEmpty else { return s }
        if s.lastBoot.isEmpty {
            s.lastBoot = boot
        } else if s.lastBoot != boot {
            s.lastBoot = boot
            let log = Shell.run("/usr/bin/log show --last boot --style compact " +
                "--predicate 'eventMessage CONTAINS[c] \"Previous shutdown cause\"' 2>/dev/null | tail -1",
                timeout: 90)
            let text = log.out.lowercased()
            let abnormal = text.contains("cause: -") || text.contains("cause: 0") ||
                text.contains("cause: 1") || text.contains("cause: 2")
            if abnormal {
                Shell.notify("Reinicio inesperado detectado — se generará contexto en el próximo informe")
                CrashEvent.persistBootNote(text: log.out.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return s
    }
}

/// Un informe de fallo ya clasificado.
struct CrashEvent {
    enum Kind: String { case crash, oom, hang, panic }

    let file: String
    let incidentID: String
    let procName: String
    let procPath: String
    let signal: String?
    let exceptionType: String?
    let bugType: String?
    let terminationReason: String?
    let faultingTime: Date?
    let kind: Kind

    /// Un .ips son dos JSON: cabecera (1 línea) + carga. Un .panic es texto plano.
    static func parse(file: String) -> CrashEvent? {
        guard let raw = try? String(contentsOfFile: file, encoding: .utf8) else { return nil }
        if file.hasSuffix(".panic") {
            let id = (file as NSString).lastPathComponent
            return CrashEvent(file: file, incidentID: id, procName: "kernel",
                              procPath: "/mach_kernel", signal: nil,
                              exceptionType: "kernel panic", bugType: "panic",
                              terminationReason: nil,
                              faultingTime: mtime(file), kind: .panic)
        }
        let lines = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard lines.count == 2,
              let header = lines[0].data(using: .utf8).flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }),
              let payload = lines[1].data(using: .utf8).flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        else { return nil }

        let incidentID = (header["incident_id"] as? String)
            ?? (payload["incident_id"] as? String)
            ?? (file as NSString).lastPathComponent
        let procName = (payload["procName"] as? String)
            ?? (payload["process"] as? String)
            ?? (payload["CFBundleIdentifier"] as? String)
            ?? "desconocido"
        let procPath = (payload["procPath"] as? String) ?? ""
        let exception = payload["exception"] as? [String: Any]
        let signal = exception?["signal"] as? String
        let exceptionType = exception?["type"] as? String
        let bugType = payload["bug_type"].flatMap { "\($0)" }
        let termination = payload["termination"] as? [String: Any]
        let terminationReason = [
            termination?["indicator"] as? String,
            termination?["reason"] as? String,
            (termination?["byProc"] as? String).map { "by \($0)" },
        ].compactMap { $0 }.joined(separator: " — ")
        let faultingTime = (payload["faultingTime"] as? Double).map { Date(timeIntervalSince1970: $0) }

        return CrashEvent(file: file, incidentID: incidentID, procName: procName, procPath: procPath,
                          signal: signal, exceptionType: exceptionType, bugType: bugType,
                          terminationReason: terminationReason.isEmpty ? nil : terminationReason,
                          faultingTime: faultingTime, kind: classify(signal: signal,
                                                                     exceptionType: exceptionType,
                                                                     bugType: bugType,
                                                                     termination: terminationReason))
    }

    static func classify(signal: String?, exceptionType: String?, bugType: String?, termination: String?) -> Kind {
        let sig = signal?.uppercased() ?? ""
        let term = termination?.lowercased() ?? ""
        let exType = exceptionType?.uppercased() ?? ""
        if term.contains("vm pageshort") || term.contains("vm pages short")
            || term.contains("per-process limit") || term.contains("per-process memory limit")
            || term.contains("memorystatus") || term.contains("jetsam")
            || term.contains("physical memory") || exType.contains("EXC_RESOURCE") {
            return .oom
        }
        if bugType == "288" || exType.contains("HANG") { return .hang }
        return .crash
    }

    private static func mtime(_ file: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: file))?[.modificationDate] as? Date
    }

    static func persistBootNote(text: String) {
        let path = "\(Paths.crashDir)/last-unexpected-reboot.txt"
        FileManager.default.createFile(atPath: path,
                                       contents: text.data(using: .utf8),
                                       attributes: [.posixPermissions: 0o600])
    }

    /// Resumen corto para incrustar en el prompt del analizador.
    var summary: String {
        var s = "Programa: \(procName) (\(procPath.isEmpty ? "ruta desconocida" : procPath))\n"
        if let t = exceptionType { s += "Excepción: \(t)\n" }
        if let sig = signal { s += "Señal: \(sig)\n" }
        if let b = bugType { s += "bug_type: \(b)\n" }
        if let r = terminationReason { s += "Terminación: \(r)\n" }
        if let d = faultingTime {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss ZZ"
            s += "Momento del fallo: \(f.string(from: d))\n"
        }
        s += "Clasificación ConBarAI: \(kind == .crash ? "crash" : kind.rawValue)\n"
        return s
    }
}
