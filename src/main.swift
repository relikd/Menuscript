#!/usr/bin/env swift
import AppKit
import Cocoa
import SwiftUI

class FlippedView: NSView {
	override var isFlipped: Bool { true }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
	private var statusItem: NSStatusItem!
	private weak var settingsWindow: NSWindow? = nil

	func applicationDidFinishLaunching(_ aNotification: Notification) {
		// UserDefaults.standard.register(defaults: ["storage": "~/"])
		initStatusIcon()
		if userStorageURL() == nil {
			showSettings()
		}
	}

	private func initStatusIcon() {
		self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		self.statusItem.button?.title = "⌘"
		// self.statusItem.button?.image = NSImage.statusIcon
		self.statusItem.menu = NSMenu(title: resolvedStorageURL().path)
		self.statusItem.menu?.delegate = self
	}

	func menuDidClose(_ menu: NSMenu) {
		if menu == self.statusItem.menu {
			self.statusItem.menu = NSMenu(title: menu.title)
			self.statusItem.menu?.delegate = self
		}
	}

	/**
	 Delegate method not used. Here to prevent weird `NSMenu` behavior.
	 Otherwise, Cmd-Q (Quit) will traverse all submenus (incl. creating unopened).
	 */
	func menuHasKeyEquivalent(_ menu: NSMenu, for event: NSEvent, target: AutoreleasingUnsafeMutablePointer<AnyObject?>, action: UnsafeMutablePointer<Selector?>) -> Bool {
		return false
	}

	func menuNeedsUpdate(_ menu: NSMenu) {
		for entry in Entry.listDir(menu.title) {
			let itm = menu.addItem(withTitle: entry.title, action: nil, keyEquivalent: "")
			itm.representedObject = entry
			itm.image = entry.icon()

			if entry.isDir {
				itm.submenu = NSMenu(title: entry.url.path)
				itm.submenu?.delegate = self
			} else {
				itm.action = #selector(menuItemCallback)
			}
		}

		if menu == self.statusItem.menu {
			menu.addItem(NSMenuItem.separator())
			menu.addItem(withTitle: "Preferences", action: #selector(showSettings), keyEquivalent: ",")
			menu.addItem(withTitle: "Quit", action: #selector(NSApp.terminate), keyEquivalent: "q")
		}
	}

	@objc private func menuItemCallback(sender: NSMenuItem) {
		(sender.representedObject as! Entry).run()
	}

	// MARK: - Manage storage path

	private func resolvedStorageURL() -> URL {
		userStorageURL()
			// if run via .app bundle
			?? Bundle.main.url(forResource: "examples", withExtension: nil)
			// if calling swift directly
			?? URL(string: "file://" + FileManager.default.currentDirectoryPath + "/" + #file)!
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appendingPathComponent("examples")
	}

	private func userStorageURL() -> URL? {
		UserDefaults.standard.url(forKey: "storage")
	}

	@objc func selectStoragePath() {
		let panel = NSOpenPanel()
		panel.canChooseDirectories = true
		panel.canCreateDirectories = true
		panel.canChooseFiles = false
		panel.allowsMultipleSelection = false
		panel.begin {
			if $0 == .OK {
				UserDefaults.standard.set(panel.url, forKey: "storage")
				self.statusItem.menu?.title = panel.url!.path
			}
		}
	}

	@objc func openStoragePath() {
		NSWorkspace.shared.open(resolvedStorageURL())
	}

	// MARK: - Settings View

	@objc func showSettings() {
		if self.settingsWindow == nil {
			let win = NSWindow(
				contentRect: NSMakeRect(0, 0, 400, 115),
				styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
				defer: true)
			self.settingsWindow = win
			win.title = "Preferences"
			win.isReleasedWhenClosed = false  // because .buffered
			win.contentView = initSettingsView()
			win.contentMinSize = NSMakeSize(300, win.contentView!.frame.size.height)
			win.center()
			win.makeKeyAndOrderFront(nil)
		}
		self.settingsWindow!.orderFrontRegardless()
	}

	private func initSettingsView() -> NSView {
		let pad = 20.0
		let view = FlippedView(frame: NSMakeRect(0, 0, 400, 120))

		let lbl = NSTextField(frame: NSMakeRect(pad, pad, 400 - 2 * pad, 22))
		lbl.isEditable = false
		lbl.isBezeled = false
		lbl.drawsBackground = false
		lbl.stringValue = "Scripts storage path:"
		view.addSubview(lbl)

		let pth = NSPathControl(frame: NSMakeRect(pad, NSMaxY(lbl.frame), 400 - 2 * pad, 22))
		pth.autoresizingMask = [.maxYMargin, .width]
		pth.isEditable = true
		pth.allowedTypes = ["public.folder"]
		pth.pathStyle = .standard
		pth.url = resolvedStorageURL()
		view.addSubview(pth)

		let chg = NSButton(title: "Change", target: self, action: #selector(selectStoragePath))
		chg.frame = NSMakeRect(pad, NSMaxY(pth.frame), 90, 40)
		chg.autoresizingMask = [.maxXMargin, .maxYMargin]
		view.addSubview(chg)

		let opn = NSButton(title: "Open", target: self, action: #selector(openStoragePath))
		opn.frame = NSMakeRect(NSMaxX(chg.frame), NSMaxY(pth.frame), 90, 40)
		// opn.autoresizingMask = [.maxXMargin, .maxYMargin]
		view.addSubview(opn)
		view.frame.size.height = NSMaxY(pth.frame) + 40 + pad
		return view
	}
}

// MARK: - A menu item

struct Entry {
	enum Flags {
		case Verbose
		case Text
	}

	let order: Int
	let title: String
	let flags: [Flags]
	let url: URL

	var isDir: Bool { url.hasDirectoryPath }

	init(_ url: URL) {
		self.url = url
		// TODO: remove file extension?
		var fname = url.lastPathComponent
		var idx = fname.firstIndex { !$0.isWholeNumber } ?? fname.startIndex
		// sort order
		if let order = Int(fname[..<idx]) {
			self.order = order
			idx = fname[idx..<fname.endIndex].firstIndex { !$0.isWhitespace } ?? idx
			idx = fname[idx..<fname.endIndex].firstIndex { !$0.isPunctuation } ?? idx
			fname = String(fname[idx..<fname.endIndex])
		} else {
			self.order = 100
		}
		// flags
		var flags: [Flags] = []
		for (key, flag) in ["verbose": Flags.Verbose, "txt": .Text] {
			if fname.contains("[" + key + "]") {
				fname = fname.replacingOccurrences(of: "[" + key + "]", with: "")
					.replacingOccurrences(of: "  ", with: " ")
				flags.append(flag)
			}
		}
		self.flags = flags
		self.title = fname.trimmingCharacters(in: .whitespaces)
	}

	static func listDir(_ path: String) -> [Entry] {
		var rv: [Entry] = []
		for url
			in (try? FileManager.default.contentsOfDirectory(
				at: URL(string: path)!,
				includingPropertiesForKeys: [.isDirectoryKey, .isExecutableKey])) ?? []
		{
			if url.hasDirectoryPath || FileManager.default.isExecutableFile(atPath: url.path) {
				rv.append(Entry(url))
			}
		}
		return rv.sorted()
	}

	func icon() -> NSImage? {
		guard isDir else {
			return nil
		}
		var img: NSImage? = nil
		for ext in ["svg", "png", "jpg", "jpeg", "gif", "ico"] {
			let iconPath = self.url.appendingPathComponent("icon." + ext)
			if FileManager.default.fileExists(atPath: iconPath.path) {
				img = NSImage(contentsOf: iconPath)
				break
			}
		}
		if img == nil {
			img = NSImage(named: NSImage.folderName)
		}
		img?.size = NSMakeSize(16, 16)
		return img
	}

	func run() {
		let proc = Process()
		proc.currentDirectoryURL = self.url.deletingLastPathComponent()
		// proc.environment = ["HOME": "$HOME"]
		if self.flags.contains(.Verbose) {
			proc.launchPath = "/usr/bin/open"
			proc.arguments = [self.url.path]
		} else {
			proc.executableURL = self.url
		}

		if self.flags.contains(.Text) {
			// open result in default text editor
			let io = Pipe()
			proc.standardOutput = io
			proc.standardError = io

			proc.launch()

			let p2 = Process()
			p2.launchPath = "/usr/bin/open"
			p2.arguments = ["-f"]
			p2.standardInput = io
			p2.launch()

			// let data = io.fileHandleForReading.readDataToEndOfFile()
			// let output = String(data: data, encoding: .utf8) ?? ""
		} else {
			proc.launch()
		}
	}
}

extension Entry : Comparable {
	static func < (lhs: Entry, rhs: Entry) -> Bool {
		return (lhs.order, lhs.title) < (rhs.order, rhs.title)
	}
}

// MARK: - Main Entry

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
// _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
