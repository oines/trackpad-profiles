import AppKit
import CoreGraphics

enum RegionResizeEdge {
    case minimum
    case maximum
}

struct NormalizedRegion: Codable, Equatable {
    static let minimumSize = 0.05
    static let full = Self(x: 0, y: 0, width: 1, height: 1)

    var x: Double
    var y: Double
    var width: Double
    var height: Double

    func moved(toX proposedX: Double, y proposedY: Double) -> Self {
        Self(
            x: min(max(proposedX, 0), 1 - width),
            y: min(max(proposedY, 0), 1 - height),
            width: width,
            height: height
        )
    }

    func resized(width newWidth: Double, height newHeight: Double) -> Self {
        let safeWidth = min(max(newWidth, Self.minimumSize), 1)
        let safeHeight = min(max(newHeight, Self.minimumSize), 1)
        return Self(x: x, y: y, width: safeWidth, height: safeHeight)
            .moved(toX: x + (width - safeWidth) / 2, y: y + (height - safeHeight) / 2)
    }

    func resizing(
        horizontal: RegionResizeEdge? = nil,
        vertical: RegionResizeEdge? = nil,
        deltaX: Double,
        deltaY: Double
    ) -> Self {
        let horizontalAxis = Self.resizeAxis(origin: x, length: width, edge: horizontal, delta: deltaX)
        let verticalAxis = Self.resizeAxis(origin: y, length: height, edge: vertical, delta: deltaY)
        return Self(
            x: horizontalAxis.origin,
            y: verticalAxis.origin,
            width: horizontalAxis.length,
            height: verticalAxis.length
        )
    }

    private static func resizeAxis(
        origin: Double,
        length: Double,
        edge: RegionResizeEdge?,
        delta: Double
    ) -> (origin: Double, length: Double) {
        guard let edge, delta.isFinite else { return (origin, length) }

        switch edge {
        case .minimum:
            let end = origin + length
            let newLength = min(max(length - delta, minimumSize), end)
            return (end - newLength, newLength)
        case .maximum:
            let newLength = min(max(length + delta, minimumSize), 1 - origin)
            return (origin, newLength)
        }
    }

    func clamped() -> Self {
        guard [x, y, width, height].allSatisfy(\.isFinite) else { return .full }

        let safeWidth = min(max(width, Self.minimumSize), 1)
        let safeHeight = min(max(height, Self.minimumSize), 1)
        return Self(x: x, y: y, width: safeWidth, height: safeHeight).moved(toX: x, y: y)
    }

    func projected(into bounds: CGRect) -> CGRect {
        CGRect(
            x: bounds.minX + bounds.width * x,
            y: bounds.minY + bounds.height * y,
            width: bounds.width * width,
            height: bounds.height * height
        )
    }
}

enum MappingTarget: String, Codable, CaseIterable {
    case window
    case display
}

struct AppProfile: Identifiable, Equatable, Codable {
    static let osuID = "sh.ppy.osu.lazer"

    var id: String
    var name: String
    var isEnabled: Bool
    var target: MappingTarget
    var source: NormalizedRegion
    var destination: NormalizedRegion
    var bundlePath: String?

    var applicationURL: URL? {
        if let bundlePath, FileManager.default.fileExists(atPath: bundlePath) {
            return URL(fileURLWithPath: bundlePath)
        }

        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    }

    var icon: NSImage? {
        applicationURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    func map(x: Double, y: Double, to bounds: CGRect) -> CGPoint? {
        guard x.isFinite, y.isFinite, !bounds.isEmpty, !bounds.isInfinite else { return nil }

        let normalX = min(max((x - source.x) / source.width, 0), 1)
        let normalY = min(max((y - source.y) / source.height, 0), 1)
        let output = destination.projected(into: bounds)
        // Quartz rectangles use exclusive right and bottom edges.
        return CGPoint(
            x: min(output.minX + normalX * output.width, max(output.minX, output.maxX - 1)),
            y: min(output.minY + normalY * output.height, max(output.minY, output.maxY - 1))
        )
    }
}

struct MapperPreferences: Codable {
    var enabled = false
    var profiles: [AppProfile] = []

    func profile(for bundleID: String?) -> AppProfile? {
        guard enabled, let bundleID else { return nil }
        return profiles.first { $0.id == bundleID && $0.isEnabled }
    }
}
