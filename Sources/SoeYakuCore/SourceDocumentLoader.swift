import Foundation

public enum DocumentFormat: Sendable, Equatable { case pdf, html }

public enum DocumentLoadError: Error, Equatable, LocalizedError {
    case unsupportedSource
    case httpStatus(Int)
    case notHTML
    case tooLarge

    public var errorDescription: String? {
        switch self {
        case .unsupportedSource: "PDF・HTML ファイル、または公開ページの HTTP / HTTPS URL を指定してください。URL にユーザー名やパスワードは含められません。"
        case .httpStatus(let status): "ページを取得できませんでした（HTTP \(status)）。公開ページの URL、または保存した HTML を使ってください。"
        case .notHTML: "取得したページは HTML ではありません。PDF は保存してから開いてください。"
        case .tooLarge: "HTML は10 MB以内のファイルを開いてください。"
        }
    }
}

/// Loads file contents, or one public HTML response in an isolated HTTP session.
public enum SourceDocumentLoader {
    public static let maximumHTMLBytes = 10 * 1024 * 1024
    typealias Fetch = @Sendable (URL) async throws -> (Data, HTTPURLResponse)

    public static func format(of url: URL) throws -> DocumentFormat {
        if url.isFileURL {
            switch url.pathExtension.lowercased() {
            case "pdf": return .pdf
            case "html", "htm", "xhtml": return .html
            default: throw DocumentLoadError.unsupportedSource
            }
        }
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil
        else { throw DocumentLoadError.unsupportedSource }
        return .html
    }

    public static func extractFile(_ url: URL) throws -> SourceDocument {
        guard url.isFileURL else { throw DocumentLoadError.unsupportedSource }
        switch try format(of: url) {
        case .pdf: return try PDFExtractor.extract(url: url)
        case .html:
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= maximumHTMLBytes else { throw DocumentLoadError.tooLarge }
            let data = try Data(contentsOf: url)
            guard data.count <= maximumHTMLBytes else { throw DocumentLoadError.tooLarge }
            return try HTMLExtractor.extract(data: data, fallbackTitle: url.deletingPathExtension().lastPathComponent)
        }
    }

    public static func load(_ url: URL) async throws -> SourceDocument {
        try await load(url, fetch: fetchHTML)
    }

    static func load(_ url: URL, fetch: Fetch) async throws -> SourceDocument {
        _ = try format(of: url)
        if url.isFileURL { return try await Task.detached { try extractFile(url) }.value }
        let (data, response) = try await fetch(url)
        try validate(response)
        guard data.count <= maximumHTMLBytes else { throw DocumentLoadError.tooLarge }
        try Task.checkCancellation()
        return try HTMLExtractor.extract(data: data, fallbackTitle: url.lastPathComponent.isEmpty ? (url.host ?? "HTML") : url.lastPathComponent,
                                         textEncodingName: response.textEncodingName)
    }

    private static func validate(_ response: HTTPURLResponse) throws {
        guard (200..<300).contains(response.statusCode) else { throw DocumentLoadError.httpStatus(response.statusCode) }
        guard ["text/html", "application/xhtml+xml"].contains(response.mimeType?.lowercased() ?? "") else { throw DocumentLoadError.notHTML }
        guard response.expectedContentLength <= Int64(maximumHTMLBytes) else { throw DocumentLoadError.tooLarge }
    }

    private static func fetchHTML(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("text/html, application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw DocumentLoadError.notHTML }
        try validate(response)
        var data = Data()
        for try await byte in bytes {
            guard data.count < maximumHTMLBytes else { throw DocumentLoadError.tooLarge }
            data.append(byte)
        }
        return (data, response)
    }
}
