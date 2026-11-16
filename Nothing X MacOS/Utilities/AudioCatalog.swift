import Foundation
import IOBluetooth

struct AudioCatalog: Decodable {
    let models: [NearbyAudioModel]
    let variants: [NearbyAudioVariant]

    static let shared: Self = {
        guard let url = Bundle.main.url(forResource: "AudioCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(Self.self, from: data) else {
            assertionFailure("Missing or invalid AudioCatalog.json")
            return Self(models: [], variants: [])
        }
        return catalog
    }()

    func model(named name: String) -> NearbyAudioModel? {
        models.first { $0.matches(name: name) }
    }
}

struct NearbyAudioModel: Decodable, Identifiable, Equatable {
    enum Kind: String, Decodable {
        case earbuds, headphones, neckband, speaker

        var symbol: String {
            switch self {
            case .earbuds: return "earbuds"
            case .headphones: return "headphones"
            case .neckband: return "earbuds"
            case .speaker: return "hifispeaker"
            }
        }
    }

    enum EQ: String, Decodable {
        case equalizer, listening, dirac, dirac7, probe

        var usesListeningMode: Bool { self == .listening || self == .dirac || self == .dirac7 }
        var diracPreset: Int? {
            switch self {
            case .dirac: return 0
            case .dirac7: return 7
            default: return nil
            }
        }
    }

    let id: String
    let title: String
    let aliases: [String]
    let eq: EQ
    let kind: Kind
    let profiles: [String: [AudioProfile]]

    static var allCases: [Self] { AudioCatalog.shared.models }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

    func matches(_ device: IOBluetoothDevice) -> Bool {
        matches(name: device.name ?? device.nameOrAddress ?? "")
    }

    func matches(name: String) -> Bool {
        func normalized(_ value: String) -> String {
            value.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        let key = normalized(name)
        return aliases.contains { normalized($0) == key }
    }

    func configurations(board: String?, firmware: String?) -> [AudioProfile] {
        let selected: [AudioProfile]
        if let board, let profiles = profiles[board] {
            selected = profiles
        } else {
            selected = profiles.sorted { $0.key < $1.key }.flatMap(\.value)
        }
        guard let firmware else { return selected }
        let candidates = selected.filter { $0.contains(firmware: firmware) }
        return candidates.isEmpty ? selected : candidates
    }
}

struct AudioProfile: Decodable {
    enum Ring: String, Decodable { case none, legacy, single, sides }

    let min: String?
    let max: String?
    let anc: Int
    let bass: Bool
    let twoBass: Bool
    let dual: Bool
    let mimi: Bool
    let audiodo: Bool
    let customEQ: Bool
    let advancedEQ: Bool
    let lowLatency: Bool
    let inEar: Bool
    let ring: Ring
    let gestures: [AudioGestureSlot]

    func contains(firmware: String) -> Bool {
        let version = firmware.split(separator: ".", omittingEmptySubsequences: false)
        func compare(_ bound: String) -> ComparisonResult? {
            let components = bound.split(separator: ".", omittingEmptySubsequences: false)
            let actual = version.count == 2 && components.starts(with: ["*", "*"])
                ? ["0", "0"] + version : version
            guard components.count == actual.count else { return nil }
            for (lhs, rhs) in zip(actual, components) where rhs != "*" {
                guard let lhs = Int(lhs), let rhs = Int(rhs) else { return nil }
                if lhs != rhs { return lhs < rhs ? .orderedAscending : .orderedDescending }
            }
            return .orderedSame
        }
        if let min {
            guard let comparison = compare(min), comparison != .orderedAscending else { return false }
        }
        if let max {
            guard let comparison = compare(max), comparison != .orderedDescending else { return false }
        }
        return true
    }
}

struct AudioGestureSlot: Decodable {
    let side: UInt8
    let button: UInt8
    let type: UInt8
    let isPinch: Bool
    let actions: [UInt8]

    init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        side = try values.decode(UInt8.self)
        button = try values.decode(UInt8.self)
        type = try values.decode(UInt8.self)
        isPinch = try values.decode(UInt8.self) != 0
        var actions: [UInt8] = []
        while !values.isAtEnd { actions.append(try values.decode(UInt8.self)) }
        self.actions = actions
    }

    func matches(_ id: EarbudGesture.ID) -> Bool {
        (id.side == side || (side == 2 && id.side == 3)) && id.button == button && id.type == type
    }

    var title: String {
        let press = isPinch ? "Pinch" : "Tap"
        switch type {
        case 1: return button == 10 ? "Slide" : "Single \(press)"
        case 2: return "Double \(press)"
        case 3: return "Triple \(press)"
        case 7: return "\(press) and Hold"
        case 9: return "Double \(press) and Hold"
        case 10: return "Rotate"
        case 11: return "Pinch Both Earbuds"
        default: return "Gesture \(type)"
        }
    }

    static func actionTitle(_ action: UInt8) -> String {
        switch action {
        case 1: return "No action"
        case 2: return "Play or pause"
        case 3: return "Answer call"
        case 8: return "Previous track"
        case 9: return "Next track"
        case 10: return "Cycle noise modes"
        case 11: return "Voice assistant"
        case 17: return "Low latency mode"
        case 18: return "Volume up"
        case 19: return "Volume down"
        case 20: return "Transparency and Off"
        case 21: return "Noise cancellation and Off"
        case 22: return "Noise cancellation and Transparency"
        case 23: return "Volume control"
        case 25: return "Answer call or mute"
        case 26: return "Hang up or decline"
        case 27: return "Spatial audio"
        case 28: return "Bass boost"
        case 29: return "Microphone mute"
        case 34: return "Equaliser preset"
        case 35: return "Bass Enhance"
        case 36: return "Treble Enhance"
        default: return "Current device setting"
        }
    }
}

struct NearbyAudioVariant: Decodable, Identifiable, Hashable {
    let id: String
    let modelID: String
    let colorName: String
    let advertisements: [String: String]
    private(set) var board: String? = nil

    private enum CodingKeys: String, CodingKey { case id, modelID, colorName, advertisements }

    var model: NearbyAudioModel { AudioCatalog.shared.models.first { $0.id == modelID }! }
    var rawValue: String { board.map { "\(id)/\($0)" } ?? id }

    static var allCases: [Self] { AudioCatalog.shared.variants }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: "/", maxSplits: 1).map(String.init)
        guard let key = parts.first, let variant = Self.allCases.first(where: { $0.id == key }) else { return nil }
        self = variant
        if parts.count == 2 && advertisements.values.contains(parts[1]) { board = parts[1] }
    }

    private static let fastPairVariants: [UInt32: Self] = {
        var result: [UInt32: Self] = [:]
        for variant in allCases {
            for (advertisement, board) in variant.advertisements {
                guard let id = UInt32(advertisement, radix: 16) else { continue }
                var option = variant
                option.board = board
                result[id] = option
            }
        }
        return result
    }()

    static func advertised(in payload: Data) -> Self? {
        guard payload.count == 3 else { return nil }
        let modelID = payload.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return fastPairVariants[modelID]
    }
}
