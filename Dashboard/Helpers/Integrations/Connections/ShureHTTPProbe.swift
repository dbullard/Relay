import Foundation

final class ShureHTTPProbe: NSObject, URLSessionDelegate {
    private let timeoutSeconds: TimeInterval = 2.5
    private let queue = DispatchQueue(label: "ShureHTTPProbe")
    private var shouldLog: Bool { WirelessLoggingPreferences.shureMasterVerbose }

    func probe(ip: String) {
        let trimmed = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var urls: [URL] = []
        let paths = ["/", "/api", "/status", "/v1"]

        for path in paths {
            if let url = URL(string: "http://\(trimmed)\(path)") {
                urls.append(url)
            }
            if let url = URL(string: "https://\(trimmed)\(path)") {
                urls.append(url)
            }
        }

        queue.async { [weak self] in
            self?.run(urls: urls, index: 0)
        }
    }

    private func run(urls: [URL], index: Int) {
        guard index < urls.count else { return }
        let url = urls[index]
        performRequest(url: url) { [weak self] in
            self?.run(urls: urls, index: index + 1)
        }
    }

    private func performRequest(url: URL, completion: @escaping () -> Void) {
        let session = makeSession()
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutSeconds

        if shouldLog {
            print("[ShureHTTPProbe] GET \(url.absoluteString)")
        }

        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                if self.shouldLog {
                    print("[ShureHTTPProbe] ERROR: \(error.localizedDescription)")
                }
                completion()
                return
            }

            if let http = response as? HTTPURLResponse {
                if self.shouldLog {
                    print("[ShureHTTPProbe] Status: \(http.statusCode)")
                    let headers = http.allHeaderFields
                    print("[ShureHTTPProbe] Headers: \(headers)")
                }
            } else if let response {
                if self.shouldLog {
                    print("[ShureHTTPProbe] Response: \(response)")
                }
            }

            if let data, !data.isEmpty {
                let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
                let snippet = String(body.prefix(500))
                if self.shouldLog {
                    print("[ShureHTTPProbe] Body: \(snippet)")
                }
            }

            completion()
        }

        task.resume()
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeoutSeconds
        config.timeoutIntervalForResource = timeoutSeconds
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust,
           PrivateHostPolicy.isPrivateOrLocal(challenge.protectionSpace.host) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
