# LESSONS

- 22.11.2026: two copies of one module drift (the two apps' MIDI modules differed by 4 to 16 lines of names) and both opened the same MIDI sources and
  key tap, so one knob fired twice. One source, one state, one owner.
- flock on a file held open by the owner is the owner lock: the kernel lets it go when the process dies, so there is no stale lock to clean.
- 23.11.2026: AbletonOSC moved to UDP 11010 (listen) / 11011 (reply), Suno Bridge owns 11000. MackieIO.swift asks 11010 now.
