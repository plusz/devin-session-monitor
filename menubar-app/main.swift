import AppKit
import Foundation

struct Session: Codable {
    let session_id: String
    let project: String
    let state: String
    let ts: Double
    let tool: String?
    let pid: Int?
}

struct Group {
    let key: String
    var project: String
    var state: String
    var ts: Double
    var members: [Session]
}

let statusDir = (NSHomeDirectory() as NSString).appendingPathComponent(".devin-status")
let staleAfter: TimeInterval = 600

func stateRank(_ s: String) -> Int {
    switch s {
    case "permission": return 4
    case "question":   return 3
    case "working":    return 2
    case "waiting":    return 1
    default:           return 0
    }
}

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
    return out
}

// Group sessions by parent Devin process (one process = one window/instance).
// Group state = highest-priority member state; ts = most recent member event.
func loadGroups() -> [Group] {
    var map: [String: Group] = [:]
    for s in loadSessions() {
        let key = s.pid.map { "p\($0)" } ?? "s\(s.session_id)"
        var g = map[key] ?? Group(key: key, project: s.project, state: s.state, ts: s.ts, members: [])
        g.members.append(s)
        if s.ts > g.ts { g.ts = s.ts; g.project = s.project }
        if stateRank(s.state) > stateRank(g.state) { g.state = s.state }
        map[key] = g
    }
    return map.values.sorted { $0.project < $1.project }
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
        let groups = loadGroups()
        let sig = groups.map { g in
            "\(g.key)|\(g.state)|\(Int(g.ts / 15))|\(g.members.count)"
        }.joined(separator: ";")
        if !force && sig == lastSignature { return }
        lastSignature = sig

        let title = NSMutableAttributedString()
        title.append(NSAttributedString(string: "D \(groups.count) ", attributes: [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        ]))
        if groups.isEmpty {
            title.append(NSAttributedString(string: "◌", attributes: [.foregroundColor: NSColor.gray]))
        } else {
            for (i, g) in groups.enumerated() {
                let stale = g.state == "working" && (Date().timeIntervalSince1970 - g.ts) > staleAfter
                title.append(NSAttributedString(string: i == 0 ? "●" : " ●", attributes: [
                    .foregroundColor: colorFor(g.state, stale: stale)
                ]))
            }
        }
        item.button?.attributedTitle = title
        item.button?.toolTip = "Devin instances: \(groups.count)"

        let menu = NSMenu()
        if groups.isEmpty {
            let m = NSMenuItem(title: "No Devin sessions reporting", action: nil, keyEquivalent: "")
            m.isEnabled = false
            menu.addItem(m)
        } else {
            for g in groups {
                let stale = g.state == "working" && (Date().timeIntervalSince1970 - g.ts) > staleAfter
                let a = NSMutableAttributedString()
                a.append(NSAttributedString(string: "● ", attributes: [.foregroundColor: colorFor(g.state, stale: stale)]))
                let suffix = g.members.count > 1 ? " (\(g.members.count) sessions)" : ""
                a.append(NSAttributedString(string: "\(g.project) — \(g.state)\(stale ? " [stale?]" : "")\(suffix) · \(fmtAge(g.ts)) ago", attributes: [:]))
                let m = NSMenuItem()
                m.attributedTitle = a
                m.isEnabled = false
                menu.addItem(m)

                for s in g.members.sorted(by: { $0.ts > $1.ts }) where g.members.count > 1 {
                    let sub = NSMutableAttributedString()
                    sub.append(NSAttributedString(string: "    ● ", attributes: [.foregroundColor: colorFor(s.state, stale: false)]))
                    sub.append(NSAttributedString(string: "\(s.session_id) — \(s.state) (\(fmtAge(s.ts)))", attributes: [:]))
                    let sm = NSMenuItem()
                    sm.attributedTitle = sub
                    sm.isEnabled = false
                    menu.addItem(sm)
                }
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
