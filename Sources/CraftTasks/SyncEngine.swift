import Foundation

struct SyncResult {
    var added = 0
    var updated = 0
    var removed = 0
    var total = 0
    var unchanged: Bool { added == 0 && updated == 0 && removed == 0 }
}

enum SyncError: LocalizedError {
    /// message is Craft's own explanation when the API returns one (e.g.
    /// "Cannot modify document in trash. Restore it first.") — surfacing
    /// that instead of a bare status code is what distinguishes a genuine
    /// permanent rejection from a transient connectivity problem.
    case apiError(status: Int, message: String?)
    case network(Error)
    var errorDescription: String? {
        switch self {
        case .apiError(let status, let message): return message ?? "Craft API returned HTTP \(status)"
        case .network(let e): return e.localizedDescription
        }
    }
    /// True only for errors that are plausibly transient (no response at
    /// all, or a 5xx) — as opposed to a 4xx the server will keep rejecting
    /// no matter how many times it's retried (bad payload, trashed
    /// document, permissions). Callers use this to avoid telling the user
    /// "Offline" when the real problem is something retrying won't fix.
    var isLikelyTransient: Bool {
        switch self {
        case .network: return true
        case .apiError(let status, _): return status >= 500 || status == 0
        }
    }
}

/// Downloads every task from Craft (scope=all), hashes each raw task payload,
/// and propagates adds / updates / deletes into the local SQLite database.
final class SyncEngine {
    static let apiBase = "https://connect.craft.do/links/Cos6OQD9VsH/api/v1"

    /// Extracts Craft's own error message from a failed response body
    /// (`{"errors":[{"message": "..."}]}`) when present.
    private static func apiError(status: Int, data: Data?) -> SyncError {
        if let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errors = obj["errors"] as? [[String: Any]],
           let message = errors.first?["message"] as? String {
            return .apiError(status: status, message: message)
        }
        return .apiError(status: status, message: nil)
    }

    /// Pushes local edits to Craft via PUT /tasks. Throws if unreachable —
    /// callers keep the payloads queued and retry before the next sync.
    static func pushUpdates(_ payloads: [[String: Any]]) async throws {
        guard !payloads.isEmpty else { return }
        guard let url = URL(string: "\(apiBase)/tasks") else { throw SyncError.apiError(status: 0, message: nil) }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20
        req.httpBody = try JSONSerialization.data(withJSONObject: ["tasksToUpdate": payloads])
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await URLSession.shared.data(for: req) }
        catch { throw SyncError.network(error) }
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw apiError(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        }
    }

    /// Creates one task via POST /tasks and returns it parsed the same way
    /// a synced task would be, hash included, ready for db.upsert.
    static func createTask(markdown: String, location: [String: Any],
                           scheduleDate: String?, deadlineDate: String?) async throws -> CraftTask {
        guard let url = URL(string: "\(apiBase)/tasks") else { throw SyncError.apiError(status: 0, message: nil) }
        var taskInfo: [String: Any] = [:]
        if let scheduleDate { taskInfo["scheduleDate"] = scheduleDate }
        if let deadlineDate { taskInfo["deadlineDate"] = deadlineDate }
        var task: [String: Any] = ["markdown": markdown, "location": location]
        if !taskInfo.isEmpty { task["taskInfo"] = taskInfo }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20
        req.httpBody = try JSONSerialization.data(withJSONObject: ["tasks": [task]])
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await URLSession.shared.data(for: req) }
        catch { throw SyncError.network(error) }
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw apiError(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]], let raw = items.first,
              let id = raw["id"] as? String else {
            throw SyncError.apiError(status: 200, message: "Craft returned an unexpected response")
        }
        let ti = raw["taskInfo"] as? [String: Any] ?? [:]
        let loc = raw["location"] as? [String: Any] ?? [:]
        return CraftTask(
            id: id,
            markdown: raw["markdown"] as? String ?? markdown,
            state: TaskState(rawValue: ti["state"] as? String ?? "todo") ?? .todo,
            scheduleDate: ti["scheduleDate"] as? String,
            deadlineDate: ti["deadlineDate"] as? String,
            locationType: loc["type"] as? String ?? "inbox",
            documentId: loc["documentId"] as? String,
            documentTitle: loc["title"] as? String,
            completedAt: nil,
            hash: CraftTask.computeHash(json: raw))
    }

    /// A task block's own content — the child text blocks Craft shows when
    /// you open a task, which is where its "description" actually lives
    /// (tasks are page blocks; children are ordinary content blocks).
    struct TaskDescription {
        var blockIds: [String]
        var text: String
    }

    /// Fetched lazily (only when a task is opened for editing), not during
    /// full sync — GET /blocks has no batch form, so pulling this for every
    /// task on every sync would multiply request count by ~200x.
    static func fetchDescription(taskId: String) async throws -> TaskDescription {
        guard let url = URL(string: "\(apiBase)/blocks?id=\(taskId)&maxDepth=1") else { throw SyncError.apiError(status: 0, message: nil) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await URLSession.shared.data(for: req) }
        catch { throw SyncError.network(error) }
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw apiError(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = root["content"] as? [[String: Any]] else {
            return TaskDescription(blockIds: [], text: "")
        }
        let ids = content.compactMap { $0["id"] as? String }
        let text = content.compactMap { $0["markdown"] as? String }.joined(separator: "\n")
        return TaskDescription(blockIds: ids, text: text)
    }

    /// Writes an edited description back as a single child text block,
    /// replacing whatever child blocks were there before (this normalizes
    /// multi-block descriptions down to one block on save).
    static func pushDescription(taskId: String, existingBlockIds: [String], newText: String) async throws {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !existingBlockIds.isEmpty {
            guard let url = URL(string: "\(apiBase)/blocks") else { throw SyncError.apiError(status: 0, message: nil) }
            var req = URLRequest(url: url)
            req.httpMethod = "DELETE"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.timeoutInterval = 15
            req.httpBody = try JSONSerialization.data(withJSONObject: ["blockIds": existingBlockIds])
            let (data, resp): (Data, URLResponse)
            do { (data, resp) = try await URLSession.shared.data(for: req) }
            catch { throw SyncError.network(error) }
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw apiError(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, data: data)
            }
        }

        guard !trimmed.isEmpty else { return }
        guard let url = URL(string: "\(apiBase)/blocks") else { throw SyncError.apiError(status: 0, message: nil) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "blocks": [["type": "text", "markdown": trimmed]],
            "position": ["position": "start", "pageId": taskId],
        ])
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await URLSession.shared.data(for: req) }
        catch { throw SyncError.network(error) }
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw apiError(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        }
    }

    /// GET /connection returns the space id needed to build craftdocs://
    /// deep links (Craft doesn't expose it via /tasks) plus a ready-made
    /// URL template — fetched once and cached in UserDefaults.
    static func fetchSpaceId() async throws -> String {
        guard let url = URL(string: "\(apiBase)/connection") else { throw SyncError.apiError(status: 0, message: nil) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await URLSession.shared.data(for: req) }
        catch { throw SyncError.network(error) }
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw apiError(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let space = root["space"] as? [String: Any], let id = space["id"] as? String else {
            throw SyncError.apiError(status: 200, message: "Craft returned an unexpected response")
        }
        return id
    }

    static func fetchAndDiff(db: Database, skipping pendingIds: Set<String> = []) async throws -> SyncResult {
        guard let url = URL(string: "\(apiBase)/tasks?scope=all") else { throw SyncError.apiError(status: 0, message: nil) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await URLSession.shared.data(for: req) }
        catch { throw SyncError.network(error) }
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw apiError(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]] else {
            throw SyncError.apiError(status: 200, message: "Craft returned an unexpected response")
        }

        let localHashes = db.allHashes()
        var result = SyncResult()
        var seen = Set<String>()

        for raw in items {
            guard let id = raw["id"] as? String else { continue }
            seen.insert(id)
            // Don't overwrite tasks with un-pushed local edits.
            if pendingIds.contains(id) { continue }
            let hash = CraftTask.computeHash(json: raw)
            if localHashes[id] == hash { continue }

            let ti = raw["taskInfo"] as? [String: Any] ?? [:]
            let loc = raw["location"] as? [String: Any] ?? [:]
            let task = CraftTask(
                id: id,
                markdown: raw["markdown"] as? String ?? "",
                state: TaskState(rawValue: ti["state"] as? String ?? "todo") ?? .todo,
                scheduleDate: ti["scheduleDate"] as? String,
                deadlineDate: ti["deadlineDate"] as? String,
                locationType: loc["type"] as? String ?? "document",
                documentId: loc["documentId"] as? String,
                documentTitle: loc["title"] as? String,
                completedAt: raw["completedAt"] as? String,
                hash: hash)
            db.upsert(task)
            if localHashes[id] == nil { result.added += 1 } else { result.updated += 1 }
        }

        let gone = localHashes.keys.filter { !seen.contains($0) && !pendingIds.contains($0) }
        if !gone.isEmpty {
            db.delete(ids: gone)
            result.removed = gone.count
        }
        result.total = items.count
        db.setMeta("lastSync", ISO8601DateFormatter().string(from: Date()))
        return result
    }
}
