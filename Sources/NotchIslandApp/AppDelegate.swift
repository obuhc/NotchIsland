import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let store = UsageStore()
    private let settings = AppSettings()
    private lazy var panelController = NotchPanelController(
        store: store,
        actions: IslandActions(
            refresh: { [weak self] in self?.store.refresh(force: true) },
            openSettings: { [weak self] in self?.openSettings() },
            quit: { [weak self] in self?.quit() }
        )
    )
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        settings.onIntervalChange = { [weak self] interval in
            self?.store.restart(interval: interval)
        }
        store.claudeOfficialEnabled = settings.claudeOfficialEnabled
        settings.onClaudeOfficialChange = { [weak self] enabled in
            self?.store.claudeOfficialEnabled = enabled
            self?.store.refresh(force: true)
        }
        store.start(interval: settings.refreshInterval)
        panelController.show()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screensChanged() {
        panelController.reposition()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "gauge.with.dots.needle.67percent",
            accessibilityDescription: "NotchIsland"
        )

        let menu = NSMenu()
        let header = NSMenuItem(title: "NotchIsland", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "立即刷新", action: #selector(refreshNow), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func refreshNow() { store.refresh() }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 260),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "NotchIsland 设置"
            window.contentView = NSHostingView(rootView: SettingsView(settings: settings))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
