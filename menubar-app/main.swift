import AppKit
import Foundation

struct Session: Codable {
    let session_id: String
    let project: String
    let state: String
    let ts: Double
    let tool: String?
}

let statusDir = (NSHomeDirectory() as NSString).appendingPathComponent(".devin-status")
let staleAfter: TimeInterval = 600

func colorFor(_ state: String, stale: Bool) -> NSColor {
    if stale { return .systemRed }
    switch state {
    case "working":    return .systemGreen
    case "waiting":    return .systemYellow
    case "permission": return .systemOrange
    case "question":   return .systemBlue
    default:           return .gray
    }
}

func loadSessions() -> [Session] {
    guard let files = try? FileManager.default.contentsOfDirectory(atPath: statusDir) else { return [] }
    var out: [Session] = []
    for f in files where f.hasSuffix(".json") {
        let p = (statusDir as NSString).appendingPathComponent(f)
        guard let d = FileManager.default.contents(atPath: p),
              let s = try? JSONDecoder().decode(Session.self, from: d) else { continue }
        out.append(s)
    }
    return out.sorted { $0.project < $1.project }
}

func fmtAge(_ ts: Double) -> String {
    let s = Int(Date().timeIntervalSince1970 - ts)
    if s < 60 { return "\(s)s" }
    if s < 3600 { return "\(s / 60)m" }
    return "\(s / 3600)h"
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var timer: Timer?
    var lastSignature = ""

    func applicationDidFinishLaunching(_ n: Notification) {
        refresh(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refresh(force: false)
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func refresh(force: Bool) {
        let sessions = loadSessions()
        let sig = sessions.map { "\($0.session_id)|\($0.state)|\(Int($0.ts / 15))" }.joined(separator: ";")
        if !force && sig == lastSignature { return }
        lastSignature = sig

        let title = NSMutableAttributedString()
        title.append(NSAttributedString(string: "D \(sessions.count) ", attributes: [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        ]))
        if sessions.isEmpty {
            title.append(NSAttributedString(string: "◌", attributes: [.foregroundColor: NSColor.gray]))
        } else {
            for (i, s) in sessions.enumerated() {
                let stale = s.state == "working" && (Date().timeIntervalSince1970 - s.ts) > staleAfter
                title.append(NSAttributedString(string: i == 0 ? "●" : " ●", attributes: [
                    .foregroundColor: colorFor(s.state, stale: stale)
                ]))
            }
        }
        item.button?.attributedTitle = title
        item.button?.toolTip = "Devin sessions: \(sessions.count)"

        let menu = NSMenu()
        if sessions.isEmpty {
            let m = NSMenuItem(title: "No Devin sessions reporting", action: nil, keyEquivalent: "")
            m.isEnabled = false
            menu.addItem(m)
        } else {
            for s in sessions {
                let stale = s.state == "working" && (Date().timeIntervalSince1970 - s.ts) > staleAfter
                let a = NSMutableAttributedString()
                a.append(NSAttributedString(string: "● ", attributes: [.foregroundColor: colorFor(s.state, stale: stale)]))
                a.append(NSAttributedString(string: "\(s.project) — \(s.state)\(stale ? " [stale?]" : "") (\(fmtAge(s.ts)) ago)", attributes: [:]))
                let m = NSMenuItem()
                m.attributedTitle = a
                m.isEnabled = false
                menu.addItem(m)
            }
        }
        menu.addItem(.separator())
        let legend = NSMenuItem(title: "green=working yellow=waiting orange=permission blue=question", action: nil, keyEquivalent: "")
        legend.isEnabled = false
        menu.addItem(legend)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open status folder", action: #selector(openFolder), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit DevinStatus", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    @objc func openFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: statusDir))
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
