import XCTest
@testable import conbarai

/// Lógica de dependencias: qué falta, por qué canal se instala y qué guía
/// se muestra cuando ni siquiera hay canal. Nada de instalar nada aquí.
final class DepsTests: XCTestCase {
    func testMissingOrderAndAllPresent() {
        var s = Deps.Status(pi: true, tmux: true, brew: true, npm: true)
        XCTAssertTrue(s.allPresent)
        XCTAssertTrue(s.missing.isEmpty)

        s.pi = false
        s.tmux = false
        XCTAssertEqual(s.missing, ["tmux", "pi"]) // tmux primero: sin él no hay sesión
        XCTAssertFalse(s.allPresent)

        s.tmux = true
        XCTAssertEqual(s.missing, ["pi"])
    }

    func testInstallCommandsUseOfficialChannels() {
        let tmux = Deps.installCommand(dep: "tmux", brewPath: "/opt/homebrew/bin/brew", npmPath: nil)
        XCTAssertEqual(tmux, "'/opt/homebrew/bin/brew' install tmux")

        let pi = Deps.installCommand(dep: "pi", brewPath: nil, npmPath: "/opt/homebrew/bin/npm")
        XCTAssertEqual(pi, "'/opt/homebrew/bin/npm' install -g @mariozechner/pi-coding-agent")

        // Sin canal no hay comando: toca la guía manual.
        XCTAssertNil(Deps.installCommand(dep: "tmux", brewPath: nil, npmPath: nil))
        XCTAssertNil(Deps.installCommand(dep: "pi", brewPath: nil, npmPath: nil))
        XCTAssertNil(Deps.installCommand(dep: "otra-cosa", brewPath: "/b", npmPath: "/n"))
    }

    func testCommandsNeverFetchRemoteScripts() {
        // Regla de la casa: nada de curl/wget de instaladores; solo el
        // gestor de paquetes local (brew/npm) del propio usuario.
        for (dep, brew, npm) in [("tmux", "/opt/homebrew/bin/brew", nil),
                                 ("pi", nil, "/usr/local/bin/npm")] {
            let cmd = Deps.installCommand(dep: dep, brewPath: brew, npmPath: npm) ?? ""
            XCTAssertFalse(cmd.contains("curl"), cmd)
            XCTAssertFalse(cmd.contains("wget"), cmd)
            XCTAssertFalse(cmd.contains("http"), cmd)
        }
    }

    func testGuidancePointsToOfficialWebsites() {
        let sinNada = Deps.Status(pi: false, tmux: false, brew: false, npm: false)
        XCTAssertTrue(Deps.guidanceText(for: "tmux", status: sinNada).contains(Deps.brewURL))
        XCTAssertTrue(Deps.guidanceText(for: "pi", status: sinNada).contains(Deps.nodeURL))

        let conCanal = Deps.Status(pi: false, tmux: false, brew: true, npm: true)
        XCTAssertEqual(Deps.guidanceText(for: "tmux", status: conCanal), "se instalará con Homebrew")
        XCTAssertEqual(Deps.guidanceText(for: "pi", status: conCanal), "se instalará con npm")
    }

    func testPackageIsTheOfficialPiCLI() {
        XCTAssertEqual(Deps.piPackage, "@mariozechner/pi-coding-agent")
    }
}
