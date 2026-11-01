import Foundation
import Testing
@testable import ScytheCore

@Suite("Snake case keys")
struct SnakeCaseKeysTests {
    private static let keys = [
        "spent_date", "hours_without_timer", "timer_started_at", "is_running", "id", "name", "x_y", "a_b_c_d",
        "_leading", "trailing_", "__both__", "a__b", "_", "__", "", "alreadyCamel", "Mixed_Case_Key", "UPPER_CASE",
        "with_digit2_here", "v2_api", "a1_b", "ünïcode_kéy", "ÜBER_cool", "end_with_9", "x_1y", "snake_case_with_ß",
    ]

    /// What a decoder with the given strategy calls the one key of an object.
    private struct Names: Decodable {
        let names: [String]

        struct Key: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        init(from decoder: any Decoder) throws {
            names = try decoder.container(keyedBy: Key.self).allKeys.map(\.stringValue)
        }
    }

    private func decodedName(_ key: String, strategy: JSONDecoder.KeyDecodingStrategy) throws -> String {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = strategy
        let json = try JSONSerialization.data(withJSONObject: [key: 1])
        return try #require(try decoder.decode(Names.self, from: json).names.first)
    }

    private func builtIn(_ key: String) throws -> String {
        try decodedName(key, strategy: .convertFromSnakeCase)
    }

    @Test("converts every key exactly as the built-in strategy does", arguments: keys)
    func matchesBuiltIn(key: String) throws {
        // Act
        let converted = try decodedName(key, strategy: SnakeCaseKeys.strategy)

        // Assert
        #expect(converted == (try builtIn(key)), "key: \(key)")
        #expect(SnakeCaseKeys.camelCased(key) == converted, "key: \(key)")
    }

    @Test("decodes through a decoder that uses the strategy")
    func decodesWithStrategy() throws {
        // Arrange
        struct Row: Decodable, Equatable {
            let spentDate: String
            let hoursWithoutTimer: Double
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = SnakeCaseKeys.strategy
        let json = Data(#"{"spent_date":"2026-10-31","hours_without_timer":1.5}"#.utf8)

        // Act
        let row = try decoder.decode(Row.self, from: json)

        // Assert
        #expect(row == Row(spentDate: "2026-10-31", hoursWithoutTimer: 1.5))
    }
}
