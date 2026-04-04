import Foundation

struct ButtonEvent: Identifiable {
    let id = UUID()
    let button: Int    // 0=top, 1=crown, 2=bottom
    let eventType: Int // 1=single, 2=long start, 3=double, etc.

    var buttonName: String {
        switch button {
        case 0: return "상단"
        case 1: return "크라운"
        case 2: return "하단"
        default: return "알 수 없음"
        }
    }

    var eventName: String {
        switch eventType {
        case 1: return "1회 클릭"
        case 2: return "길게 누름"
        case 3: return "2회 클릭"
        case 4: return "3회 클릭"
        case 5: return "4회 클릭"
        case 6: return "1회+길게"
        case 7: return "2회+길게"
        case 8: return "3회+길게"
        case 11: return "폰 찾기"
        case 12: return "길게 누름 끝"
        default: return "코드 \(eventType)"
        }
    }
}

final class KronabyProtocol {
    func encode(commandId: Int, value: Any) -> Data {
        let msgValue = anyToMsgPack(value)
        let map = MsgPackValue.map([(key: .int(Int64(commandId)), value: msgValue)])
        return MsgPackEncoder.encode(map)
    }

    func encodeArray(_ values: [Any]) -> Data {
        let arr = MsgPackValue.array(values.map { anyToMsgPack($0) })
        return MsgPackEncoder.encode(arr)
    }

    func encodeBinary(commandId: Int, payload: Data) -> Data {
        // {commandId: bin(payload)} — MsgPack map with binary value
        var data = Data()
        // fixmap with 1 entry
        data.append(0x81)
        // key: commandId
        if commandId <= 127 {
            data.append(UInt8(commandId))
        } else {
            data.append(0xCC)
            data.append(UInt8(commandId))
        }
        // value: bin8/bin16
        let count = payload.count
        if count <= 0xFF {
            data.append(0xC4)
            data.append(UInt8(count))
        } else {
            data.append(0xC5)
            var be = UInt16(count).bigEndian
            data.append(Data(bytes: &be, count: 2))
        }
        data.append(payload)
        return data
    }

    func decode(data: Data) -> Any? {
        guard let value = MsgPackDecoder.decode(data) else { return nil }
        return msgPackToAny(value)
    }

    func parseButtonEvent(_ decoded: Any?, commandMap: [String: Int]) -> ButtonEvent? {
        guard let dict = decoded as? [Int: Any],
              let buttonCmdId = commandMap["button"],
              let arr = dict[buttonCmdId] as? [Any],
              arr.count >= 2,
              let button = arr[0] as? Int,
              let eventType = arr[1] as? Int else { return nil }
        return ButtonEvent(button: button, eventType: eventType)
    }

    // MARK: - Conversion helpers

    private func anyToMsgPack(_ value: Any) -> MsgPackValue {
        switch value {
        case let b as Bool:
            return .bool(b)
        case let i as Int:
            return .int(Int64(i))
        case let s as String:
            return .string(s)
        case let arr as [Int]:
            return .array(arr.map { .int(Int64($0)) })
        case let arr as [Any]:
            return .array(arr.map { anyToMsgPack($0) })
        case let dict as [Int: Any]:
            let pairs = dict.map { (key: MsgPackValue.int(Int64($0.key)), value: anyToMsgPack($0.value)) }
            return .map(pairs)
        default:
            return .nil
        }
    }

    private func msgPackToAny(_ value: MsgPackValue) -> Any? {
        switch value {
        case .int(let i): return Int(i)
        case .uint(let u): return Int(u)
        case .string(let s): return s
        case .bool(let b): return b
        case .nil: return nil
        case .array(let arr): return arr.compactMap { msgPackToAny($0) }
        case .map(let pairs):
            // command map response: {string: int} — used during handshake
            var stringDict: [String: Int] = [:]
            var intDict: [Int: Any] = [:]
            var allStringKeyed = true

            for pair in pairs {
                if case .string(let key) = pair.key, case .int(let val) = pair.value {
                    stringDict[key] = Int(val)
                } else if case .string(let key) = pair.key, case .uint(let val) = pair.value {
                    stringDict[key] = Int(val)
                } else {
                    allStringKeyed = false
                }

                let intKey: Int?
                switch pair.key {
                case .int(let k): intKey = Int(k)
                case .uint(let k): intKey = Int(k)
                default: intKey = nil
                }
                if let k = intKey {
                    intDict[k] = msgPackToAny(pair.value)
                }
            }
            return allStringKeyed && !stringDict.isEmpty ? stringDict : intDict
        }
    }
}
