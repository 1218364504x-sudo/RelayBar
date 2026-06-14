// Utils/APIError.swift
import Foundation

struct APIError: LocalizedError {
    let statusCode: Int
    let message: String

    var errorDescription: String? {
        "HTTP \(statusCode): \(message)"
    }
}

enum APIHelper {
    struct ErrorResponse: Codable {
        let error: ErrorDetail?
    }
    struct ErrorDetail: Codable {
        let message: String?
        let type: String?
        let code: String?
    }

    static func validateResponse(data: Data, response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorDetail = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            let message = errorDetail?.error?.message ?? "Unknown server error"
            throw APIError(statusCode: httpResponse.statusCode, message: message)
        }
    }
}
