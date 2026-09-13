import XCTest
import Carbon.HIToolbox
@testable import conbarai

final class SessionsTests: XCTestCase {
    func testSlug() {
        XCTAssertEqual(Sessions.slug("Mi Proyecto Genial"), "mi-proyecto-genial")
        XCTAssertEqual(Sessions.slug("C++ y Rust!!"), "c-y-rust")
        XCTAssertEqual(Sessions.slug("///"), "sesion")
        XCTAssertEqual(Sessions.slug("A"), "a")
    }

    func testValidation() {
        XCTAssertNotNil(Sessions.validated("oc"))
        XCTAssertNotNil(Sessions.validated("oc-mi-proyecto"))
        XCTAssertNil(Sessions.validated("OC"))           // mayúsculas fuera
        XCTAssertNil(Sessions.validated("-oc"))          // no empieza por guion
        XCTAssertNil(Sessions.validated("oc;rm -rf"))    // sin metacaracteres
        XCTAssertNil(Sessions.validated(""))
    }

    func testSessionForWorkdir() {
        var s = Settings()
        s.workdir = "/Users/xx/proys"
        XCTAssertEqual(Sessions.session(forWorkdir: "/Users/xx/proys", settings: s), "oc")
        XCTAssertEqual(Sessions.session(forWorkdir: "/Users/xx/proys/Otra Cosa", settings: s),
                       "oc-otra-cosa")
        XCTAssertEqual(Sessions.defaultWorkdir(settings: s), "/Users/xx/proys")
    }
}

final class HotKeyTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(HotKey.parse("alt+return")?.keyCode, UInt32(kVK_Return))
        XCTAssertEqual(HotKey.parse("alt+return")?.carbonMods, optionKey)
        XCTAssertEqual(HotKey.parse("<Super>Return")?.carbonMods, cmdKey)
        XCTAssertEqual(HotKey.parse("cmd+ctrl+space")?.keyCode, UInt32(kVK_Space))
        XCTAssertEqual(HotKey.parse("shift+a")?.carbonMods, shiftKey)
        XCTAssertNil(HotKey.parse("return"))     // sin modificador
        XCTAssertNil(HotKey.parse("alt+ñ"))      // tecla desconocida
        XCTAssertNil(HotKey.parse(""))
    }

    func testDisplay() {
        XCTAssertEqual(HotKey.display("alt+return"), "⌥⏎")
        XCTAssertEqual(HotKey.display("cmd+ctrl+space"), "⌘⌃espacio")
    }
}

final class SettingsTests: XCTestCase {
    func testClamp() {
        var s = Settings()
        s.width = 5; s.height = 0.01; s.opacity = 0.1; s.font_size = 99
        s.clamp()
        XCTAssertEqual(s.width, 0.90)
        XCTAssertEqual(s.height, 0.20)
        XCTAssertEqual(s.opacity, 0.50)
        XCTAssertEqual(s.font_size, 20)
    }
}

final class CrashClassifyTests: XCTestCase {
    func testSegfault() {
        XCTAssertEqual(CrashEvent.classify(signal: "SIGSEGV", exceptionType: "EXC_BAD_ACCESS",
                                            bugType: "309", termination: nil), .crash)
    }

    func testOOM() {
        XCTAssertEqual(CrashEvent.classify(signal: "SIGKILL", exceptionType: nil, bugType: "309",
                                            termination: "VM Pages Short — by kernel"), .oom)
        XCTAssertEqual(CrashEvent.classify(signal: "SIGKILL", exceptionType: nil, bugType: "309",
                                            termination: "per-process memory limit"), .oom)
    }

    func testHang() {
        XCTAssertEqual(CrashEvent.classify(signal: nil, exceptionType: nil, bugType: "288",
                                            termination: nil), .hang)
    }
}

final class UpdateCheckTests: XCTestCase {
    func testSemver() {
        XCTAssertFalse(UpdateCheck.isOutdated(current: "1.0.0", latest: "1.0.0"))
        XCTAssertTrue(UpdateCheck.isOutdated(current: "1.0.0", latest: "1.2.0"))
        XCTAssertFalse(UpdateCheck.isOutdated(current: "2.0.0", latest: "1.9.9"))
        XCTAssertTrue(UpdateCheck.isOutdated(current: "1.0.0", latest: "1.0.1"))
    }
}

final class ProvidersTests: XCTestCase {
    func testParseModelsOpenAI() {
        let json = #"{"object":"list","data":[{"id":"gpt-5.2"},{"id":"o4-mini"}]}"#
        let result = Providers.parseModels(json.data(using: .utf8)!)
        XCTAssertEqual(try? result.get(), ["gpt-5.2", "o4-mini"])
    }

    func testParseModelsAnthropicShape() {
        let json = #"{"data":[{"id":"claude-opus-4","display_name":"Opus"}]}"#
        let result = Providers.parseModels(json.data(using: .utf8)!)
        XCTAssertEqual(try? result.get(), ["claude-opus-4"])
    }

    func testParseModelsGarbage() {
        let result = Providers.parseModels(Data("no soy json".utf8))
        XCTAssertNil(try? result.get())
    }

    func testProviderDefsSanity() {
        XCTAssertEqual(Providers.all.count, 6)
        for p in Providers.all {
            XCTAssertTrue(p.baseURL.hasPrefix("https://"), "\(p.id) debe ser https")
            XCTAssertTrue(p.keyEnv.hasSuffix("_API_KEY"))
            XCTAssertFalse(p.staticModels.isEmpty)
            XCTAssertNotNil(URL(string: p.baseURL + "/models"))
        }
    }
}

final class KeyStoreTests: XCTestCase {
    func testRoundtripEnFicheroTemporal() {
        // Fichero temporal propio: los tests JAMÁS tocan el almacén real del
        // usuario, y los valores son cadenas obviamente falsas que no
        // disparan los escáneres de secretos.
        let tmp = NSTemporaryDirectory() + "conbarai-keystore-test-\(UUID().uuidString).auth"
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        XCTAssertTrue(KeyStore.set(env: "KIMI_API_KEY", value: "prueba-clave-sin-formato-real-1234", at: tmp))
        XCTAssertTrue(KeyStore.set(env: "XAI_API_KEY", value: "otra-prueba-de-clave-5678", at: tmp))
        let all = KeyStore.all(at: tmp)
        XCTAssertEqual(all["KIMI_API_KEY"], "prueba-clave-sin-formato-real-1234")
        XCTAssertEqual(all["XAI_API_KEY"], "otra-prueba-de-clave-5678")
        XCTAssertTrue(KeyStore.set(env: "KIMI_API_KEY", value: "", at: tmp)) // borrar
        XCTAssertNil(KeyStore.all(at: tmp)["KIMI_API_KEY"])
        XCTAssertFalse(KeyStore.set(env: "XAI_API_KEY", value: "corta", at: tmp)) // muy corta
        XCTAssertEqual(KeyStore.mask("una-clave-larguisima-9876543210"), "••••••••3210")
    }
}

final class AgentResolveTests: XCTestCase {
    func testPreferenciaPi() {
        XCTAssertEqual(Agent.resolve(setting: "auto", piInstalled: true, opencodeInstalled: true), .pi)
        XCTAssertEqual(Agent.resolve(setting: "pi", piInstalled: true, opencodeInstalled: false), .pi)
        XCTAssertEqual(Agent.resolve(setting: "opencode", piInstalled: true, opencodeInstalled: true), .opencode)
        XCTAssertNil(Agent.resolve(setting: "pi", piInstalled: false, opencodeInstalled: false))
        XCTAssertNil(Agent.resolve(setting: nil, piInstalled: false, opencodeInstalled: false))
        // Respaldo: sin pi, opencode
        XCTAssertEqual(Agent.resolve(setting: "auto", piInstalled: false, opencodeInstalled: true), .opencode)
    }
}

final class PiConfigTests: XCTestCase {
    func testEnsureProviderFusionaSinRomper() {
        let tmp = NSTemporaryDirectory() + "models-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        // Un proveedor preexistente (el del usuario) que debe sobrevivir.
        let preexistente = """
        {"providers":{"ollama":{"api":"openai-completions","baseUrl":"http://127.0.0.1:11434/v1"}}}
        """
        FileManager.default.createFile(atPath: tmp, contents: preexistente.data(using: .utf8))

        let kimi = Providers.byID("kimi")!
        XCTAssertTrue(PiConfig.ensureProvider(kimi, models: ["kimi-k2", "kimi-k2-turbo"], at: tmp))

        let obj = try! JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: tmp))) as! [String: Any]
        let providers = obj["providers"] as! [String: Any]
        // El suyo sigue…
        XCTAssertNotNil(providers["ollama"])
        // …y el nuestro entra con key por entorno (nunca literal).
        let added = providers["kimi"] as! [String: Any]
        XCTAssertEqual(added["apiKey"] as? String, "$KIMI_API_KEY")
        XCTAssertEqual(added["baseUrl"] as? String, kimi.baseURL)
        let models = added["models"] as! [[String: Any]]
        XCTAssertEqual(models.map { $0["id"] as! String }, ["kimi-k2", "kimi-k2-turbo"])
    }

    func testQuietStartupEnCarpetaTemporal() {
        let workdir = NSTemporaryDirectory() + "wd-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: workdir) }
        XCTAssertTrue(PiConfig.ensureQuietStartup(workdir: workdir))
        let text = try! String(contentsOfFile: "\(workdir)/.pi/settings.json", encoding: .utf8)
        XCTAssertTrue(text.contains("\"quietStartup\" : true"))
        // Idempotente: segunda pasada no rompe.
        XCTAssertTrue(PiConfig.ensureQuietStartup(workdir: workdir))
    }
}

final class SkillInstallerTests: XCTestCase {
    func testInstalaLasTresDesdeElRepoATemporal() {
        let repo = TestEnv.repoRoot
        let dst = NSTemporaryDirectory() + "skills-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: dst) }
        XCTAssertTrue(SkillInstaller.install(from: repo, to: dst))
        for skill in Paths.bundledSkills {
            XCTAssertTrue(FileManager.default.fileExists(atPath: "\(dst)/\(skill)/SKILL.md"),
                          "falta \(skill)")
        }
    }
}

final class UpdaterSecurityTests: XCTestCase {
    func testSoloHostsDeGitHub() {
        XCTAssertTrue(Updater.isAllowedDownloadURL(URL(string: "https://github.com/x/y/releases/download/v1/a.dmg")!))
        XCTAssertTrue(Updater.isAllowedDownloadURL(URL(string: "https://objects.githubusercontent.com/a.dmg")!))
        XCTAssertFalse(Updater.isAllowedDownloadURL(URL(string: "http://github.com/a.dmg")!))         // no https
        XCTAssertFalse(Updater.isAllowedDownloadURL(URL(string: "https://evil.example.com/a.dmg")!))  // host ajeno
        XCTAssertFalse(Updater.isAllowedDownloadURL(URL(string: "https://127.0.0.1/a.dmg")!))         // localhost
    }

    func testDownloadRechazaURLMalaSinRed() {
        // Se rechaza en el guard, sin llegar a tocar la red.
        XCTAssertFalse(Updater.download(URL(string: "https://evil.example.com/a.dmg")!, to: "/tmp/no"))
    }
}

final class CrashAnalyzerTests: XCTestCase {
    func testExcerptRecortaLineas() {
        let f = NSTemporaryDirectory() + "ips-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: f) }
        let lines = (1...300).map { "linea \($0)" }.joined(separator: "\n")
        FileManager.default.createFile(atPath: f, contents: lines.data(using: .utf8))
        let out = CrashAnalyzer.excerpt(of: f, maxLines: 50)
        XCTAssertEqual(out.components(separatedBy: "\n").count, 50)
        XCTAssertTrue(out.contains("linea 1"))
        XCTAssertFalse(out.contains("linea 300"))
    }

    func testPromptConCincoSecciones() {
        let event = CrashEvent(file: "/tmp/x.ips", incidentID: "T-1", procName: "App",
                               procPath: "/Applications/App.app", signal: "SIGSEGV",
                               exceptionType: "EXC_BAD_ACCESS", bugType: "309",
                               terminationReason: nil, faultingTime: nil, kind: .crash)
        let prompt = CrashAnalyzer.crashPrompt(event: event, ipsExcerpt: "EXC", evidence: "EV")
        for seccion in ["Qué pasó", "Evidencia", "Causa probable",
                        "Arreglo (con rollbacks)", "Cómo evitarlo"] {
            XCTAssertTrue(prompt.contains("## \(seccion)"), "falta \(seccion)")
        }
        XCTAssertTrue(prompt.contains("no tienes herramientas") || prompt.contains("No tienes herramientas"))
    }
}

final class UsageTests: XCTestCase {
    func testDBInexistenteDevuelveNil() {
        XCTAssertNil(Usage.forDirectory("/tmp", dbPath: "/tmp/no-existe-\(UUID().uuidString).db"))
    }
}

enum TestEnv {
    /// Raíz del repo (Tests/../..) para probar instalaciones de skills reales.
    static var repoRoot: String {
        URL(fileURLWithPath: #filePath)          // …/Tests/ConBarAITests/ConBarAITests.swift
            .deletingLastPathComponent()         // Tests/ConBarAITests
            .deletingLastPathComponent()         // Tests
            .deletingLastPathComponent()         // repo
            .path
    }
}
