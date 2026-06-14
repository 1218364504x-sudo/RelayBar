// kxTests/DeepSeekServiceTests.swift
import XCTest
@testable import CostBar_kx

final class DeepSeekServiceTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testBalanceParsing() async throws {
        let service = makeService { _ in
            Self.response("""
            {
              "is_available": true,
              "balance_infos": [
                {
                  "currency": "CNY",
                  "total_balance": "10.50",
                  "granted_balance": 5.0,
                  "topped_up_balance": "5.50"
                }
              ]
            }
            """)
        }

        let balance = try await service.fetchBalance()

        XCTAssertEqual(balance.totalBalance, 10.5)
        XCTAssertEqual(balance.grantAmount, 5.0)
        XCTAssertEqual(balance.toppedUpAmount, 5.5)
        XCTAssertEqual(balance.currency, "CNY")
    }

    func testMissingTotalBalanceThrowsInsteadOfReturningZero() async {
        let service = makeService { _ in
            Self.response("""
            {
              "is_available": true,
              "balance_infos": [
                {
                  "currency": "CNY",
                  "granted_balance": "5.00",
                  "topped_up_balance": "5.50"
                }
              ]
            }
            """)
        }

        await XCTAssertThrowsErrorAsync(try await service.fetchBalance())
    }

    func testUnavailableBalanceThrowsInsteadOfReturningZero() async {
        let service = makeService { _ in
            Self.response("""
            {
              "is_available": false,
              "balance_infos": [
                {
                  "currency": "CNY",
                  "total_balance": "0",
                  "granted_balance": "0",
                  "topped_up_balance": "0"
                }
              ]
            }
            """)
        }

        await XCTAssertThrowsErrorAsync(try await service.fetchBalance())
    }

    private func makeService(handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) -> DeepSeekService {
        MockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let config = ProviderConfig(provider: .deepseek, apiKey: "test-key")
        return DeepSeekService(config: config, session: session)
    }

    private static func response(_ json: String) -> (HTTPURLResponse, Data) {
        let url = URL(string: "https://api.deepseek.com/test")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, Data(json.utf8))
    }
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
