import Foundation
import JavaScriptCore
import CommonCrypto
import Security

/// One isolated JavaScriptCore context per imported LX source script.
/// All JSContext access is serialized on the instance queue.
final class LXJavaScriptRuntime {
    struct ScriptMetadata {
        let id: String
        let name: String
        let description: String
        let version: String
        let author: String
        let homepage: String
    }

    struct RegisteredSource: Decodable {
        struct Platform: Decodable {
            let type: String
            let actions: [String]
            let qualitys: [String]
        }
        let sources: [String: Platform]
    }

    enum RuntimeError: LocalizedError {
        case invalidScript
        case preloadMissing
        case javascript(String)
        case request(String)
        case unsupportedCrypto(String)

        var errorDescription: String? {
            switch self {
            case .invalidScript: return "音源脚本为空或格式无效。"
            case .preloadMissing: return "洛雪运行时 preload 资源缺失。"
            case .javascript(let message): return "音源脚本执行失败：\(message)"
            case .request(let message): return "音源网络请求失败：\(message)"
            case .unsupportedCrypto(let message): return "音源加密操作失败：\(message)"
            }
        }
    }

    private let queue = DispatchQueue(label: "com.huangenxu.musicxlx.lx-runtime", qos: .userInitiated)
    private let session: URLSession
    private var context: JSContext?
    private var requestTasks: [String: URLSessionTask] = [:]
    private var timerWorkItems: [Int: DispatchWorkItem] = [:]
    private var pendingInitCompletion: ((Result<RegisteredSource, Error>) -> Void)?
    private var pendingActionCompletions: [String: (Result<[String: Any], Error>) -> Void] = [:]
    private var actionTimeouts: [String: DispatchWorkItem] = [:]
    private var initTimeoutWorkItem: DispatchWorkItem?
    private var runtimeToken = UUID().uuidString
    private var scriptKey = UUID().uuidString
    private var isDestroyed = false

    init(session: URLSession = .shared) {
        self.session = session
    }

    func load(script: String, metadata: ScriptMetadata, preload: String, completion: @escaping (Result<RegisteredSource, Error>) -> Void) {
        queue.async {
            do {
                guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw RuntimeError.invalidScript
                }
                guard !preload.isEmpty else { throw RuntimeError.preloadMissing }
                self.destroyOnQueue()
                self.isDestroyed = false
                self.runtimeToken = UUID().uuidString
                self.scriptKey = UUID().uuidString

                let ctx = JSContext()!
                self.context = ctx
                ctx.exceptionHandler = { _, exception in
                    let message = exception?.toString() ?? "Unknown JavaScript exception"
                    NSLog("[MusicXLX:LX] %@", message)
                }
                self.installNativeFunctions(in: ctx, token: self.runtimeToken)
                ctx.evaluateScript(preload, withSourceURL: URL(string: "musicxlx://lx/user-api-preload.js"))
                if let exception = ctx.exception { throw RuntimeError.javascript(exception.toString()) }

                let setup = ctx.objectForKeyedSubscript("lx_setup")
                setup?.call(withArguments: [
                    self.scriptKey, metadata.id, metadata.name, metadata.description,
                    metadata.version, metadata.author, metadata.homepage, script
                ])
                if let exception = ctx.exception { throw RuntimeError.javascript(exception.toString()) }

                ctx.evaluateScript(script, withSourceURL: URL(string: "musicxlx://source/\(metadata.id).js"))
                if let exception = ctx.exception { throw RuntimeError.javascript(exception.toString()) }

                // LX source scripts announce readiness through lx.send(EVENT_NAMES.inited, info).
                self.pendingInitCompletion = completion
                let timeout = DispatchWorkItem { [weak self, weak ctx] in
                    guard let self, let ctx, !self.isDestroyed, self.context === ctx else { return }
                    self.pendingInitCompletion?(.failure(RuntimeError.javascript("脚本在 8 秒内未完成 LX 初始化。")))
                    self.pendingInitCompletion = nil
                }
                self.initTimeoutWorkItem = timeout
                self.queue.asyncAfter(deadline: .now() + .seconds(8), execute: timeout)
            } catch {
                self.destroyOnQueue()
                completion(.failure(error))
            }
        }
    }

    func destroy() {
        queue.async { self.destroyOnQueue() }
    }

    /// Invoke an LX-registered provider action (musicUrl, lyric, or pic).
    /// The JavaScript preload validates and normalizes the provider result before returning it.
    func performSourceAction(source: String, action: String, info: [String: Any], timeout: TimeInterval = 20, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        queue.async {
            guard !self.isDestroyed, self.context != nil else {
                completion(.failure(RuntimeError.javascript("音源运行时尚未启动。")))
                return
            }
            guard ["musicUrl", "lyric", "pic"].contains(action) else {
                completion(.failure(RuntimeError.javascript("不支持的音源动作：\(action)")))
                return
            }
            let requestKey = UUID().uuidString
            self.pendingActionCompletions[requestKey] = completion
            let timeoutItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.actionTimeouts.removeValue(forKey: requestKey)
                let callback = self.pendingActionCompletions.removeValue(forKey: requestKey)
                callback?(.failure(RuntimeError.request("音源解析超时。")))
            }
            self.actionTimeouts[requestKey] = timeoutItem
            self.queue.asyncAfter(deadline: .now() + max(1, timeout), execute: timeoutItem)
            let payload: [String: Any] = [
                "requestKey": requestKey,
                "data": ["source": source, "action": action, "info": info]
            ]
            self.callJavaScript(action: "request", json: Self.jsonString(payload))
        }
    }

    private func destroyOnQueue() {
        isDestroyed = true
        runtimeToken = UUID().uuidString
        requestTasks.values.forEach { $0.cancel() }
        requestTasks.removeAll()
        timerWorkItems.values.forEach { $0.cancel() }
        timerWorkItems.removeAll()
        initTimeoutWorkItem?.cancel()
        initTimeoutWorkItem = nil
        pendingInitCompletion = nil
        actionTimeouts.values.forEach { $0.cancel() }
        actionTimeouts.removeAll()
        pendingActionCompletions.removeAll()
        context?.exceptionHandler = nil
        context?.setObject(nil, forKeyedSubscript: "__lx_native_call__" as NSString)
        context = nil
    }

    private func installNativeFunctions(in ctx: JSContext, token: String) {
        let nativeCall: @convention(block) (String, String, String) -> Void = { [weak self] key, action, payload in
            guard let self else { return }
            self.queue.async {
                guard !self.isDestroyed, self.runtimeToken == token, key == self.scriptKey else { return }
                self.handleNativeAction(action, payload: payload, token: token)
            }
        }
        ctx.setObject(nativeCall, forKeyedSubscript: "__lx_native_call__" as NSString)

        let timeout: @convention(block) (NSNumber, NSNumber) -> Void = { [weak self] identifier, milliseconds in
            guard let self else { return }
            let id = identifier.intValue
            let item = DispatchWorkItem { [weak self] in
                guard let self, !self.isDestroyed, self.runtimeToken == token else { return }
                self.timerWorkItems.removeValue(forKey: id)
                self.callJavaScript(action: "__set_timeout__", json: String(id))
            }
            self.timerWorkItems[id]?.cancel()
            self.timerWorkItems[id] = item
            self.queue.asyncAfter(deadline: .now() + .milliseconds(max(0, milliseconds.intValue)), execute: item)
        }
        ctx.setObject(timeout, forKeyedSubscript: "__lx_native_call__set_timeout" as NSString)

        let base64: @convention(block) (String) -> String = { Data($0.utf8).base64EncodedString() }
        ctx.setObject(base64, forKeyedSubscript: "__lx_native_call__utils_str2b64" as NSString)
        let decode: @convention(block) (String) -> String = { value in
            let bytes = Data(base64Encoded: value) ?? Data()
            let array = Array(bytes)
            let data = (try? JSONSerialization.data(withJSONObject: array)) ?? Data("[]".utf8)
            return String(data: data, encoding: .utf8) ?? "[]"
        }
        ctx.setObject(decode, forKeyedSubscript: "__lx_native_call__utils_b642buf" as NSString)
        let md5: @convention(block) (String) -> String = { value in
            let digest = Data(value.utf8).withUnsafeBytes { raw in
                var output = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
                _ = CC_MD5(raw.baseAddress, CC_LONG(raw.count), &output)
                return output
            }
            return digest.map { String(format: "%02x", $0) }.joined()
        }
        ctx.setObject(md5, forKeyedSubscript: "__lx_native_call__utils_str2md5" as NSString)

        let aes: @convention(block) (String, String, String, String) -> String = { input, key, iv, mode in
            do { return try Self.aesEncrypt(inputBase64: input, keyBase64: key, ivBase64: iv, mode: mode) }
            catch { NSLog("[MusicXLX:LX] AES: %@", error.localizedDescription); return "" }
        }
        ctx.setObject(aes, forKeyedSubscript: "__lx_native_call__utils_aes_encrypt" as NSString)

        let rsa: @convention(block) (String, String, String) -> String = { input, key, padding in
            do { return try Self.rsaEncrypt(inputBase64: input, publicKeyBase64: key) }
            catch { NSLog("[MusicXLX:LX] RSA: %@", error.localizedDescription); return "" }
        }
        ctx.setObject(rsa, forKeyedSubscript: "__lx_native_call__utils_rsa_encrypt" as NSString)
    }

    private func handleNativeAction(_ action: String, payload: String, token: String) {
        switch action {
        case "request":
            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let key = object["requestKey"] as? String,
                  let urlString = object["url"] as? String,
                  let url = URL(string: urlString),
                  let options = object["options"] as? [String: Any] else { return }
            performRequest(key: key, url: url, options: options, token: token)
        case "cancelRequest":
            let requestKey = (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? String ?? payload
            requestTasks.removeValue(forKey: requestKey)?.cancel()
        case "response":
            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let requestKey = object["requestKey"] as? String else { return }
            actionTimeouts.removeValue(forKey: requestKey)?.cancel()
            let callback = pendingActionCompletions.removeValue(forKey: requestKey)
            if object["status"] as? Bool == true, let result = object["result"] as? [String: Any] {
                callback?(.success(result))
            } else {
                callback?(.failure(RuntimeError.request(object["errorMessage"] as? String ?? "音源返回失败。")))
            }
        case "init":
            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                pendingInitCompletion?(.failure(RuntimeError.javascript("LX 初始化数据格式错误。")))
                pendingInitCompletion = nil
                return
            }
            guard object["status"] as? Bool == true,
                  let info = object["info"],
                  let infoData = try? JSONSerialization.data(withJSONObject: info),
                  let registered = try? JSONDecoder().decode(RegisteredSource.self, from: infoData) else {
                let message = object["errorMessage"] as? String ?? "脚本没有注册任何有效音源平台。"
                pendingInitCompletion?(.failure(RuntimeError.javascript(message)))
                pendingInitCompletion = nil
                return
            }
            initTimeoutWorkItem?.cancel()
            initTimeoutWorkItem = nil
            pendingInitCompletion?(.success(registered))
            pendingInitCompletion = nil
        case "showUpdateAlert":
            NSLog("[MusicXLX:LX] source update notice: %@", payload)
        default:
            NSLog("[MusicXLX:LX] ignored native action: %@", action)
        }
    }

    private func performRequest(key: String, url: URL, options: [String: Any], token: String) {
        var request = URLRequest(url: url)
        request.httpMethod = (options["method"] as? String ?? "GET").uppercased()
        request.timeoutInterval = min(max(options["timeout"] as? Double ?? 20, 1), 60)
        if let headers = options["headers"] as? [String: String] {
            headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        }
        if let body = options["body"] as? String { request.httpBody = Data(body.utf8) }
        if let form = options["form"] as? [String: Any],
           let encoded = form.map({ "\(Self.formEncode($0.key))=\(Self.formEncode(String(describing: $0.value)))" }).joined(separator: "&").data(using: .utf8) {
            request.httpBody = encoded
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            }
        }
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            self.queue.async {
                guard !self.isDestroyed, self.runtimeToken == token else { return }
                self.requestTasks.removeValue(forKey: key)
                let result: [String: Any]
                if let error {
                    result = ["requestKey": key, "error": error.localizedDescription, "response": NSNull()]
                } else if let response = response as? HTTPURLResponse {
                    let raw = data ?? Data()
                    let binary = options["binary"] as? Bool == true
                    let body: Any = binary ? Array(raw) : (String(data: raw, encoding: .utf8) ?? raw.base64EncodedString())
                    let headers = response.allHeaderFields.reduce(into: [String: String]()) { output, pair in
                        output[String(describing: pair.key)] = String(describing: pair.value)
                    }
                    result = ["requestKey": key, "error": NSNull(), "response": [
                        "statusCode": response.statusCode,
                        "statusMessage": HTTPURLResponse.localizedString(forStatusCode: response.statusCode),
                        "headers": headers,
                        "body": body
                    ]]
                } else {
                    result = ["requestKey": key, "error": "Invalid HTTP response", "response": NSNull()]
                }
                self.callJavaScript(action: "response", json: Self.jsonString(result))
            }
        }
        requestTasks[key] = task
        task.resume()
    }

    private func callJavaScript(action: String, json: String) {
        guard let ctx = context else { return }
        let native = ctx.objectForKeyedSubscript("__lx_native__")
        _ = native?.call(withArguments: [scriptKey, action, json])
        if let exception = ctx.exception { NSLog("[MusicXLX:LX] callback: %@", exception.toString()) }
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func jsonString(_ value: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }

    private static func aesEncrypt(inputBase64: String, keyBase64: String, ivBase64: String, mode: String) throws -> String {
        guard let input = Data(base64Encoded: inputBase64), let key = Data(base64Encoded: keyBase64) else {
            throw RuntimeError.unsupportedCrypto("AES 输入不是有效 Base64")
        }
        let ecb = mode == "AES"
        let iv = ecb ? nil : Data(base64Encoded: ivBase64)
        guard key.count == kCCKeySizeAES128, ecb || iv?.count == kCCBlockSizeAES128 else {
            throw RuntimeError.unsupportedCrypto("仅支持 128-bit AES，CBC 需要 16-byte IV")
        }
        let outputCapacity = input.count + kCCBlockSizeAES128
        var output = [UInt8](repeating: 0, count: outputCapacity)
        var moved = 0
        let status = input.withUnsafeBytes { inputBytes in
            key.withUnsafeBytes { keyBytes in
                iv?.withUnsafeBytes { ivBytes in
                    CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(ecb ? 0 : kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, key.count, ecb ? nil : ivBytes.baseAddress,
                            inputBytes.baseAddress, input.count, &output, outputCapacity, &moved)
                } ?? CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
                             CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode),
                             keyBytes.baseAddress, key.count, nil, inputBytes.baseAddress,
                             input.count, &output, outputCapacity, &moved)
            }
        }
        guard status == kCCSuccess else { throw RuntimeError.unsupportedCrypto("CommonCrypto status \(status)") }
        return Data(output.prefix(moved)).base64EncodedString()
    }

    private static func rsaEncrypt(inputBase64: String, publicKeyBase64: String) throws -> String {
        guard let input = Data(base64Encoded: inputBase64),
              let keyData = Data(base64Encoded: publicKeyBase64) else {
            throw RuntimeError.unsupportedCrypto("RSA 输入不是有效 Base64")
        }
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            throw RuntimeError.unsupportedCrypto(error?.takeRetainedValue().localizedDescription ?? "RSA 公钥格式无效")
        }
        let algorithm: SecKeyAlgorithm = .rsaEncryptionRaw
        guard SecKeyIsAlgorithmSupported(key, .encrypt, algorithm),
              let encrypted = SecKeyCreateEncryptedData(key, algorithm, input as CFData, &error) else {
            throw RuntimeError.unsupportedCrypto(error?.takeRetainedValue().localizedDescription ?? "RSA 加密失败")
        }
        return (encrypted as Data).base64EncodedString()
    }
}
