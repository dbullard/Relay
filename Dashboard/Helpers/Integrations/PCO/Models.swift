import Foundation

// T must be Decodable & Hashable so PCOResource<T> can be decoded and used in SwiftUI selections
public struct PCOCollection<T: Decodable & Hashable>: Decodable {
    public let data: [PCOResource<T>]
    public let included: [PCOIncluded]?
}

public struct PCOResource<T: Decodable & Hashable>: Decodable, Identifiable, Hashable, Equatable {
    public let id: String
    public let attributes: T
    public let relationships: [String: PCORelationship]?
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public struct PCORelationship: Decodable {
    public let data: PCORelationshipData?
}

public enum PCORelationshipData: Decodable {
    case single(PCORef)
    case multiple([PCORef])
    case none

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .none
        } else if let one = try? c.decode(PCORef.self) {
            self = .single(one)
        } else if let many = try? c.decode([PCORef].self) {
            self = .multiple(many)
        } else {
            self = .none
        }
    }
}


public struct PCORef: Decodable {
    public let id: String
    public let type: String
}

public struct PCOIncluded: Decodable {
    public let id: String
    public let type: String
    public let attributes: [String:PCODynamic]
    public let relationships: [String: PCORelationship]?
}

public enum PCODynamic: Decodable {
    case string(String), int(Int), double(Double), bool(Bool), null, obj([String:PCODynamic]), arr([PCODynamic])
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let o = try? c.decode([String:PCODynamic].self) { self = .obj(o); return }
        if let a = try? c.decode([PCODynamic].self) { self = .arr(a); return }
        self = .null
    }
}

// MARK: - Attributes (make sure these are Hashable)
public struct ServiceTypeAttr: Decodable, Hashable {
    public let name: String
}

public struct ServiceTypeFolderAttr: Decodable, Hashable {
    public let name: String
}

public struct FolderAttr: Decodable, Hashable {
    public let name: String
}

public struct PlanAttr: Decodable, Hashable {
    public let title: String?
    public let sort_date: String?
}

public struct ItemAttr: Decodable, Hashable {
    public let title: String?
    public let item_type: String?
    public let length: Int?
    public let key_name: String?
    public let description: String?
    public let html_details: String?
    public let sequence: Int?
    public let custom_arrangement_sequence: [String]?
    public let custom_arrangement_sequence_full: [String]?
    public let custom_arrangement_sequence_short: [String]?
}

public struct ItemTimeAttr: Decodable, Hashable {
    public let starts_at: String?
    public let live_start_at: String?
    public let live_end_at: String?
    public let length: Int?
    public let length_offset: Int?
    public let exclude: Bool?
}

public struct PlanTimeAttr: Decodable, Hashable {
    public let name: String?
    public let starts_at: String?
    public let live_starts_at: String?
}
