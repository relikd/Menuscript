#!/usr/bin/env swift
import AppKit
import Cocoa

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
		if let img = statusIcon() {
			self.statusItem.button?.image = img
		} else {
			self.statusItem.button?.title = "⌘" // cant load svg (<10.15)
		}
		self.statusItem.menu = NSMenu(title: resolvedStorageURL().path)
		self.statusItem.menu?.delegate = self
	}

	private func statusIcon() -> NSImage? {
		let img = NSImage(contentsOf: resFile("status", "svg"))
		img?.isTemplate = true
		img?.size = NSMakeSize(14, 14)
		return img
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
		for entry in listDir(menu.title) {
			if entry.action == .Ignore {
				continue
			}
			let itm = menu.addItem(withTitle: entry.title, action: nil, keyEquivalent: "")
			itm.representedObject = entry
			itm.image = entry.icon()

			if entry.isDir || entry.action == .Dynamic {
				itm.submenu = NSMenu(title: entry.url.path)
				itm.submenu?.delegate = self
			} else if entry.action != .Inactive {
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
		let entry = sender.representedObject as! Entry
		let cmd = Exec(file: entry.url, env: ["ACTION": "click", "ITEM": entry.title])
		if entry.action == .Text {
			cmd.editor()
		} else {
			cmd.run(verbose: entry.action == .Verbose)
		}
	}

	// MARK: - Helper

	private func resFile(_ name: String, _ ext: String?) -> URL {
		// if run via .app bundle
		return Bundle.main.url(forResource: name, withExtension: ext)
			// if calling swift directly
			?? URL(fileURLWithPath: #file + "/../../res/" + name + (ext == nil ? "" : ("." + ext!)))
	}

	// MARK: - Manage storage path

	private func resolvedStorageURL() -> URL {
		userStorageURL() ?? resFile("examples", nil)
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
				self.statusItem.menu?.title = panel.url!.path
				// update user defaults
				UserDefaults.standard.set(panel.url, forKey: "storage")
				// update settings window
				let pth = self.settingsWindow?.contentView!.viewWithTag(201) as? NSPathControl
				pth?.url = panel.url
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
		pth.tag = 201
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


// MARK: - Command executor

struct Exec {
	let file: URL
	var env: [String: String]? = nil

	private func prepare() -> Process {
		let proc = Process()
		proc.environment = self.env
		proc.currentDirectoryURL = self.file.deletingLastPathComponent()
		proc.executableURL = self.file
		return proc
	}

	private func toPipe() -> Pipe {
		let proc = prepare()
		let io = Pipe()
		proc.standardOutput = io
		proc.standardError = io
		proc.launch()
		return io
	}

	/// run command (ignoring output)
	func run(verbose: Bool = false) {
		let proc = prepare()
		if verbose {
			proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
			proc.arguments = [self.file.path]
		}
		proc.launch()
	}

	/// open result in default text editor
	func editor() {
		let p2 = Process()
		p2.launchPath = "/usr/bin/open"
		p2.arguments = ["-f"]
		p2.standardInput = toPipe()
		p2.launch()
	}

	/// run command and return output
	func readData() -> Data {
		return toPipe().fileHandleForReading.readDataToEndOfFile()
	}

	/// run command and return output
	func readString() -> String {
		return String(data: readData(), encoding: .utf8) ?? ""
	}
}


// MARK: - static methods

func listDir(_ path: String) -> [Entry] {
	let target = URL(fileURLWithPath: path)
	var rv: [Entry] = []
	// dynamic menu
	if !target.hasDirectoryPath {
		Exec(file: target, env: ["ACTION": "list"]).readString().enumerateLines { line, stop in
			rv.append(Entry(target, title: line))
		}
		return rv
	}
	// else: static menu
	for url in (try? FileManager.default.contentsOfDirectory(at: target, includingPropertiesForKeys: [.isDirectoryKey, .isExecutableKey])) ?? [] {
		if url.hasDirectoryPath || FileManager.default.isExecutableFile(atPath: url.path),
			!url.lastPathComponent.hasPrefix("_")
		{
			rv.append(Entry(url))
		}
	}
	return rv.sorted()
}


// MARK: - A menu item

enum ActionFlag {
	case Default
	case Text
	case Verbose
	case Inactive
	case Ignore
	case Dynamic

	static func from(_ filename: inout String) -> Self {
		for (key, flag) in [
			"[txt]": ActionFlag.Text,
			"[verbose]": .Verbose,
			"[inactive]": .Inactive,
			"[ignore]": .Ignore,
			"[dyn]": .Dynamic,
		] {
			if filename.contains(key) {
				filename = filename
					.replacingOccurrences(of: key, with: "")
					.replacingOccurrences(of: "  ", with: " ")
				return flag
			}
		}
		return Default
	}
}

struct Entry {
	let order: Int
	let url: URL
	let title: String
	let action: ActionFlag
	let hasDynParent: Bool

	var isDir: Bool { url.hasDirectoryPath }

	init(_ url: URL, title: String? = nil) {
		self.hasDynParent = title != nil
		self.url = url
		// TODO: remove file extension?
		var fname = title ?? url.lastPathComponent
		var customOrder = 100
		if !hasDynParent {
			var idx = fname.firstIndex { !$0.isWholeNumber } ?? fname.startIndex
			// sort order
			if let order = Int(fname[..<idx]) {
				customOrder = order
				idx = fname[idx..<fname.endIndex].firstIndex { !$0.isWhitespace } ?? idx
				idx = fname[idx..<fname.endIndex].firstIndex { !$0.isPunctuation } ?? idx
				fname = String(fname[idx..<fname.endIndex])
			}
		}
		self.order = customOrder
		self.action = ActionFlag.from(&fname)
		self.title = fname.trimmingCharacters(in: .whitespaces)
	}

	func icon() -> NSImage? {
		var img: NSImage? = nil
		if !hasDynParent {
			let basePath = self.isDir ? self.url.appendingPathComponent("icon") : self.url
			for ext in ["svg", "png", "jpg", "jpeg", "gif", "ico", "icns"] {
				let iconPath = basePath.appendingPathExtension(ext)
				if FileManager.default.fileExists(atPath: iconPath.path) {
					img = NSImage(contentsOf: iconPath)
					break
				}
			}
			if img == nil, self.isDir {
				img = NSImage(named: NSImage.folderName)
			}
		}
		if img == nil, action == .Dynamic || hasDynParent {
			let cmd = Exec(file: self.url, env: ["ACTION": "icon", "ITEM": hasDynParent ? self.title : ""])
			img = NSImage(data: cmd.readData())
		}
		img?.size = NSMakeSize(16, 16)
		return img
	}
}

extension Entry: Comparable {
	static func < (lhs: Entry, rhs: Entry) -> Bool {
		return (lhs.order, lhs.title) < (rhs.order, rhs.title)
	}
}

// MARK: - Main Entry

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
// _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
