import SwiftUI
import AppKit

@main
struct ObservatoryApp: App {
	@StateObject private var appState = AppState()
	@State private var isAuthenticated = false

	var body: some Scene {
		WindowGroup {
			if isAuthenticated {
				ContentView()
					.environmentObject(appState)
					.background(WindowAccessor())
					.onAppear {
						// Start auto-refresh timer (but only fetches connected controllers)
						DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
							appState.startAutoRefresh()
							// Don't auto-fetch on startup - let user manually connect
							// appState.fetchStatus()
							appState.fetchWeather()
						}
					}
			} else {
				LoginView(isAuthenticated: $isAuthenticated)
					.environmentObject(appState)
			}
		}
		.defaultSize(width: 1200, height: 800)
		.commands {
			CommandGroup(replacing: .windowSize) {
				Button("Zoom") {
					toggleFullScreen()
				}
				.keyboardShortcut("f", modifiers: [.command, .control])
			}
		}
	}
	
	func toggleFullScreen() {
		if let window = NSApplication.shared.windows.first {
			window.toggleFullScreen(nil)
		}
	}
}

class WindowDelegate: NSObject, NSWindowDelegate {
	func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
		// 如果不是全屏，强制返回固定尺寸
		if !sender.styleMask.contains(.fullScreen) {
			return NSSize(width: 1200, height: 800)
		}
		return frameSize
	}
	
	func windowDidResize(_ notification: Notification) {
		guard let window = notification.object as? NSWindow else { return }
		// 如果不是全屏，强制恢复固定尺寸
		if !window.styleMask.contains(.fullScreen) {
			let fixedSize = NSSize(width: 1200, height: 800)
			if window.frame.size != fixedSize {
				window.setContentSize(fixedSize)
			}
		}
	}
}

struct WindowAccessor: NSViewRepresentable {
	private let delegate = WindowDelegate()
	
	func makeNSView(context: Context) -> NSView {
		let view = NSView()
		DispatchQueue.main.async {
			if let window = view.window {
				window.minSize = NSSize(width: 1200, height: 800)
				window.maxSize = NSSize(width: 1200, height: 800)
				window.collectionBehavior = [.fullScreenPrimary]
				window.delegate = delegate
				// 设置固定尺寸
				window.setContentSize(NSSize(width: 1200, height: 800))
			}
		}
		return view
	}
	
	func updateNSView(_ nsView: NSView, context: Context) {
		DispatchQueue.main.async {
			if let window = nsView.window {
				window.minSize = NSSize(width: 1200, height: 800)
				window.maxSize = NSSize(width: 1200, height: 800)
				window.delegate = delegate
				// 如果不是全屏，强制恢复固定尺寸
				if !window.styleMask.contains(.fullScreen) {
					let fixedSize = NSSize(width: 1200, height: 800)
					if window.frame.size != fixedSize {
						window.setContentSize(fixedSize)
					}
				}
			}
		}
	}
}

