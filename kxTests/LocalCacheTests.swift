// kxTests/LocalCacheTests.swift
import XCTest
@testable import CostBar_kx

final class LocalCacheTests: XCTestCase {
    let cache = LocalCache()
    let provider = AIProvider.deepseek

    func testSaveAndLoadUsageHistory() throws {
        let records = [
            UsageRecord(provider: .deepseek, promptTokens: 100, completionTokens: 50, cost: 0.015),
            UsageRecord(provider: .deepseek, promptTokens: 200, completionTokens: 100, cost: 0.03)
        ]
        try cache.saveUsageHistory(records, for: provider)
        let loaded = try cache.loadUsageHistory(for: provider)
        XCTAssertEqual(loaded.count, records.count)
        XCTAssertEqual(loaded[0].totalTokens, 150)
        XCTAssertEqual(loaded[1].totalTokens, 300)
    }

    func testSaveAndLoadConfigPreservesNonSecretFields() throws {
        var config = ProviderConfig(provider: .openai, apiKey: "placeholder-api-key", baseURL: "https://example.com")
        config.isEnabled = false
        config.displayOrder = 42

        try cache.saveConfig([config])
        let loaded = try cache.loadConfig()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].provider, .openai)
        XCTAssertEqual(loaded[0].apiKey, "")
        XCTAssertEqual(loaded[0].baseURL, "https://example.com")
        XCTAssertFalse(loaded[0].isEnabled)
        XCTAssertEqual(loaded[0].displayOrder, 42)
    }
}
