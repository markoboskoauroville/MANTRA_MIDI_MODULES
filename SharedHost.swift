// THE SHARED MIDI MODULES, the host: both apps (Ableton Live Assistant, MIDI Tools) show MIDI to MK Control and MIDI to Key
// Stroke; one process at a time runs their engines (the owner), the other is a view of the same state. Once a second:
// the shared on / off state is read (a switch flipped in the other window shows here), the owner lock is asked for while any
// module is ON, each engine is set to run only in the owner, and both settings files are re-read when they changed.
import Foundation
import AppKit

final class MidiHost {
    static let shared = MidiHost()
    struct Mod { let id: String; let setOn: (Bool) -> Void; let reload: () -> Void }
    private(set) var on: [String: Bool] = [:]
    private(set) var line: String?                         // "runs in <the other app>", or nil
    var isOwner: Bool { lock.isOwner }
    var onChange: (() -> Void)?
    private var mods: [Mod] = []
    private var applied: [String: Bool] = [:]
    private let lock = OwnerLock()
    private var app = "", log: (String) -> Void = { _ in }
    private var timer: Timer?
    private var stamps: [String: Date] = [:]

    func start(app: String, mods: [Mod], log: @escaping (String) -> Void) {
        self.app = app; self.mods = mods; self.log = log
        on = MidiShared.load()
        stamps = stampsNow()
        poll()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
    }
    /// a switch pressed in this app's window
    func setOn(_ id: String, _ v: Bool) {
        var s = MidiShared.read() ?? on
        s[id] = v
        MidiShared.write(s)
        poll()
    }
    func shutdown() {
        timer?.invalidate(); timer = nil
        for m in mods where applied[m.id] == true { m.setOn(false); applied[m.id] = false }
        if lock.isOwner { lock.release(); log("midi owner released (quit)") }
    }

    private func settingsFiles() -> [String] { [NSHomeDirectory() + "/.config/midi-to-mk.json", NSHomeDirectory() + "/.config/midi-to-keystroke.json"] }
    private func stampsNow() -> [String: Date] {
        var d: [String: Date] = [:]
        for p in settingsFiles() { d[p] = ((try? FileManager.default.attributesOfItem(atPath: p))?[.modificationDate] as? Date) ?? .distantPast }
        return d
    }

    func poll() {
        var changed = false
        if let s = MidiShared.read(), s != on { on = s; changed = true }
        let any = MidiShared.wantsLock(on)
        if any && !lock.isOwner {
            if lock.tryAcquire(app: app) { log("midi owner acquired (\(app))"); changed = true }
        } else if !any && lock.isOwner {
            lock.release(); log("midi owner released (all modules off)"); changed = true
        }
        for m in mods {
            let run = MidiShared.engineShouldRun(moduleOn: on[m.id] ?? true, owner: lock.isOwner)
            if applied[m.id] != run { applied[m.id] = run; m.setOn(run); log("\(m.id) engine \(run ? "started" : "stopped") here"); changed = true }
        }
        let now = stampsNow()
        if now != stamps { stamps = now; for m in mods { m.reload() }; changed = true }     // the other app changed a settings file
        let holder = lock.isOwner ? nil : OwnerLock.holder()
        let l = MidiShared.viewLine(owner: lock.isOwner, anyOn: any, holderApp: holder?.app, myApp: app)
        if l != line { line = l; changed = true; if let l = l { log("midi: " + l) } }
        if changed { onChange?() }
    }
}
