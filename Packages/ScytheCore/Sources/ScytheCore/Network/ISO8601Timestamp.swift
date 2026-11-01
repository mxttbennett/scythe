import Foundation

/// Reads Harvest's `2026-10-31T14:22:33Z` without Foundation's 5 µs parser; nil for any other form.
enum ISO8601Timestamp {
    static func date(from text: String) -> Date? {
        var text = text
        return text.withUTF8 { bytes -> Date? in
            guard bytes.count == 20,
                  bytes[4] == UInt8(ascii: "-"), bytes[7] == UInt8(ascii: "-"), bytes[10] == UInt8(ascii: "T"),
                  bytes[13] == UInt8(ascii: ":"), bytes[16] == UInt8(ascii: ":"), bytes[19] == UInt8(ascii: "Z")
            else { return nil }

            func number(_ range: Range<Int>) -> Int? {
                var value = 0
                for index in range {
                    let digit = Int(bytes[index]) - Int(UInt8(ascii: "0"))
                    guard (0...9).contains(digit) else { return nil }
                    value = value * 10 + digit
                }
                return value
            }

            guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
                  let hour = number(11..<13), let minute = number(14..<16), let second = number(17..<19),
                  year >= 1583, (1...12).contains(month), (1...31).contains(day),
                  hour < 24, minute < 60, second < 60
            else { return nil }

            let date = CalendarDate(year: year, month: month, day: day)
            guard CalendarDate(dayNumber: date.dayNumber) == date else { return nil }
            let seconds = date.dayNumber * 86_400 + hour * 3600 + minute * 60 + second
            return Date(timeIntervalSince1970: TimeInterval(seconds))
        }
    }
}
