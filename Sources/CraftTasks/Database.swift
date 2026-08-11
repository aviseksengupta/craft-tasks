import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Local SQLite copy of all Craft tasks. Hash column drives change detection.
final class Database {
    private var db: OpaquePointer?
    let path: String

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CraftTasks", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        path = dir.appendingPathComponent("tasks.sqlite").path
        sqlite3_open(path, &db)
        exec("""
        CREATE TABLE IF NOT EXISTS tasks (
            id TEXT PRIMARY KEY,
            markdown TEXT NOT NULL,
            state TEXT NOT NULL,
            schedule_date TEXT,
            deadline_date TEXT,
            location_type TEXT NOT NULL,
            document_id TEXT,
            document_title TEXT,
            completed_at TEXT,
            hash TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE IF NOT EXISTS pending_updates (
            task_id TEXT PRIMARY KEY,
            payload TEXT NOT NULL,
            created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS pending_creates (
            local_id TEXT PRIMARY KEY,
            payload TEXT NOT NULL,
            created_at TEXT NOT NULL
        );
        """)
    }

    deinit { sqlite3_close(db) }

    private func exec(_ sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK, let err {
            NSLog("SQLite error: \(String(cString: err))")
            sqlite3_free(err)
        }
    }

    // MARK: meta
    func getMeta(_ key: String) -> String? {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key=?", -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_text(stmt, 0).map { String(cString: $0) } : nil
    }

    func setMeta(_ key: String, _ value: String) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "INSERT INTO meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, value, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    // MARK: tasks
    func allHashes() -> [String: String] {
        var out: [String: String] = [:]
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT id, hash FROM tasks", -1, &stmt, nil) == SQLITE_OK else { return out }
        while sqlite3_step(stmt) == SQLITE_ROW {
            out[String(cString: sqlite3_column_text(stmt, 0))] = String(cString: sqlite3_column_text(stmt, 1))
        }
        return out
    }

    func upsert(_ t: CraftTask) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = """
        INSERT INTO tasks (id,markdown,state,schedule_date,deadline_date,location_type,document_id,document_title,completed_at,hash)
        VALUES (?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET markdown=excluded.markdown, state=excluded.state,
            schedule_date=excluded.schedule_date, deadline_date=excluded.deadline_date,
            location_type=excluded.location_type, document_id=excluded.document_id,
            document_title=excluded.document_title, completed_at=excluded.completed_at, hash=excluded.hash
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        func bind(_ i: Int32, _ s: String?) {
            if let s { sqlite3_bind_text(stmt, i, s, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, i) }
        }
        bind(1, t.id); bind(2, t.markdown); bind(3, t.state.rawValue)
        bind(4, t.scheduleDate); bind(5, t.deadlineDate); bind(6, t.locationType)
        bind(7, t.documentId); bind(8, t.documentTitle); bind(9, t.completedAt); bind(10, t.hash)
        sqlite3_step(stmt)
    }

    func delete(ids: [String]) {
        for id in ids {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "DELETE FROM tasks WHERE id=?", -1, &stmt, nil) == SQLITE_OK else { continue }
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
    }

    // MARK: pending update queue (outbox for edits made while Craft is unreachable)
    func enqueuePending(taskId: String, payload: String) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "INSERT INTO pending_updates(task_id,payload,created_at) VALUES(?,?,?) ON CONFLICT(task_id) DO UPDATE SET payload=excluded.payload, created_at=excluded.created_at"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, taskId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, payload, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, ISO8601DateFormatter().string(from: Date()), -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    func pendingUpdates() -> [(taskId: String, payload: String)] {
        var out: [(String, String)] = []
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT task_id, payload FROM pending_updates ORDER BY created_at", -1, &stmt, nil) == SQLITE_OK else { return out }
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append((String(cString: sqlite3_column_text(stmt, 0)),
                        String(cString: sqlite3_column_text(stmt, 1))))
        }
        return out
    }

    func removePending(taskIds: [String]) {
        for id in taskIds {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "DELETE FROM pending_updates WHERE task_id=?", -1, &stmt, nil) == SQLITE_OK else { continue }
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
    }

    // MARK: pending create queue (outbox for new tasks made while Craft is unreachable)
    func enqueuePendingCreate(localId: String, payload: String) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "INSERT INTO pending_creates(local_id,payload,created_at) VALUES(?,?,?) ON CONFLICT(local_id) DO UPDATE SET payload=excluded.payload, created_at=excluded.created_at"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, localId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, payload, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, ISO8601DateFormatter().string(from: Date()), -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    func pendingCreates() -> [(localId: String, payload: String)] {
        var out: [(String, String)] = []
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT local_id, payload FROM pending_creates ORDER BY created_at", -1, &stmt, nil) == SQLITE_OK else { return out }
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append((String(cString: sqlite3_column_text(stmt, 0)),
                        String(cString: sqlite3_column_text(stmt, 1))))
        }
        return out
    }

    func removePendingCreate(localId: String) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "DELETE FROM pending_creates WHERE local_id=?", -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, localId, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    func loadAll() -> [CraftTask] {
        var out: [CraftTask] = []
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT id,markdown,state,schedule_date,deadline_date,location_type,document_id,document_title,completed_at,hash FROM tasks"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return out }
        func col(_ i: Int32) -> String? {
            sqlite3_column_text(stmt, i).map { String(cString: $0) }
        }
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(CraftTask(
                id: col(0) ?? "", markdown: col(1) ?? "",
                state: TaskState(rawValue: col(2) ?? "todo") ?? .todo,
                scheduleDate: col(3), deadlineDate: col(4),
                locationType: col(5) ?? "document",
                documentId: col(6), documentTitle: col(7),
                completedAt: col(8), hash: col(9) ?? ""))
        }
        return out
    }
}
