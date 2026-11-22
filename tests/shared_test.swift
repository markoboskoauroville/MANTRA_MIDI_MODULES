// Tests of SharedPure.swift without the apps (a workflow copies this to main.swift beside SharedPure.swift):
//   swiftc -o /tmp/shared_test SharedPure.swift main.swift && /tmp/shared_test
import Foundation

var pass = 0, fail = 0
func ok(_ c: Bool, _ what: String) { if c { pass += 1 } else { fail += 1; print("FAIL  \(what)") } }
let tmp = NSTemporaryDirectory() + "midishared-\(getpid())"
try? FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(atPath: tmp) }
let state = URL(fileURLWithPath: tmp + "/mantra-midi-modules.json")

// migration: today ON in Live Assistant and OFF in MIDI Tools -> ON
let la: [String: Any] = ["modules": ["a1": true, "mackie": true, "midikeys": true]]
let mt: [String: Any] = ["modules": ["mackie": false, "midikeys": false]]
ok(MidiShared.migrate(legacy: [la, mt]) == ["mackie": true, "midikeys": true], "migrate: ON in one app, OFF in the other -> ON")
ok(MidiShared.migrate(legacy: [mt]) == ["mackie": false, "midikeys": false], "migrate: OFF everywhere -> OFF")
ok(MidiShared.migrate(legacy: [[:], [:]]) == ["mackie": true, "midikeys": true], "migrate: nothing said -> ON (the default)")
ok(MidiShared.migrate(legacy: [["modules": ["mackie": false]], ["modules": ["midikeys": true]]]) == ["mackie": false, "midikeys": true], "migrate: per module")

// round trip, atomic
ok(MidiShared.read(at: state) == nil, "no file yet: nil")
ok(MidiShared.write(["mackie": true, "midikeys": false], at: state), "write")
ok(MidiShared.read(at: state) == ["mackie": true, "midikeys": false], "round trip")
ok((try? FileManager.default.contentsOfDirectory(atPath: tmp))?.sorted() == ["mantra-midi-modules.json"], "atomic: no temporary file is left beside it")
let raw = (try? JSONSerialization.jsonObject(with: Data(contentsOf: state))) as? [String: Any]
ok((raw?["schema"] as? Int) == 1 && ((raw?["modules"] as? [String: Any])?["mackie"] as? [String: Any])?["on"] as? Bool == true, "schema 1, modules.<id>.on")
// load: the file is made from the old files when missing
try? FileManager.default.removeItem(at: state)
let laPath = tmp + "/live-actions.json", mtPath = tmp + "/midi-tools.json"
try? JSONSerialization.data(withJSONObject: la).write(to: URL(fileURLWithPath: laPath))
try? JSONSerialization.data(withJSONObject: mt).write(to: URL(fileURLWithPath: mtPath))
ok(MidiShared.load(at: state, legacyPaths: [laPath, mtPath]) == ["mackie": true, "midikeys": true], "load: migrates the old files (ON)")
ok(MidiShared.read(at: state) == ["mackie": true, "midikeys": true], "load: the shared file was written")
MidiShared.write(["mackie": false, "midikeys": true], at: state)
ok(MidiShared.load(at: state, legacyPaths: [laPath, mtPath]) == ["mackie": false, "midikeys": true], "load: the shared file wins once it exists (the old keys are not read again)")

// the owner lock
let lp = tmp + "/owner.lock"
let a = OwnerLock(path: lp), b = OwnerLock(path: lp), c = OwnerLock(path: lp)
ok(OwnerLock.holder(path: lp) == nil, "no lock file: nobody holds it")
ok(a.tryAcquire(app: "Ableton Live Assistant (Mantra)"), "A acquires")
ok(!b.tryAcquire(app: "MIDI Tools (Mantra)"), "B cannot while A holds it: one owner")
ok(a.isOwner && !b.isOwner, "A owner, B not")
ok(OwnerLock.holder(path: lp)?.app == "Ableton Live Assistant (Mantra)", "the holder is named")
a.release()
ok(OwnerLock.holder(path: lp) == nil, "released: nobody holds it")
ok(b.tryAcquire(app: "MIDI Tools (Mantra)"), "A quit: B takes over")
ok(OwnerLock.holder(path: lp)?.app == "MIDI Tools (Mantra)", "B is the holder")
b.release()
// a stale file of a dead process
try? "{\"pid\":999999,\"app\":\"Dead (Mantra)\",\"since\":1}".write(toFile: lp, atomically: true, encoding: .utf8)
ok(OwnerLock.holder(path: lp) == nil, "a stale file with no lock held: nobody holds it")
ok(c.tryAcquire(app: "C"), "a stale lock of a dead pid is taken")
ok(OwnerLock.holder(path: lp)?.app == "C", "and rewritten with its own name")
c.release()

// the view line
let LA = "Ableton Live Assistant (Mantra)", MT = "MIDI Tools (Mantra)"
ok(MidiShared.viewLine(owner: false, anyOn: true, holderApp: MT, myApp: LA) == "runs in MIDI Tools (Mantra)", "view line names the other app")
ok(MidiShared.viewLine(owner: false, anyOn: true, holderApp: LA, myApp: MT) == "runs in Ableton Live Assistant (Mantra)", "view line, the other way")
ok(MidiShared.viewLine(owner: true, anyOn: true, holderApp: nil, myApp: LA) == nil, "the owner shows no line")
ok(MidiShared.viewLine(owner: false, anyOn: false, holderApp: MT, myApp: LA) == nil, "nothing ON: no line")
ok(MidiShared.viewLine(owner: false, anyOn: true, holderApp: nil, myApp: LA) == nil, "nobody holds it (only one app): no line")

// one knob, one action, with both apps running (a model: each app's engine acts only when the rule lets it)
struct App { let name: String; let lock: OwnerLock; var on: [String: Bool]
    func acts(_ id: String) -> Bool { MidiShared.engineShouldRun(moduleOn: on[id] ?? true, owner: lock.isOwner) } }
func poll(_ x: inout App) { if MidiShared.wantsLock(x.on) { _ = x.lock.tryAcquire(app: x.name) } else { x.lock.release() } }
func actions(_ apps: [App], _ id: String) -> Int { apps.filter { $0.acts(id) }.count }
do {
    let p = tmp + "/knob.lock"
    var x = App(name: LA, lock: OwnerLock(path: p), on: ["mackie": true, "midikeys": true])
    var y = App(name: MT, lock: OwnerLock(path: p), on: ["mackie": true, "midikeys": true])
    poll(&x); poll(&y)
    ok(actions([x, y], "mackie") == 1 && actions([x, y], "midikeys") == 1, "both apps running, both modules ON: one knob event, exactly one action")
    ok(x.lock.isOwner && !y.lock.isOwner, "the first one is the owner")
    x.lock.release(); poll(&y)
    ok(actions([y], "mackie") == 1 && actions([y], "midikeys") == 1, "the owner quit: the other app takes over, still exactly one action, never zero")
    var z = App(name: LA, lock: OwnerLock(path: p), on: ["mackie": true, "midikeys": true]); poll(&z)
    ok(actions([y, z], "mackie") == 1, "a third start while y runs: still one action")
    y.on = ["mackie": false, "midikeys": false]; z.on = y.on; poll(&y); poll(&z)
    ok(actions([y, z], "mackie") == 0, "all modules OFF: no action, no owner")
    ok(!y.lock.isOwner && !z.lock.isOwner, "nobody holds the lock while everything is OFF")
    y.on = ["mackie": true, "midikeys": false]; z.on = y.on; poll(&y); poll(&z)
    ok(actions([y, z], "mackie") == 1 && actions([y, z], "midikeys") == 0, "mackie ON, midikeys OFF in both views: one action for mackie, none for midikeys")
}
print(fail == 0 ? "shared_test: all \(pass) passed" : "shared_test: \(fail) FAILED of \(pass + fail)")
exit(fail == 0 ? 0 : 1)
