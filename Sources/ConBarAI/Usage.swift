import Foundation
import SQLite3

/// SQLITE_TRANSIENT es una macro de C que el módulo SQLite3 no expone a Swift.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Uso de tokens y coste por carpeta, leído de la base de OpenCode en modo solo-lectura.
/// Equivalente de usage() de oc_common.py.
enum Usage {
    struct Totals {
        var cost = 0.0
        var tokensIn = 0
        var tokensOut = 0

        var tokensTotal: Int { tokensIn + tokensOut }

        var shortTokens: String {
            Double(tokensTotal) >= 1_000_000
                ? String(format: "%.1fM", Double(tokensTotal) / 1_000_000)
                : (Double(tokensTotal) >= 1_000 ? String(format: "%.0fk", Double(tokensTotal) / 1_000)
                                                : "\(tokensTotal)")
        }

        var shortCost: String { cost >= 1 ? String(format: "$%.2f", cost) : String(format: "¢%.0f", cost * 100) }
    }

    static func forDirectory(_ directory: String, dbPath: String = Paths.opencodeDB) -> Totals? {
        guard FileManager.default.fileExists(atPath: dbPath) else { return nil }
        var db: OpaquePointer?
        // URI mode=ro: nunca escribimos en la base del usuario (ni WAL checkpoints).
        guard sqlite3_open_v2("file:\(dbPath)?mode=ro&immutable=0", &db,
                              SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 1500)

        // El esquema cambia entre versiones de OpenCode: detectar columnas disponibles.
        var columns = Set<String>()
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(session)", -1, &stmt, nil) == SQLITE_OK else { return nil }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 1) { columns.insert(String(cString: c)) }
        }
        sqlite3_finalize(stmt)
        guard columns.contains("directory") else { return nil }

        var sums: [String] = []
        if columns.contains("cost") { sums.append("SUM(COALESCE(cost,0))") }
        for col in ["tokens_input", "tokens_output", "tokens_reasoning", "tokens_cache_write", "tokens_cache_read"] {
            if columns.contains(col) { sums.append("SUM(COALESCE(\(col),0))") }
        }
        guard !sums.isEmpty else { return nil }

        // time_archived guarda un epoch (no NULL), así que no filtra: se suma todo,
        // igual que usage() de la versión Ubuntu.
        let sql = "SELECT \(sums.joined(separator: ",")) FROM session WHERE directory = ?"

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, directory, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        var totals = Totals()
        totals.cost = sqlite3_column_double(stmt, 0)
        var tokens = 0
        for i in 1..<sqlite3_column_count(stmt) {
            tokens += Int(sqlite3_column_int64(stmt, i))
        }
        totals.tokensIn = tokens
        return totals
    }
}
