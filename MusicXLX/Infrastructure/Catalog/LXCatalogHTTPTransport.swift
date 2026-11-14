import Foundation

/// Native transport used by the LX 1.9.2 catalog bridge.
///
/// This intentionally mirrors the useful part of LX's `httpFetch` contract:
/// response body is preserved as bytes/text, status and headers are retained,
/// JSON decoding is optional, and every request can be cancelled.
final class LXCatalogHTTPTransport {
    struct Response {
        let url: URL
        let statusCode: Int
        let statusMessage: String
        let headers: [String: String]
        let body: Data

        var text: String {
            String(data: body, encoding: .utf8) ?? ""
        }

        var jsonObject: Any? {
            try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed])
        }

        var isSuccessful: Bool {
            (200..<300).contains(statusCode)
        }
    }

    struct Request {
        var method: String = "GET"
        var headers: [String: String] = [:]
        var body: Data?
        var form: [String: String]?
        var timeout: TimeInterval = 15
        var cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData
    }

    enum TransportError: LocalizedError {
        case invalidURL
        case nonHTTPResponse
        case httpStatus(Int, String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "洛雪目录请求 URL 无效。"
            case .nonHTTPResponse:
                return "洛雪目录请求没有返回 HTTP 响应。"
            case .httpStatus(let code, let message):
                return "洛雪目录请求失败（HTTP \(code)）：\(message)"
            }
        }
    }

    private final class TaskBox {
        private let lock = NSLock()
        private var task: URLSessionDataTask?

        func install(_ task: URLSessionDataTask) {
            lock.lock()
            self.task = task
            lock.unlock()
        }

        func cancel() {
            lock.lock()
            let task = self.task
            lock.unlock()
            task?.cancel()
        }
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(_ url: URL, options: Request = Request()) async throws -> Response {
        var request = URLRequest(
            url: url,
            cachePolicy: options.cachePolicy,
            timeoutInterval: max(1, options.timeout)
        )
        request.httpMethod = options.method.uppercased()

        var headers = options.headers
        if let form = options.form {
            let pairs = form.keys.sorted().map { key in
                "\(Self.formEncode(key))=\(Self.formEncode(form[key] ?? ""))"
            }
            request.httpBody = pairs.joined(separator: "&").data(using: .utf8)
            if headers["Content-Type"] == nil {
                headers["Content-Type"] = "application/x-www-form-urlencoded"
            }
        } else {
            request.httpBody = options.body
        }

        if headers["Accept"] == nil {
            headers["Accept"] = "application/json"
        }
        if headers["User-Agent"] == nil {
            headers["User-Agent"] = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15"
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let taskBox = TaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request) { data, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let http = response as? HTTPURLResponse else {
                        continuation.resume(throwing: TransportError.nonHTTPResponse)
                        return
                    }
                    let responseHeaders = http.allHeaderFields.reduce(into: [String: String]()) { result, item in
                        result[String(describing: item.key)] = String(describing: item.value)
                    }
                    let result = Response(
                        url: http.url ?? url,
                        statusCode: http.statusCode,
                        statusMessage: HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
                        headers: responseHeaders,
                        body: data ?? Data()
                    )
                    continuation.resume(returning: result)
                }
                taskBox.install(task)
                task.resume()
            }
        } onCancel: {
            taskBox.cancel()
        }
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
