import Foundation

enum RedirectPolicy {
    static func isTheSameOrigin(_ from: URL?, _ to: URL?) -> Bool {
        guard let from, let to else { return false }
        guard let fromScheme = from.scheme?.lowercased(),
              let toScheme = to.scheme?.lowercased(),
              fromScheme == toScheme
        else { return false }
        guard let fromHost = from.host?.lowercased(),
              let toHost = to.host?.lowercased(),
              fromHost == toHost
        else { return false }

        return from.port == to.port
    }
}

final class OneShotRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard RedirectPolicy.isTheSameOrigin(task.originalRequest?.url, request.url) else {
            Journal.log("request.redirectRefused", [
                "from": task.originalRequest?.url?.host ?? "-",
                "status": String(response.statusCode),
                "to": request.url?.host ?? "-",
            ])
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
