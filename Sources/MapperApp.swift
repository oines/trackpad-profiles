import AppKit
import Combine
import SwiftUI

@main
@MainActor
struct MapperApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = MapperAppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
private final class MapperAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let appName = "触控板映射"
    private var store: MapperStore!
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var statusSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = MapperStore()
        installApplicationMenu()
        installStatusItem()
        showSettingsWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.shutdown()
    }

    private func installApplicationMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: Self.appName)
        addItem(to: appMenu, title: "设置…", action: #selector(showSettings), key: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏\(Self.appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        addItem(to: appMenu, title: "退出\(Self.appName)", action: #selector(quit), key: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "trackpad", accessibilityDescription: Self.appName)
        item.button?.toolTip = Self.appName

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        statusSubscription = store.$status.sink { [weak self] status in
            self?.statusItem?.button?.toolTip = "\(Self.appName) · \(status)"
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = NSMenuItem(title: store.status, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        addItem(to: menu, title: store.enabled ? "暂停映射" : "开启映射", action: #selector(toggleMapping))
        addItem(to: menu, title: "打开设置…", action: #selector(showSettings), key: ",")
        menu.addItem(.separator())
        addItem(to: menu, title: "退出触控板映射", action: #selector(quit), key: "q")
    }

    private func addItem(to menu: NSMenu, title: String, action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    @objc private func showSettings() {
        NSApp.activate()
        showSettingsWindow()
    }

    private func showSettingsWindow() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = Self.appName
            window.contentMinSize = NSSize(width: 750, height: 525)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("MapperSettings")
            window.contentViewController = NSHostingController(rootView: MapperView(store: store))
            window.center()
            settingsWindow = window
        }

        if settingsWindow?.isMiniaturized == true {
            settingsWindow?.deminiaturize(nil)
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleMapping() {
        store.enabled.toggle()
        if store.needsPermission || store.profiles.isEmpty {
            showSettings()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
