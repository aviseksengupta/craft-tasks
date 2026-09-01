import Foundation

/// Tiny append-only activity log for sync/push events, persisted to
/// `CraftTasks/sync.log` in Application Support. Deliberately small: it keeps
/// only the last `maxLines` lines (trimmed on every write) so it never grows
/// without bound and stays readable at a glance. The point is to answer
/// "why aren't my changes syncing, and which task is to blame?" — so the
/// things worth logging are queued edits/creates, push results, and
/// rejections (with the offending task's title and id), not routine polls.
final class AppLog {
    static let shared = AppLog()

    private let maxLines = 120
    private let queue = DispatchQueue(label: "com.crafttasks.applog")
    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CraftTasks", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sync.log")
    }()

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()

    /// Append one line, timestamped. Safe to call from any thread/actor.
    func log(_ message: String) {
        let line = "\(Self.stamp.string(from: Date()))  \(message)"
        queue.async {
            var lines = (try? String(contentsOf: self.url, encoding: .utf8))?
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init) ?? []
            if lines.last == "" { lines.removeLast() }
            lines.append(line)
            if lines.count > self.maxLines { lines.removeFirst(lines.count - self.maxLines) }
            try? (lines.joined(separator: "\n") + "\n").write(to: self.url, atomically: true, encoding: .utf8)
        }
    }

    /// The most recent `count` lines, oldest first. Synchronous — reads
    /// through the same queue so it never races a pending write.
    func recent(_ count: Int) -> [String] {
        queue.sync {
            let lines = (try? String(contentsOf: url, encoding: .utf8))?
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map(String.init) ?? []
            return Array(lines.suffix(count))
        }
    }

    func clear() {
        queue.async { try? FileManager.default.removeItem(at: self.url) }
    }
}
