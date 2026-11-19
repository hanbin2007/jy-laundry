import Foundation

enum Config {
    static let defaultBaseURL = "http://laundry.example.com/laundry"
    static let defaultToken = "REDACTED_TOKEN"
}

enum APIError: LocalizedError {
    case badURL
    case unauthorized
    case message(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "服务器地址无效"
        case .unauthorized: return "访问令牌无效"
        case .message(let text): return text
        }
    }
}

struct HistoryAPI {
    let baseURL: URL
    let token: String

    /// `live` asks the server to read the vendor right now (rate-limited server side);
    /// otherwise it answers from the once-a-minute poll.
    func fetch(hours: Int = 24, live: Bool = true) async throws -> Snapshot {
        guard var comps = URLComponents(url: baseURL.appendingPathComponent("api/v1/overview"),
                                        resolvingAgainstBaseURL: false) else {
            throw APIError.badURL
        }
        comps.queryItems = [
            URLQueryItem(name: "hours", value: String(hours)),
            URLQueryItem(name: "live", value: live ? "1" : "0")
        ]
        guard let url = comps.url else { throw APIError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(token, forHTTPHeaderField: "X-Token")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.badURL }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard http.statusCode == 200 else {
            throw APIError.message("服务器错误 \(http.statusCode)")
        }

        return try JSONDecoder().decode(Snapshot.self, from: data)
    }
}
