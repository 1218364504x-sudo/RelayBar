import XCTest
@testable import CostBar_kx

final class OpenAIServiceTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testFetchBalanceDecodesSnakeCaseBillingFields() async throws {
        let service = makeService { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/dashboard/billing/subscription") {
                return Self.response("""
                {
                  "hard_limit_usd": 120.0,
                  "soft_limit_usd": 100.0
                }
                """)
            }

            return Self.response("""
            {
              "total_usage": 3450
            }
            """)
        }

        let balance = try await service.fetchBalance()

        XCTAssertEqual(balance.grantAmount, 120.0)
        XCTAssertEqual(balance.totalUsed, 34.5)
        XCTAssertEqual(balance.totalBalance, 85.5)
        XCTAssertEqual(balance.currency, "USD")
    }

    func testFetchBalanceThrowsWhenHardLimitIsMissing() async {
        let service = makeService { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/dashboard/billing/subscription") {
                return Self.response("{}")
            }

            return Self.response("""
            {
              "total_usage": 3450
            }
            """)
        }

        await XCTAssertThrowsErrorAsync(try await service.fetchBalance())
    }

    func testFetchBalanceThrowsWhenTotalUsageIsMissing() async {
        let service = makeService { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/dashboard/billing/subscription") {
                return Self.response("""
                {
                  "hard_limit_usd": 120.0
                }
                """)
            }

            return Self.response("{}")
        }

        await XCTAssertThrowsErrorAsync(try await service.fetchBalance())
    }

    func testFetchUsageKeepsDailyTimestamps() async throws {
        let service = makeService { _ in
            Self.response("""
            {
              "daily_costs": [
                {
                  "timestamp": 1714521600,
                  "cost": 1.25,
                  "line_items": [
                    { "name": "gpt", "cost": 1.25 }
                  ]
                }
              ],
              "total_usage": 125
            }
            """)
        }

        let records = try await service.fetchUsage(startDate: Date(), endDate: Date())

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].cost, 0.0125, accuracy: 0.0001)
        XCTAssertEqual(records[0].timestamp.timeIntervalSince1970, 1_714_521_600)
    }

    private func makeService(handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) -> OpenAIService {
        MockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let config = ProviderConfig(provider: .openai, apiKey: "test-key")
        return OpenAIService(config: config, session: session)
    }

    private static func response(_ json: String) -> (HTTPURLResponse, Data) {
        let url = URL(string: "https://api.openai.com/test")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, Data(json.utf8))
    }
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> some Any,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch {
        // Expected.
    }
}
