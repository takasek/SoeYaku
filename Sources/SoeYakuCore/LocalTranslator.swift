import Foundation
import CFNetwork

public struct TranslationPair: Sendable, Equatable {
    public let source: String
    public let translation: String
    public init(source: String, translation: String) {
        self.source = source
        self.translation = translation
    }
}

public protocol SentenceTranslator: Sendable {
    func translate(_ source: String, context: String, history: [TranslationPair], glossary: Glossary) async throws -> String
}

private final class LocalHTTPDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public struct LocalTranslator: SentenceTranslator {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: false, kCFNetworkProxiesHTTPSEnable as String: false,
            kCFNetworkProxiesSOCKSEnable as String: false, kCFNetworkProxiesProxyAutoConfigEnable as String: false,
            kCFNetworkProxiesProxyAutoDiscoveryEnable as String: false,
            kCFNetworkProxiesExceptionsList as String: ["127.0.0.1"]
        ]
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config, delegate: LocalHTTPDelegate(), delegateQueue: nil)
    }()

    private let endpoint: URL
    private let apiKey: String?

    public init(port: Int, apiKey: String?) throws {
        guard (1...65535).contains(port), let url = URL(string: "http://127.0.0.1:\(port)/completion") else {
            throw TranslationError("ポートは 1〜65535 で指定してください。")
        }
        endpoint = url
        self.apiKey = apiKey
    }

    public func translate(_ source: String, context: String, history: [TranslationPair],
                          glossary: Glossary) async throws -> String {
        let prompt = PFML3.prompt(source, context: context, history: history, glossary: glossary)
        let request = try request(for: prompt)
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw TranslationError("ローカル翻訳サーバーが応答エラーを返しました（HTTP \(status)）。")
        }
        return try Self.completed(data)
    }

    func request(for prompt: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey { request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "prompt": prompt, "n_predict": 512, "stream": false, "temperature": 0, "top_k": 1, "min_p": 0,
            "repeat_penalty": 1.0, "repeat_last_n": 0, "cache_prompt": false,
            "stop": ["<|plamo:tag|>", "<|plamo:bos|>", "<|plamo:eos|>"]
        ])
        return request
    }

    static func completed(_ data: Data) throws -> String {
        struct Completion: Decodable {
            let content: String
            let stop: Bool
            let stop_type: String
            let truncated: Bool?
        }
        let result = try JSONDecoder().decode(Completion.self, from: data)
        let text = result.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.stop, result.truncated != true, ["word", "eos"].contains(result.stop_type), !text.isEmpty else {
            throw TranslationError("翻訳が完了しませんでした。入力の長さとサーバーの状態を確認してください。")
        }
        return text
    }
}
