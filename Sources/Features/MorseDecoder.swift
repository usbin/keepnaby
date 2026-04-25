import Foundation

enum MorseSymbol: String, Codable {
    case dot = "."
    case dash = "-"
}

enum MorseDecoder {
    static let table: [String: Character] = [
        ".-":   "A", "-...": "B", "-.-.": "C", "-..":  "D", ".":    "E",
        "..-.": "F", "--.":  "G", "....": "H", "..":   "I", ".---": "J",
        "-.-":  "K", ".-..": "L", "--":   "M", "-.":   "N", "---":  "O",
        ".--.": "P", "--.-": "Q", ".-.":  "R", "...":  "S", "-":    "T",
        "..-":  "U", "...-": "V", ".--":  "W", "-..-": "X", "-.--": "Y",
        "--..": "Z",
        ".----": "1", "..---": "2", "...--": "3", "....-": "4", ".....": "5",
        "-....": "6", "--...": "7", "---..": "8", "----.": "9", "-----": "0"
    ]

    private static let reverseTable: [Character: String] = {
        var dict: [Character: String] = [:]
        for (code, char) in table { dict[char] = code }
        return dict
    }()

    static func decode(_ symbols: [MorseSymbol]) -> Character? {
        guard !symbols.isEmpty else { return nil }
        return table[symbolString(symbols)]
    }

    static func encode(_ char: Character) -> [MorseSymbol]? {
        let upper = Character(char.uppercased())
        guard let code = reverseTable[upper] else { return nil }
        return code.map { $0 == "." ? .dot : .dash }
    }

    static func symbolString(_ symbols: [MorseSymbol]) -> String {
        symbols.map { $0.rawValue }.joined()
    }

    /// 문자열을 모스코드로 변환 (UI 미리보기용). 변환 불가 문자는 "?"로 표시.
    static func encodeString(_ text: String) -> String {
        text.map { ch -> String in
            if let code = reverseTable[Character(ch.uppercased())] {
                return code
            } else {
                return "?"
            }
        }.joined(separator: " ")
    }
}
