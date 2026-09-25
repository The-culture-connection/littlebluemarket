# Append this section to `little_blue_market/CLAUDE.md` (do not replace the file)

```markdown
## Redesign branch rules (Sept 2026) — these override the sections above while on `redesign/pinterest-grid`

**Source of truth.** `Planning/redesign-plan.md` is the spec; `Planning/full-app-redesign-mockup.html` is what it must look like (open it in Chrome, "All screens"). `Planning/redesign-checkpoints.md` is the queue — first unticked box only. `Planning/ux-map.md` explains the feed recipe.

**Branch and merge.** All work on `redesign/pinterest-grid`. Push the branch at the end of each phase. **Never merge or push to `main`** — the "push to main at the end of each phase" rule above is suspended on this branch. Grace merges.

**Hard gates — stop and ask.** Any change under `firebase/` (rules, indexes) or `functions/` outside Phase 6; anything touching Shopify, Shipturtle, `catalog.ts`, `cart.ts`, `orders.ts`, `linking.ts`, `vendors.ts`, money; deleting data; deleting or relaxing a test not named in the plan; **any edit to `lib/screens/onboarding/welcome_screen.dart`, `lib/app_assets.dart`, `assets/`, `LbmConst.welcomeBlue/onWelcome/slate`, or `test/welcome_handoff_test.dart`** (Grace: welcome screen and GIF stay exactly as they are); any file not in the plan's files-touched map.

**Never invent data.** If the mockup shows a number the app has no source for ("23 here now", "replies in ~1h", "12 people carted it this week", "Rae and 2 people you've bought from"), either omit it or render static copy with a `// STATIC COPY — no data source yet` comment. The plan says which per task.

**Product decisions still stand.** Cart is the like (no heart anywhere — `test/pins_test.dart` greps for it). Orchid `accentDeep` is for the cart action and the [+] button only; chips and secondary buttons are sky/ink. No points, levels or streaks. No shipping status or orders in the app — Shipturtle owns that; "Under review" links out to `appConfig.shipturtleUrl`.

**Every repository interface change is made in three places in the same commit:** `lib/data/repositories/repositories.dart`, the Firestore implementation, and `lib/data/fixtures/fixture_repositories.dart` (+ `fixture_store.dart` if state). `flutter analyze` is the enforcement.

**Every new tile survives 390 wide at text scale 2.0 in both themes.** `screens_smoke_test.dart` and `text_scaling_test.dart` are the gate; use the `Wrap` / `FittedBox` idiom from `_CartBody` in `post_card.dart`.

**Write code with the file tools, never through shell one-liners.** `sed`/`echo`/heredoc edits eat escapes (`\s` → `s`) and interpolate variables silently. Use Edit/Write.

**Verify, then report.** `scripts\verify-redesign.ps1 -Phase N` must exit 0 before a phase is ticked. A green suite is not proof — the *Done when* in the plan is observed on `run-fixtures.ps1` before ticking. After Phase 2 and Phase 5, stop and report to Grace with the `test/shots/*.png` attached; do not start Phase 6 until she says go.

**Commit messages.** `redesign(N): <what>` on the first line, phase summary in the body, ending with the attribution line this environment specifies (the `Co-Authored-By: Claude Opus 5` line earlier in this file is the previous session's; use the current one).
```
