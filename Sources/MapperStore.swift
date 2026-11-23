import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class MapperStore: ObservableObject {
    @Published var enabled: Bool {
        didSet {
            guard enabled != oldValue else { return }
            save()
            refresh()
        }
    }

    @Published var selectedID: String?
    @Published private(set) var profiles: [AppProfile]
    @Published private(set) var status = ""
    @Published private(set) var needsPermission = false

    private let engine = TrackpadEngine()
    private let defaults: UserDefaults
    private var activationObserver: NSObjectProtocol?
    private var refreshTimer: Timer?
    private static let preferencesKey = "MapperPreferences"

    var selectedProfile: AppProfile? {
        profiles.first { $0.id == selectedID }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let data = defaults.data(forKey: Self.preferencesKey)
        let decoded = data.flatMap { try? JSONDecoder().decode(MapperPreferences.self, from: $0) }
        let preferences = decoded ?? MapperPreferences()
        enabled = preferences.enabled
        profiles = preferences.profiles.map {
            var profile = $0
            profile.source = profile.source.clamped()
            profile.destination = profile.destination.clamped()
            return profile
        }
        selectedID = profiles.first?.id

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }

        // Permissions, Spaces, moving or resizing windows, and monitor
        // arrangement can change without another app-activation notification.
        let timer = Timer(timeInterval: 0.65, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        refresh()
    }

    func shutdown() {
        refreshTimer?.invalidate()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        engine.stop()
    }

    func updateProfile(_ profile: AppProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }),
              profiles[index] != profile
        else { return }

        profiles[index] = profile
        save()
        refresh()
    }

    func addApplication() {
        let panel = NSOpenPanel()
        panel.title = "选择要映射的 App"
        panel.prompt = "添加"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window) { [weak self] response in
                if response == .OK, let url = panel.url { self?.addApplication(at: url) }
            }
        } else {
            panel.begin { [weak self] response in
                if response == .OK, let url = panel.url { self?.addApplication(at: url) }
            }
        }
    }

    func removeSelectedProfile() {
        guard let selectedID, let index = profiles.firstIndex(where: { $0.id == selectedID }) else { return }
        profiles.remove(at: index)
        self.selectedID = profiles.isEmpty ? nil : profiles[min(index, profiles.count - 1)].id
        save()
        refresh()
    }

    func requestPermission() {
        if !CGPreflightPostEventAccess() {
            _ = CGRequestPostEventAccess()
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        refresh()
    }

    private func addApplication(at url: URL) {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, id != Bundle.main.bundleIdentifier else {
            let alert = NSAlert()
            alert.messageText = "无法添加这个 App"
            alert.informativeText = "请选择另一个带有 Bundle Identifier 的 macOS 应用。"
            if let window = NSApp.keyWindow {
                alert.beginSheetModal(for: window)
            } else {
                alert.runModal()
            }
            return
        }

        if let index = profiles.firstIndex(where: { $0.id == id }) {
            if profiles[index].bundlePath != url.path {
                profiles[index].bundlePath = url.path
                save()
            }
            selectedID = id
            return
        }

        profiles.append(AppProfile(
            id: id,
            name: url.deletingPathExtension().lastPathComponent,
            isEnabled: true,
            target: .window,
            source: .full,
            destination: .full,
            bundlePath: url.path
        ))
        selectedID = id
        save()
        refresh()
    }

    private func save() {
        let preferences = MapperPreferences(enabled: enabled, profiles: profiles)
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: Self.preferencesKey)
        }
    }

    private func refresh() {
        guard enabled else {
            idle("总开关已关闭")
            return
        }
        guard profiles.contains(where: \.isEnabled) else {
            idle("等待添加或启用 App")
            return
        }
        guard CGPreflightPostEventAccess() else {
            idle("需要辅助功能权限", permission: true)
            return
        }

        let application = NSWorkspace.shared.frontmostApplication
        let preferences = MapperPreferences(enabled: enabled, profiles: profiles)
        guard NSApp?.isActive != true, let application,
              let profile = preferences.profile(for: application.bundleIdentifier)
        else {
            idle("等待切换到已启用的 App")
            return
        }
        guard let bounds = TargetBounds.resolve(profile.target, pid: application.processIdentifier) else {
            idle("找不到 \(profile.name) 的可见窗口")
            return
        }

        switch engine.activate(profile, pid: application.processIdentifier, bounds: bounds) {
        case .running:
            setStatus("正在映射 \(profile.name)")
        case .noTrackpad:
            setStatus("未找到可用的触控板")
        case .frameworkUnavailable:
            setStatus("当前 macOS 无法读取触控板")
        case .eventTapUnavailable:
            setStatus("无法启动鼠标事件过滤，请检查辅助功能权限", permission: true)
        }
    }

    private func idle(_ message: String, permission: Bool = false) {
        engine.stop()
        setStatus(message, permission: permission)
    }

    private func setStatus(_ message: String, permission: Bool = false) {
        if status != message { status = message }
        if needsPermission != permission { needsPermission = permission }
    }
}
