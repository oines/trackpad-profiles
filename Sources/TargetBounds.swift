import CoreGraphics
import Foundation

enum TargetBounds {
    static func resolve(_ target: MappingTarget, pid: pid_t) -> CGRect? {
        let window = largestVisibleWindow(pid: pid)
        let display = window.flatMap(bestDisplay) ?? CGDisplayBounds(CGMainDisplayID())

        switch target {
        case .window:
            guard let window else { return nil }
            let visible = window.intersection(display)
            return visible.isEmpty ? nil : visible
        case .display:
            return display.isEmpty ? nil : display
        }
    }

    private static func largestVisibleWindow(pid: pid_t) -> CGRect? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        return windows.compactMap { info -> CGRect? in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
                  let dictionary = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
                  bounds.width >= 120, bounds.height >= 100
            else { return nil }

            return bounds
        }.max { $0.width * $0.height < $1.width * $1.height }
    }

    private static func bestDisplay(for window: CGRect) -> CGRect? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return nil }

        return displays.prefix(Int(count)).map(CGDisplayBounds).filter {
            !$0.intersection(window).isEmpty
        }.max {
            let left = $0.intersection(window)
            let right = $1.intersection(window)
            return left.width * left.height < right.width * right.height
        }
    }
}
