# TAKEOVER: MANTRA_MIDI_MODULES

The MIDI modules shared by two Mac apps, as one source: **MIDI to MK Control** (`Mackie*.swift`) and **MIDI to Key Stroke**
(`MidiKeys*.swift`, `Ports.swift`), plus the sharing itself (`SharedPure.swift`, `SharedHost.swift`).

Marko, 22.11.2026: "All the MIDI modules should only be actually in both places. We are sharing the modules. We can do that.
So because they are shared modules, they also share the settings. It's the same thing, just in different views."

- **Consumers:** ABLETON_LIVE_ACTIONS (Ableton Live Assistant (Mantra)) and MANTRA_MIDI_TOOLS (MIDI Tools (Mantra)). Each pulls this repository as
  a git submodule in `shared/`, pinned by commit, and compiles `shared/*.swift` with its own `app/*.swift`. Each has `shared.sha256`;
  its workflow fails when the hash of `shared/*.swift` differs, so both builds hold byte-identical sources.
- **What the apps provide** (globals the shared code uses): `APP_NAME` (display name), `APP_SOURCE_DIR` (its folder under ~/Developer, for the
  helpers fallback), and the usual app kit (LiveModule, Chord, INK, Word, CloseX, Small ...).
- **One state:** `~/.config/mantra-midi-modules.json` `{"schema":1,"modules":{"mackie":{"on":true},"midikeys":{"on":true}}}`, atomic writes. Made once from
  the old `live-actions.json` and `midi-tools.json` "modules" keys (ON when any says ON). The table settings stay in `midi-to-mk.json` and
  `midi-to-keystroke.json` (atomic, re-read by both apps when they change).
- **One engine:** the owner lock `~/.config/mantra-midi-owner.lock` (flock, held open by the owner, JSON with pid and app name). `MidiHost` polls once a
  second: the owner runs the engines of the modules that are ON; the other app is a view and says "runs in <the other app>". The owner quits or
  dies: the other takes over within about a second. One app alone: it owns, no line.
- **Tests:** `tests/shared_test.swift` (state, migration, lock, view line, one knob one action), run by this repo's workflow and by both apps' workflows.
- A1's E16 blob (`A1MIDI.swift`, Live Assistant only) is part of A1, not a shared module. It only reads and shows incoming MIDI (a second input
  port on the same source: harmless, no action).
- Public and unpromoted by the rule (repo-privacy.md): no README, no description.
