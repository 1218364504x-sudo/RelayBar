// kxTests/KeychainStorageTests.swift
import XCTest
@testable import CostBar_kx

final class KeychainStorageTests: XCTestCase {
    let storage = KeychainStorage()
    let testKey = "testKeychainKey"
    let testValue = "test-keychain-value"

    override func tearDown() {
        try? storage.delete(key: testKey)
        super.tearDown()
    }

    func testSaveAndRead() throws {
        try storage.save(key: testKey, value: testValue)
        let readValue = try storage.read(key: testKey)
        XCTAssertEqual(readValue, testValue)
    }

    func testDelete() throws {
        try storage.save(key: testKey, value: testValue)
        try storage.delete(key: testKey)
        XCTAssertThrowsError(try storage.read(key: testKey)) { error in
            XCTAssertTrue(error is KeychainError)
        }
    }
}
