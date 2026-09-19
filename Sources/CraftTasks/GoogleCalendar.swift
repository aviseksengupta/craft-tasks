import Foundation
import AuthenticationServices
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Security
import CryptoKit

// Google Calendar integration for the macOS app — mirrors the web app's
// web/src/gcal.ts. Craft stays the source of truth for tasks (no time, no
// reminders). A dedicated "Craft Tasks" Google Calendar is a separate store
// for time-based reminders; "Send to Calendar" is a one-way, one-shot push.
//
// Auth: OAuth for native apps — an "iOS" type OAuth client (works on macOS),
// PKCE, no client secret, custom-scheme redirect (the reversed client id).
// The refresh token lives in the Keychain; the access token is kept in memory
// and refreshed on demand. Scope `calendar.app.created` means this app can
// only ever see and touch calendars it created itself.

enum GoogleCalError: LocalizedError {
    case notConfigured
    case cancelled
    case api(Int, String)
    case noCalendar
    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Google OAuth Client ID not set — add it in Settings."
        case .cancelled: return "Authorization was cancelled."
        case .api(let code, let msg): return "Google Calendar API \(code): \(msg)"
        case .noCalendar: return "Couldn't resolve the Craft Tasks calendar."
        }
    }
}

enum RepeatKind: String, CaseIterable, Identifiable {
    case none, daily, weekly, weekday, monthly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "Does not repeat"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .weekday: return "Every weekday (Mon–Fri)"
        case .monthly: return "Monthly"
        }
    }
}

struct GCalEvent: Identifiable, Equatable {
    let id: String
    var summary: String
    var start: Date
    var isAllDay: Bool
    var recurringEventId: String?
    var hasRecurrence: Bool
    var htmlLink: String?
}

struct AgendaEvent: Identifiable {
    let event: GCalEvent
    let calendarId: String
    let calendarName: String
    let color: String?
    let editable: Bool
    var id: String { calendarId + "/" + event.id }
}

@MainActor
final class GoogleCalendar: ObservableObject {
    static let shared = GoogleCalendar()

    @Published private(set) var isConnected: Bool
    @Published var lastError: String?

    private let scope = "https://www.googleapis.com/auth/calendar"
    private let authEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    private let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    private let apiBase = "https://www.googleapis.com/calendar/v3"
    private let calendarSummary = "Craft Tasks"
    private let keychainService = "com.avisek.crafttasks.google"

    private var accessToken: String?
    private var accessTokenExpiry: Date = .distantPast
    private var authSession: ASWebAuthenticationSession?
    private let presenter = AuthPresenter()

    private init() {
        isConnected = Keychain.get(service: keychainService, account: "refreshToken") != nil
            && !Self.clientID.isEmpty
    }

    // MARK: client id (UserDefaults, like the web app's localStorage)

    static var clientID: String {
        get { UserDefaults.standard.string(forKey: "googleClientId")?.trimmingCharacters(in: .whitespaces) ?? "" }
        set {
            let v = newValue.trimmingCharacters(in: .whitespaces)
            if v.isEmpty { UserDefaults.standard.removeObject(forKey: "googleClientId") }
            else { UserDefaults.standard.set(v, forKey: "googleClientId") }
        }
    }

    func setClientID(_ id: String) {
        let trimmed = id.trimmingCharacters(in: .whitespaces)
        guard trimmed != Self.clientID else { return }
        Self.clientID = trimmed
        disconnect()
    }

    /// The custom URL scheme Google expects for an iOS/native client is the
    /// client id with its dot-separated components reversed.
    private var redirectScheme: String {
        String(Self.clientID.split(separator: ".").reversed().joined(separator: "."))
    }
    private var redirectURI: String { "\(redirectScheme):/oauth2redirect" }

    // MARK: connect / disconnect

    func connect() async throws {
        guard !Self.clientID.isEmpty else { throw GoogleCalError.notConfigured }

        let verifier = Self.randomURLSafe(64)
        let challenge = Self.s256(verifier)
        var comps = URLComponents(url: authEndpoint, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "client_id", value: Self.clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scope),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]

        let callbackURL: URL = try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(
                url: comps.url!, callbackURLScheme: redirectScheme
            ) { url, error in
                if let url { cont.resume(returning: url) }
                else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    cont.resume(throwing: GoogleCalError.cancelled)
                } else {
                    cont.resume(throwing: error ?? GoogleCalError.cancelled)
                }
            }
            session.presentationContextProvider = presenter
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            if !session.start() { cont.resume(throwing: GoogleCalError.cancelled) }
        }

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw GoogleCalError.cancelled
        }

        try await exchangeCode(code, verifier: verifier)
        isConnected = true
    }

    func disconnect() {
        accessToken = nil
        accessTokenExpiry = .distantPast
        Keychain.delete(service: keychainService, account: "refreshToken")
        isConnected = false
    }

    private func exchangeCode(_ code: String, verifier: String) async throws {
        let body = Self.form([
            "client_id": Self.clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ])
        let (data, resp) = try await URLSession.shared.data(for: Self.post(tokenEndpoint, body: body))
        try Self.check(resp, data)
        let t = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = t.access_token
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(t.expires_in ?? 3600) - 60)
        if let refresh = t.refresh_token {
            Keychain.set(refresh, service: keychainService, account: "refreshToken")
        }
    }

    private func validToken() async throws -> String {
        if let accessToken, accessTokenExpiry > Date() { return accessToken }
        guard !Self.clientID.isEmpty else { throw GoogleCalError.notConfigured }
        guard let refresh = Keychain.get(service: keychainService, account: "refreshToken") else {
            isConnected = false
            throw GoogleCalError.cancelled
        }
        let body = Self.form([
            "client_id": Self.clientID,
            "refresh_token": refresh,
            "grant_type": "refresh_token",
        ])
        let (data, resp) = try await URLSession.shared.data(for: Self.post(tokenEndpoint, body: body))
        do { try Self.check(resp, data) }
        catch {
            // refresh token revoked / expired
            disconnect()
            throw error
        }
        let t = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = t.access_token
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(t.expires_in ?? 3600) - 60)
        return t.access_token ?? ""
    }

    // MARK: calendar resolution

    /// Resolve the dedicated calendar id, creating it only if none exists.
    /// Always scans by name first so a calendar made on another device (or by
    /// the web app) is adopted rather than duplicated; after a create, re-scans
    /// and collapses any race duplicates to the first id.
    func ensureCalendar(known: String?) async throws -> String {
        if let known, !known.isEmpty {
            if (try? await request("GET", "/calendars/\(enc(known))")) != nil { return known }
        }
        let found = try await findCalendars()
        if let first = found.first { return first }

        _ = try await request("POST", "/calendars", json: ["summary": calendarSummary])
        let after = try await findCalendars()
        guard let winner = after.first else { throw GoogleCalError.noCalendar }
        for extra in after.dropFirst() where (try? await calendarIsEmpty(extra)) == true {
            _ = try? await request("DELETE", "/calendars/\(enc(extra))")
        }
        return winner
    }

    private func findCalendars() async throws -> [String] {
        let data = try await request("GET", "/users/me/calendarList?showHidden=true&maxResults=250")
        let list = try JSONDecoder().decode(CalendarListResponse.self, from: data)
        return list.items
            .filter { $0.summary?.trimmingCharacters(in: .whitespaces) == calendarSummary }
            .map(\.id)
            .sorted()
    }

    private func calendarIsEmpty(_ calId: String) async throws -> Bool {
        let data = try await request("GET", "/calendars/\(enc(calId))/events?maxResults=1")
        let r = try JSONDecoder().decode(EventsResponse.self, from: data)
        return r.items.isEmpty
    }

    // MARK: events

    struct EventInput {
        var title: String
        var start: Date
        var durationMinutes: Int = 30
        var repeatKind: RepeatKind = .none
        var repeatUntil: Date?
        var craftTaskId: String?
        var description: String?
    }

    func listEvents(calId: String, from: Date, to: Date) async throws -> [GCalEvent] {
        var comps = URLComponents(string: "\(apiBase)/calendars/\(enc(calId))/events")!
        comps.queryItems = [
            .init(name: "singleEvents", value: "true"),
            .init(name: "orderBy", value: "startTime"),
            .init(name: "timeMin", value: Self.rfc3339(from)),
            .init(name: "timeMax", value: Self.rfc3339(to)),
            .init(name: "maxResults", value: "250"),
        ]
        let data = try await requestRaw("GET", comps.url!)
        let r = try JSONDecoder().decode(EventsResponse.self, from: data)
        return r.items.compactMap { $0.toModel() }.filter { $0.summary != "__cancelled__" }
    }

    /// Every event across the user's visible calendars for [from, to). Events
    /// on the dedicated Craft Tasks calendar are `editable`; all others are
    /// read-only context. Respects each calendar's "shown" checkbox.
    func listAgenda(craftCalId: String, from: Date, to: Date) async throws -> [AgendaEvent] {
        let data = try await request("GET", "/users/me/calendarList?maxResults=250")
        let list = try JSONDecoder().decode(CalendarListFull.self, from: data)
        let cals = list.items.filter { $0.selected != false && $0.accessRole != "freeBusyReader" }
        var out: [AgendaEvent] = []
        try await withThrowingTaskGroup(of: [AgendaEvent].self) { group in
            for c in cals {
                group.addTask {
                    let evs = (try? await self.listEvents(calId: c.id, from: from, to: to)) ?? []
                    let name = c.summaryOverride ?? c.summary ?? c.id
                    return evs.map { AgendaEvent(event: $0, calendarId: c.id, calendarName: name,
                                                 color: c.backgroundColor, editable: c.id == craftCalId) }
                }
            }
            for try await chunk in group { out.append(contentsOf: chunk) }
        }
        return out
    }

    @discardableResult
    func createEvent(calId: String, _ input: EventInput) async throws -> GCalEvent {
        let data = try await request("POST", "/calendars/\(enc(calId))/events", json: eventBody(input))
        guard let ev = (try JSONDecoder().decode(EventResource.self, from: data)).toModel() else {
            throw GoogleCalError.api(0, "bad response")
        }
        return ev
    }

    @discardableResult
    func updateEvent(calId: String, eventId: String, _ input: EventInput) async throws -> GCalEvent {
        let data = try await request("PATCH", "/calendars/\(enc(calId))/events/\(enc(eventId))", json: eventBody(input))
        guard let ev = (try JSONDecoder().decode(EventResource.self, from: data)).toModel() else {
            throw GoogleCalError.api(0, "bad response")
        }
        return ev
    }

    func deleteEvent(calId: String, eventId: String) async throws {
        _ = try await request("DELETE", "/calendars/\(enc(calId))/events/\(enc(eventId))")
    }

    // MARK: RRULE

    static func buildRecurrence(_ kind: RepeatKind, date: Date, until: Date?) -> [String]? {
        guard kind != .none else { return nil }
        let cal = Calendar.current
        let byday = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
        var rule: String
        switch kind {
        case .none: return nil
        case .daily: rule = "FREQ=DAILY"
        case .weekly: rule = "FREQ=WEEKLY;BYDAY=\(byday[cal.component(.weekday, from: date) - 1])"
        case .weekday: rule = "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"
        case .monthly: rule = "FREQ=MONTHLY;BYMONTHDAY=\(cal.component(.day, from: date))"
        }
        if let until {
            let end = cal.date(bySettingHour: 23, minute: 59, second: 59, of: until) ?? until
            let f = DateFormatter()
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            rule += ";UNTIL=\(f.string(from: end))"
        }
        return ["RRULE:\(rule)"]
    }

    static func parseRecurrence(_ recurrence: [String]?) -> (kind: RepeatKind, until: Date?) {
        guard let rrule = recurrence?.first(where: { $0.hasPrefix("RRULE:") }) else { return (.none, nil) }
        let parts = Dictionary(uniqueKeysWithValues: rrule.dropFirst(6).split(separator: ";").compactMap { seg -> (String, String)? in
            let kv = seg.split(separator: "=", maxSplits: 1)
            return kv.count == 2 ? (String(kv[0]), String(kv[1])) : nil
        })
        var until: Date?
        if let u = parts["UNTIL"] {
            let f = DateFormatter(); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            until = f.date(from: u) ?? { let g = DateFormatter(); g.dateFormat = "yyyyMMdd"; return g.date(from: String(u.prefix(8))) }()
        }
        let kind: RepeatKind
        switch parts["FREQ"] {
        case "DAILY": kind = .daily
        case "MONTHLY": kind = .monthly
        case "WEEKLY": kind = parts["BYDAY"] == "MO,TU,WE,TH,FR" ? .weekday : .weekly
        default: kind = .none
        }
        return (kind, until)
    }

    // MARK: request plumbing

    private func eventBody(_ input: EventInput) -> [String: Any] {
        let end = input.start.addingTimeInterval(TimeInterval(input.durationMinutes * 60))
        let tz = TimeZone.current.identifier
        var body: [String: Any] = [
            "summary": input.title,
            "start": ["dateTime": Self.localISO(input.start), "timeZone": tz],
            "end": ["dateTime": Self.localISO(end), "timeZone": tz],
        ]
        if let rec = Self.buildRecurrence(input.repeatKind, date: input.start, until: input.repeatUntil) {
            body["recurrence"] = rec
        }
        if let d = input.description { body["description"] = d }
        if let tid = input.craftTaskId { body["extendedProperties"] = ["private": ["craftTaskId": tid]] }
        return body
    }

    @discardableResult
    private func request(_ method: String, _ path: String, json: [String: Any]? = nil) async throws -> Data {
        try await requestRaw(method, URL(string: apiBase + path)!, json: json)
    }

    @discardableResult
    private func requestRaw(_ method: String, _ url: URL, json: [String: Any]? = nil) async throws -> Data {
        func send() async throws -> (Data, URLResponse) {
            let token = try await validToken()
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let json {
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try JSONSerialization.data(withJSONObject: json)
            }
            return try await URLSession.shared.data(for: req)
        }
        var (data, resp) = try await send()
        if (resp as? HTTPURLResponse)?.statusCode == 401 {
            accessToken = nil; accessTokenExpiry = .distantPast
            (data, resp) = try await send()
        }
        try Self.check(resp, data)
        return data
    }

    private func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
    }

    // MARK: helpers

    private static func post(_ url: URL, body: Data) -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = body
        return r
    }

    private static func form(_ dict: [String: String]) -> Data {
        dict.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&").data(using: .utf8)!
    }

    private static func check(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            var msg = String(data: data, encoding: .utf8) ?? ""
            if let obj = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
                msg = obj.error.message ?? obj.error_description ?? msg
            }
            throw GoogleCalError.api(http.statusCode, String(msg.prefix(200)))
        }
    }

    private static func randomURLSafe(_ n: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func s256(_ verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func localISO(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.string(from: d)
    }

    private static func rfc3339(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        return f.string(from: d)
    }
}

// MARK: - ASWebAuthenticationSession presentation anchor

private final class AuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        return NSApplication.shared.windows.first { $0.isKeyWindow } ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #else
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
            ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        return scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first ?? ASPresentationAnchor()
        #endif
    }
}

// MARK: - JSON models

private struct TokenResponse: Decodable {
    let access_token: String?
    let expires_in: Int?
    let refresh_token: String?
}

private struct APIErrorEnvelope: Decodable {
    struct Inner: Decodable { let message: String? }
    let error: Inner
    let error_description: String?
}

private struct CalendarListResponse: Decodable {
    struct Entry: Decodable { let id: String; let summary: String? }
    let items: [Entry]
}

private struct CalendarListFull: Decodable {
    struct Entry: Decodable {
        let id: String
        let summary: String?
        let summaryOverride: String?
        let backgroundColor: String?
        let selected: Bool?
        let accessRole: String?
    }
    let items: [Entry]
}

private struct EventsResponse: Decodable {
    let items: [EventResource]
}

private struct EventResource: Decodable {
    struct When: Decodable { let dateTime: String?; let date: String? }
    let id: String
    let summary: String?
    let start: When?
    let end: When?
    let recurrence: [String]?
    let recurringEventId: String?
    let status: String?
    let htmlLink: String?

    func toModel() -> GCalEvent? {
        guard let start else { return nil }
        if status == "cancelled" {
            return GCalEvent(id: id, summary: "__cancelled__", start: .distantPast, isAllDay: false,
                             recurringEventId: recurringEventId, hasRecurrence: false, htmlLink: nil)
        }
        let allDay = start.dateTime == nil && start.date != nil
        let date: Date
        if let dt = start.dateTime {
            date = ISO8601DateFormatter.flexible.date(from: dt) ?? Date()
        } else if let d = start.date {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; date = f.date(from: d) ?? Date()
        } else { return nil }
        return GCalEvent(
            id: id, summary: summary ?? "(no title)", start: date, isAllDay: allDay,
            recurringEventId: recurringEventId,
            hasRecurrence: (recurrence?.isEmpty == false) || recurringEventId != nil,
            htmlLink: htmlLink
        )
    }
}

private extension ISO8601DateFormatter {
    static let flexible: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

// MARK: - Keychain

enum Keychain {
    static func set(_ value: String, service: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(service: String, account: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }
}
