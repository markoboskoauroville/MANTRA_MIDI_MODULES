# LESSONS

- 22.11.2026: two copies of one module drift (the two apps' MIDI modules differed by 4 to 16 lines of names) and both opened the same MIDI sources and
  key tap, so one knob fired twice. One source, one state, one owner.
- flock on a file held open by the owner is the owner lock: the kernel lets it go when the process dies, so there is no stale lock to clean.
