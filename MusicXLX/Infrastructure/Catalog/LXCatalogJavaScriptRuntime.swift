import Foundation
import JavaScriptCore

/// JavaScriptCore host for the extracted LX catalog modules.
/// All JSContext access is confined to one serial queue. Network work runs
/// asynchronously and returns to that queue before invoking JavaScript.
final class LXCatalogJavaScriptRuntime {
    enum RuntimeError: LocalizedError {
        case invalidRequest
        case invalidOptions
        case script(String)

        var errorDescription: String? {
            switch self {
            case .invalidRequest: return "洛雪目录运行时收到无效请求。"
            case .invalidOptions: return "洛雪目录请求参数格式错误。"
            case .script(let message): return "洛雪目录脚本执行失败：\(message)"
            }
        }
    }

    private let queue = DispatchQueue(label: "com.huangenxu.musicxlx.lx-catalog-js", qos: .userInitiated)
    private let transport: LXCatalogHTTPTransport
    private var context: JSContext?
    private var activeTasks: [String: Task<Void, Never>] = [:]
    private var isInvalidated = false

    init(transport: LXCatalogHTTPTransport = LXCatalogHTTPTransport()) {
        self.transport = transport
    }

    /// Evaluates a prebuilt JavaScript bundle containing the original LX modules
    /// plus the compatibility bootstrap. This class does not synthesize provider
    /// APIs; the bundle must export the selected original LX functions.
    func load(bundle: String, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            self.invalidateOnQueue()
            self.isInvalidated = false

            guard let context = JSContext() else {
                completion(.failure(RuntimeError.script("无法创建 JavaScriptCore 上下文。")))
                return
            }
            self.context = context
            context.exceptionHandler = { _, exception in
                NSLog("[MusicXLX:LXCatalog] %@", exception?.toString() ?? "JavaScript exception")
            }

            let nativeFetch: @convention(block) (String, String, String) -> Void = { [weak self] requestID, urlString, optionsJSON in
                guard let self else { return }
                self.queue.async {
                    self.startRequestOnQueue(id: requestID, urlString: urlString, optionsJSON: optionsJSON)
                }
            }
            context.setObject(nativeFetch, forKeyedSubscript: "__lx_catalog_native_fetch" as NSString)

            let nativeCancel: @convention(block) (String) -> Void = { [weak self] requestID in
                guard let self else { return }
                self.queue.async {
                    self.activeTasks.removeValue(forKey: requestID)?.cancel()
                }
            }
            context.setObject(nativeCancel, forKeyedSubscript: "__lx_catalog_native_cancel" as NSString)

            context.evaluateScript(Self.compatibilityBootstrap)
            if let exception = context.exception {
                completion(.failure(RuntimeError.script(exception.toString())))
                return
            }

            context.evaluateScript(bundle, withSourceURL: URL(string: "musicxlx://lx-catalog/bundle.js"))
            if let exception = context.exception {
                completion(.failure(RuntimeError.script(exception.toString())))
                return
            }
            completion(.success(()))
        }
    }

    func call(export name: String, arguments: [Any], completion: @escaping (Result<Any?, Error>) -> Void) {
        queue.async {
            guard !self.isInvalidated, let context = self.context else {
                completion(.failure(RuntimeError.script("目录运行时尚未加载。")))
                return
            }
            guard let function = context.objectForKeyedSubscript("LXCatalog")?.objectForKeyedSubscript(name),
                  function.isObject, function.hasProperty("call") else {
                completion(.failure(RuntimeError.script("目录模块未导出函数：\(name)")))
                return
            }
            let result = function.call(withArguments: arguments)
            if let exception = context.exception {
                context.exception = nil
                completion(.failure(RuntimeError.script(exception.toString())))
            } else {
                completion(.success(result?.toObject()))
            }
        }
    }

    func invalidate() {
        queue.async { self.invalidateOnQueue() }
    }

    private func startRequestOnQueue(id: String, urlString: String, optionsJSON: String) {
        guard !isInvalidated, !id.isEmpty,
              let url = URL(string: urlString),
              let optionsData = optionsJSON.data(using: .utf8),
              let options = (try? JSONSerialization.jsonObject(with: optionsData)) as? [String: Any] else {
            completeRequestOnQueue(id: id, response: nil, error: RuntimeError.invalidRequest.localizedDescription)
            return
        }

        var request = LXCatalogHTTPTransport.Request()
        request.method = (options["method"] as? String ?? "GET").uppercased()
        request.timeout = (options["timeout"] as? NSNumber)?.doubleValue ?? 15
        request.headers = options["headers"] as? [String: String] ?? [:]
        request.form = options["form"] as? [String: String]
        if let body = options["body"] as? String {
            request.body = Data(body.utf8)
        } else if let body = options["body"], JSONSerialization.isValidJSONObject(body),
                  let data = try? JSONSerialization.data(withJSONObject: body) {
            request.body = data
        }

        let wantsBinary = options["binary"] as? Bool == true
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.transport.fetch(url, options: request)
                var response: [String: Any] = [
                    "url": result.url.absoluteString,
                    "statusCode": result.statusCode,
                    "statusMessage": result.statusMessage,
                    "headers": result.headers,
                    "ok": result.isSuccessful
                ]
                if wantsBinary {
                    response["bodyBase64"] = result.body.base64EncodedString()
                } else if let json = result.jsonObject {
                    response["body"] = json
                } else {
                    response["body"] = result.text
                }
                self.queue.async {
                    self.activeTasks.removeValue(forKey: id)
                    self.completeRequestOnQueue(id: id, response: response, error: nil)
                }
            } catch {
                self.queue.async {
                    self.activeTasks.removeValue(forKey: id)
                    self.completeRequestOnQueue(id: id, response: nil, error: error.localizedDescription)
                }
            }
        }
        activeTasks[id] = task
    }

    private func completeRequestOnQueue(id: String, response: [String: Any]?, error: String?) {
        guard let context, !isInvalidated else { return }
        let callback = context.objectForKeyedSubscript("__lxCatalogResolve")
        _ = callback?.call(withArguments: [
            id,
            response ?? NSNull(),
            error ?? NSNull()
        ])
        if let exception = context.exception {
            NSLog("[MusicXLX:LXCatalog] callback exception: %@", exception.toString())
            context.exception = nil
        }
    }

    private func invalidateOnQueue() {
        isInvalidated = true
        activeTasks.values.forEach { $0.cancel() }
        activeTasks.removeAll()
        context?.exceptionHandler = nil
        context?.setObject(nil, forKeyedSubscript: "__lx_catalog_native_fetch" as NSString)
        context?.setObject(nil, forKeyedSubscript: "__lx_catalog_native_cancel" as NSString)
        context = nil
    }

    private static let compatibilityBootstrap = """
    (function (global) {
      var pending = Object.create(null);
      var sequence = 0;

      global.__lxCatalogResolve = function (id, response, error) {
        var item = pending[id];
        if (!item) return;
        delete pending[id];
        if (error && error !== null) {
          item.reject(new Error(String(error)));
          return;
        }
        item.resolve(response);
      };

      global.__lxCatalogHTTPFetch = function (url, options) {
        options = options || {};
        var id = String(++sequence);
        var promise = new Promise(function (resolve, reject) {
          pending[id] = { resolve: resolve, reject: reject };
          global.__lx_catalog_native_fetch(
            id,
            String(url),
            JSON.stringify(options)
          );
        });
        return {
          promise: promise,
          cancelHttp: function () {
            global.__lx_catalog_native_cancel(id);
            var item = pending[id];
            if (item) {
              delete pending[id];
              item.reject(new Error('Aborted'));
            }
          }
        };
      };
    })(this);
    """
}
