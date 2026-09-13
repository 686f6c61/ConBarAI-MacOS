import Foundation

/// La skill macos-operator se instala como copia canónica y se enlaza como
/// skill de proyecto solo en la carpeta de ejecución del panel, igual que la
/// versión Ubuntu enlazaba ubuntu-operator.
enum SkillInstaller {
    static var canonicalSkillDir: String { "\(Paths.skillsDir)/\(Paths.bundledSkill)" }

    /// Copia las skills del repo a ~/.local/share/conbarai/skills (la hace install.sh).
    /// `to` permite a los tests usar un destino temporal.
    @discardableResult
    static func install(from sourceDir: String, to destination: String? = nil) -> Bool {
        let dstRoot = destination ?? Paths.skillsDir
        let fm = FileManager.default
        var installed = 0
        for skill in Paths.bundledSkills {
            // Acepta tanto <repo> como <repo>/skills como origen.
            let candidates = [
                "\(sourceDir)/skills/\(skill)/SKILL.md",
                "\(sourceDir)/\(skill)/SKILL.md",
            ]
            guard let src = candidates.first(where: { fm.fileExists(atPath: $0) }) else { continue }
            let dst = "\(dstRoot)/\(skill)"
            try? fm.removeItem(atPath: dst)
            do {
                try fm.createDirectory(atPath: dst, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])
                try fm.copyItem(atPath: src, toPath: "\(dst)/SKILL.md")
                installed += 1
            } catch {
                // seguir con las demás
            }
        }
        return installed > 0
    }

    /// Enlaza la skill canónica en <workdir>/.opencode/skills/<skill> (symlink).
    @discardableResult
    static func linkInto(workdir: String) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: "\(canonicalSkillDir)/SKILL.md"),
              Sessions.slug(workdir) != "" else { return false }
        let projectSkills = "\(workdir)/.opencode/skills"
        let link = "\(projectSkills)/\(Paths.bundledSkill)"
        do {
            try fm.createDirectory(atPath: projectSkills, withIntermediateDirectories: true)
            if fm.fileExists(atPath: link) {
                // Si ya es nuestro symlink o nuestra copia, refrescar; si es otra
                // cosa del usuario, no tocarla.
                if try fm.destinationOfSymbolicLink(atPath: link) == canonicalSkillDir { return true }
                if !fm.isDeletableFile(atPath: link) { return false }
                var isDir: ObjCBool = false
                _ = fm.fileExists(atPath: link, isDirectory: &isDir)
                if !isDir.boolValue || fm.fileExists(atPath: "\(link)/SKILL.md") {
                    try fm.removeItem(atPath: link)
                } else {
                    return false
                }
            }
            try fm.createSymbolicLink(atPath: link, withDestinationPath: canonicalSkillDir)
            return true
        } catch {
            return false
        }
    }

    static func list() -> [String] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: Paths.skillsDir) else { return [] }
        return names.filter { fm.fileExists(atPath: "\(Paths.skillsDir)/\($0)/SKILL.md") }.sorted()
    }

    static func cli(_ args: [String]) {
        Paths.ensureStateDirs()
        let sub = args.count > 2 ? args[2] : "list"
        switch sub {
        case "install":
            let source = args.count > 3 ? args[3] : repoSkillSource()
            if install(from: source) {
                print("Skills instaladas en \(Paths.skillsDir): \(Paths.bundledSkills.joined(separator: ", "))")
            } else {
                print("No encontré skills en \(source ?? "(origen desconocido)")")
                exit(1)
            }
        case "link":
            guard args.count > 3 else { print("uso: conbarai skill link <carpeta>"); exit(64) }
            if linkInto(workdir: args[3]) {
                print("Skill enlazada en \(args[3])/.opencode/skills/\(Paths.bundledSkill)")
            } else {
                print("No pude enlazar la skill"); exit(1)
            }
        default:
            let skills = list()
            print(skills.isEmpty ? "(sin skills instaladas)" : skills.joined(separator: "\n"))
        }
    }

    /// En modo desarrollo, la skill vive junto al binario: <paquete>/skills/.
    private static func repoSkillSource() -> String {
        let bin = URL(fileURLWithPath: Paths.selfBinaryPath())
        // .build/release/conbarai → sube 3 niveles hasta la raíz del paquete.
        let root = bin.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return root.path
    }
}
