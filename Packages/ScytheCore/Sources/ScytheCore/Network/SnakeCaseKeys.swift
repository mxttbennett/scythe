import Foundation

/// Same keys as `convertFromSnakeCase`, but lowercase ASCII converts in one byte pass instead of split and capitalize.
enum SnakeCaseKeys {
    static var strategy: JSONDecoder.KeyDecodingStrategy {
        .custom { path in
            guard let key = path.last, key.intValue == nil else { return path.last ?? Key(stringValue: "") }
            return Key(stringValue: camelCased(key.stringValue))
        }
    }

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    static func camelCased(_ key: String) -> String {
        var key = key
        let fast = key.withUTF8 { bytes -> String? in
            let underscore = UInt8(ascii: "_")
            guard let first = bytes.first, first != underscore, bytes.last != underscore else { return nil }
            var previous = UInt8(0)
            var hasUnderscore = false
            for byte in bytes {
                guard (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")) || byte == underscore else { return nil }
                if byte == underscore {
                    if previous == underscore { return nil }
                    hasUnderscore = true
                }
                previous = byte
            }
            guard hasUnderscore else { return String(decoding: bytes, as: UTF8.self) }
            return String(unsafeUninitializedCapacity: bytes.count) { buffer in
                var count = 0
                var upper = false
                for byte in bytes {
                    if byte == underscore {
                        upper = true
                    } else {
                        buffer[count] = upper ? byte - 0x20 : byte
                        count += 1
                        upper = false
                    }
                }
                return count
            }
        }
        return fast ?? general(key)
    }

    private static func general(_ key: String) -> String {
        guard !key.isEmpty, let firstNonUnderscore = key.firstIndex(where: { $0 != "_" }) else { return key }
        var lastNonUnderscore = key.index(before: key.endIndex)
        while lastNonUnderscore > firstNonUnderscore, key[lastNonUnderscore] == "_" {
            key.formIndex(before: &lastNonUnderscore)
        }
        let leading = key[key.startIndex..<firstNonUnderscore]
        let trailing = key[key.index(after: lastNonUnderscore)...]
        let components = key[firstNonUnderscore...lastNonUnderscore].split(separator: "_")
        let joined = components.count == 1
            ? String(key[firstNonUnderscore...lastNonUnderscore])
            : ([components[0].lowercased()] + components[1...].map { $0.capitalized }).joined()
        return leading + joined + trailing
    }
}
