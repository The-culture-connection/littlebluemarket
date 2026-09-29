# Paste this into a NEW Claude Code session, started from `little_blue_market/`

```
Another Claude Code session is working right now in this folder on branch redesign/pinterest-grid. Do not touch this working tree.

First, make your own worktree from the last committed state of that branch:
  git fetch
  git worktree add ..\lbm-phase9 -b redesign/phase9-donations redesign/pinterest-grid
  cd ..\lbm-phase9
Everything you do happens in ..\lbm-phase9 on branch redesign/phase9-donations. Never pull, rebase or merge mid-phase; never push to redesign/pinterest-grid or main; never run firebase deploy or the emulator-backed rules tests (ports collide with the other session). We merge later.

Then read CLAUDE.md (including the redesign section at the end) and Planning/phase9-donations-following-profile.md in full. Open Planning/donations-mockup.html in a browser — the "Chip in page", "Checkout round-up", "Feed nudge" and "You tab quiet row" moments are the visual spec.

Do Part A (Chip in page, checkout round-up, feed nudge + You row), then Part B (Following tab first, comments/threads on profiles with Edit-profile toggles), then Part C (functions + rules + index as file changes only, with unit tests, no deploy). One commit per part.

Keep changes additive: new files wherever possible; where you must touch feed_screen.dart, feed_items.dart, profile_screen.dart, app_shell.dart or the pin widgets, make the smallest insertion and keep the logic in your own files so the later merge is one line.

Before each commit run scripts\verify-redesign.ps1 -Phase 5 (Parts A/B) and -Phase 6 minus the emulator step (Part C). Never commit red.

Hard gates in the phase file: Shopify products are created by me, not by you — stop if the handles aren't in config; find out how Shipturtle treats a line whose vendor is the store itself and report before anything round-up-related is considered done; never invent numbers for the transparency tiles — read them from funding/{month} or show "—".

At the end, rebase once onto redesign/pinterest-grid, resolve conflicts keeping both sides, re-run -Phase 5, push redesign/phase9-donations, and report to me with: the conflict list, the golden shots, and the manual checklist rows from the phase file.
```
