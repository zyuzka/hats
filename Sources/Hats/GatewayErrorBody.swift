import Foundation

enum GatewayErrorBody {
    static let refusal = Data("""
        {"type":"error","error":{"type":"authentication_error",\
        "message":"gateway: the account was switched; re-read it"}}
        """.utf8)

    static func describing(_ reason: String) -> Data {
        let payload: [String: Any] = [
            "type": "error",
            "error": ["type": "api_error", "message": "gateway: " + reason],
        ]
        let encoded = try? JSONSerialization.data(withJSONObject: payload)
        return encoded ?? Data("""
            {"type":"error","error":{"type":"api_error","message":"gateway failed"}}
            """.utf8)
    }
}
