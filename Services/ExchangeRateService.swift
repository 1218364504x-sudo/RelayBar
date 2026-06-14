import Foundation

struct ExchangeRateSnapshot: Codable, Equatable {
    let rate: Double
    let fetchedAt: Date
}

struct ExchangeRateService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchUSDCNYRate() async throws -> ExchangeRateSnapshot {
        let url = URL(string: "https://api.frankfurter.dev/v2/rate/USD/CNY")!
        let (data, response) = try await session.data(from: url)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        struct RateEnvelope: Decodable {
            let rates: [String: Double]
        }

        let envelope = try JSONDecoder().decode(RateEnvelope.self, from: data)
        guard let rate = envelope.rates["CNY"] else {
            throw URLError(.cannotParseResponse)
        }
        return ExchangeRateSnapshot(rate: rate, fetchedAt: Date())
    }
}
