import Foundation

public enum WindowPlacement: String, Codable, CaseIterable, Identifiable, Sendable {
    case center
    case leftHalf
    case rightHalf

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .center: "Center"
        case .leftHalf: "Left"
        case .rightHalf: "Right"
        }
    }
}

public struct WindowRule: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var bundleIdentifier: String
    public var applicationName: String
    public var placement: WindowPlacement
    public var centeredWidth: Double
    public var centeredHeight: Double
    public var restoreSize: Bool
    public var restorePosition: Bool

    public init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        applicationName: String,
        placement: WindowPlacement,
        centeredWidth: Double,
        centeredHeight: Double,
        restoreSize: Bool = true,
        restorePosition: Bool = true
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.placement = placement
        self.centeredWidth = centeredWidth
        self.centeredHeight = centeredHeight
        self.restoreSize = restoreSize
        self.restorePosition = restorePosition
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case bundleIdentifier
        case applicationName
        case placement
        case centeredWidth
        case centeredHeight
        case restoreSize
        case restorePosition
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        applicationName = try container.decode(String.self, forKey: .applicationName)
        placement = try container.decode(WindowPlacement.self, forKey: .placement)
        centeredWidth = try container.decode(Double.self, forKey: .centeredWidth)
        centeredHeight = try container.decode(Double.self, forKey: .centeredHeight)
        restoreSize = try container.decodeIfPresent(Bool.self, forKey: .restoreSize) ?? true
        restorePosition = try container.decodeIfPresent(Bool.self, forKey: .restorePosition) ?? true
    }
}
