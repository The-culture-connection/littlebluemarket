# Paste this into Claude Code, from `little_blue_market/`

```
Read CLAUDE.md, then Planning/redesign-plan.md in full, then Planning/redesign-checkpoints.md.
Open Planning/full-app-redesign-mockup.html in a browser tab (it is the visual spec).

Run the preflight (plan §1). If P3 or P4 fails, stop and tell me.
Then work the checkpoints file top to bottom, one unticked box at a time.
Run scripts\verify-redesign.ps1 -Phase N before ticking a phase; never tick red.
One commit per phase, pushed to the branch redesign/pinterest-grid. Never merge to main.
Stop and report after Phase 2 and after Phase 5 with the test/shots/*.png attached.
Do not start Phase 6 (Firestore rules + functions) until I say go.
Hard gates are in plan §2 — if a task needs anything outside the files-touched map, stop and ask.
Welcome screen and GIF: do not touch, at all.
```

Before pasting: append `Planning/redesign-CLAUDE-additions.md` to the end of `CLAUDE.md` (it's a fenced block — copy what's inside the fence).
