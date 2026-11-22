// THE SHARED MIDI MODULES, the part that needs nothing but Foundation (so a workflow tests it without the apps):
// one on / off state for both apps that show MIDI to MK Control and MIDI to Key Stroke, and the owner lock that lets exactly
// one process run the engines. Marko, 22.11.2026: "All the MIDI modules should only be actually in both places. We are
// sharing the modules ... they also share the settings. It's the same thing, just in different views."
import Foundation
import Darwin

enum MidiShared {
    static let ids = ["mackie", "midikeys"]
    static let stateURL = URL(fileURLWithPath: NSHomeDirectory() + "/.config/mantra-midi-modules.json")
    static let lockPath = NSHomeDirectory() + "/.config/mantra-midi-owner.lock"
    /// the two apps' own settings files before the sharing: their "modules" keys are read once, to migrate (one version)
    static let legacyPaths = [NSHomeDirectory() + "/.config/live-actions.json", NSHomeDirectory() + "/.config/midi-tools.json"]

    /// Shared state from the old per-app files: ON when any of them says ON, OFF when they all say OFF, ON when none says anything.
    /// (Today: ON in Ableton Live Assistant, OFF in MIDI Tools: ON.)
    static func migrate(legacy: [[String: Any]]) -> [String: Bool] {
        var out: [String: Bool] = [:]
        for id in ids {
            let says = legacy.compactMap { ($0["modules"] as? [String: Any])?[id] as? Bool }
            out[id] = says.isEmpty ? true : says.contains(true)
        }
        return out
    }
    /// {"schema":1,"modules":{"mackie":{"on":true},"midikeys":{"on":true}}}
    static func read(at url: URL = stateURL) -> [String: Bool]? {
        guard let d = try? Data(contentsOf: url), let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              (j["schema"] as? Int) == 1, let m = j["modules"] as? [String: Any] else { return nil }
        var out: [String: Bool] = [:]
        for id in ids { out[id] = ((m[id] as? [String: Any])?["on"] as? Bool) ?? true }
        return out
    }
    /// Atomic: written to a temporary file and renamed over the real one.
    @discardableResult static func write(_ on: [String: Bool], at url: URL = stateURL) -> Bool {
        var m: [String: Any] = [:]
        for id in ids { m[id] = ["on": on[id] ?? true] }
        guard let d = try? JSONSerialization.data(withJSONObject: ["schema": 1, "modules": m] as [String: Any], options: [.prettyPrinted, .sortedKeys]) else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? d.write(to: url, options: .atomic)) != nil
    }
    /// The shared state; when the file does not exist yet it is made from the old files and written.
    static func load(at url: URL = stateURL, legacyPaths: [String] = legacyPaths) -> [String: Bool] {
        if let s = read(at: url) { return s }
        let legacy = legacyPaths.compactMap { p in (try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: p)))) as? [String: Any] }
        let s = migrate(legacy: legacy)
        write(s, at: url)
        return s
    }

    // the rules, as pure functions
    /// the engine of a module runs only in the process that owns the lock, and only while the module is ON
    static func engineShouldRun(moduleOn: Bool, owner: Bool) -> Bool { moduleOn && owner }
    /// a process asks for the lock while any module is ON (and lets it go when none is)
    static func wantsLock(_ on: [String: Bool]) -> Bool { on.values.contains(true) }
    /// the line a view shows when the other app is the one doing the work
    static func viewLine(owner: Bool, anyOn: Bool, holderApp: String?, myApp: String) -> String? {
        guard !owner, anyOn, let h = holderApp, h != myApp else { return nil }
        return "runs in " + h
    }
}

/// The owner lock: flock on a file held open by the owner, so the kernel lets it go when the owner dies (a stale file of a
/// dead process is simply taken). The file also says who holds it: {"pid":..,"app":"..","since":..}.
final class OwnerLock {
    struct Info: Equatable { let pid: Int32; let app: String; let since: Double }
    let path: String
    private var fd: Int32 = -1
    init(path: String = MidiShared.lockPath) { self.path = path }
    var isOwner: Bool { fd >= 0 }

    func tryAcquire(app: String) -> Bool {
        if fd >= 0 { return true }
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let f = open(path, O_RDWR | O_CREAT, 0o644)
        guard f >= 0 else { return false }
        if flock(f, LOCK_EX | LOCK_NB) != 0 { close(f); return false }
        fd = f
        let json = "{\"pid\":\(getpid()),\"app\":\"\(app.replacingOccurrences(of: "\"", with: "'"))\",\"since\":\(Date().timeIntervalSince1970)}"
        _ = ftruncate(fd, 0)
        _ = json.withCString { pwrite(fd, $0, strlen($0), 0) }
        return true
    }
    func release() {
        guard fd >= 0 else { return }
        _ = ftruncate(fd, 0)
        flock(fd, LOCK_UN); close(fd); fd = -1
    }
    /// Who holds the lock now (nil when nobody does: a file left by a dead process does not count).
    static func holder(path: String = MidiShared.lockPath) -> Info? {
        let f = open(path, O_RDWR)
        guard f >= 0 else { return nil }
        defer { close(f) }
        if flock(f, LOCK_EX | LOCK_NB) == 0 { flock(f, LOCK_UN); return nil }      // nobody holds it
        var buf = [UInt8](repeating: 0, count: 512)
        let n = pread(f, &buf, 511, 0)
        guard n > 0, let j = (try? JSONSerialization.jsonObject(with: Data(buf[0..<n]))) as? [String: Any],
              let pid = j["pid"] as? Int, let app = j["app"] as? String else { return Info(pid: 0, app: "another app", since: 0) }
        return Info(pid: Int32(pid), app: app, since: (j["since"] as? Double) ?? 0)
    }
}
