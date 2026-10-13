# What is left

Snapshot: 14 October 2026. Everything below is either approved and not started,
or started and unfinished. Nothing here is a maybe: the user approved this list.

## Done in this session (committed)

**Calendar**
- `events` table (schema v7): date, time, location, duration column, synced flag.
- "schedule a call with Bilal tomorrow at 3pm at the studio" is parsed by
  `WriteIntentParser` into `AddEventIntent` → approval card → store, like every
  other write. Title/date/time/location all read; a bare number is never a time.
- Optional one-way mirror to the phone's own calendar (`lib/calendar_bridge.dart`,
  device_calendar + flutter_timezone), asked at the moment of approval or from
  the Business screen, never throwing, marked synced only after the copy lands.
- Business screen: "Calendar" section with per-entry sync and delete.
- Settings: "Copy new entries to my phone calendar" toggle; permission asked
  when it is turned on, not at startup.

**On-device assistant (much broader)**
- Small talk (how are you / thanks / goodbye / praise), date and clock,
  arithmetic incl. percentages, "how much does X owe" for one named client,
  "who should I chase", counts, and calendar answers (entries + deadlines
  merged for the next 7 days).
- Greeting/identity phrasings vary deterministically per question.
- Fallback names concrete questions to ask instead.

**Chat**
- Follows the stream while an answer generates; explicit send always lands at
  the new turn.
- Timestamps (in the badge row, no extra height), long-press a reply to copy.
- Fixed the per-bubble `ValueNotifier` leak (bubble is a proper stateful widget,
  handoff dismiss survives rebuilds).
- Guide banner on the empty chat; calendar suggestion chip; per-write activity
  wording ("Checking your calendar").

**Fixes found on the way**
- "Delete everything" now clears projects, project notes and events (it
  previously left all three behind).
- The local model's facts were missing projects; added, plus events.
- `CardTheme` → `CardThemeData` (new Flutter made it an error).

All 494 tests pass, analyze is clean.

## Next (Phase 1 remainder, already approved)

1. **Mascot upgrade** — procedural improvement in `tool/generate_assets.py`:
   body gradient + rim light, ambient occlusion, iris/eyelid/catchlight eyes,
   frond interior highlight, motion follow-through. Regenerate atlas, splash,
   icons. Keep the atlas contract (192 px cells, 32 frames) so
   `mascot_clips.dart` and `atlas_layout_test.dart` are untouched.
2. **Event depth**
   - Durations ("for 2 hours"), recurrence (weekly / monthly meetings).
   - Edit an existing event (currently create + delete only).
   - Events in the attention list (`lib/attention.dart`) so today's entries
     reach the notification/widget/badge like deadlines do.
   - Notification for a timed entry N minutes before (needs a channel + the
     existing `AttentionWatcher` pattern).
3. **Chat depth**
   - Light markdown rendering of replies (bold, lists) — cloud replies use it.
   - Scroll-to-bottom pill when scrolled up during a stream.
   - Timestamps on user bubbles too (deliberately skipped: an extra row per
     bubble grew the thread and moved cards below the fold).
4. **Assistant depth**
   - Follow-ups that resolve against the previous turn ("what about next
     week?") for the built-in engine.
   - Fuzzy client-name matching (typos) in `how much does X owe`.
5. **Tests to add**: widget test for the Business calendar section; flow test
   for schedule → approve → lands in store → mirrored flag.

## Phase 2 (UI, from the audit)

- Dark theme + Material You dynamic colour (`MaterialApp` has no `darkTheme`).
- Human dates everywhere ("due in 3 days" instead of `2026-10-13`) — a shared
  formatter used by business, client detail, chat.
- Haptics on approve / settle / complete / tab switch (currently zero).
- Error states that are not raw `$e` strings; skeleton loading instead of bare
  spinners.
- M3 `NavigationBar` with the attention badge (count already exists in
  `attentionProvider`).
- Responsive: max content width, a tablet breakpoint, two-pane client list.
- Accessibility: `inkFaint` on cream is ~3.4:1 (needs ≥4.5:1), no text-scale
  handling, ~32 px chip targets.
- `SearchAnchor` for the model picker; About/licences + app version in Settings.

## Phase 3 (features, from the audit)

- Invoices: numbering + shareable document (data already on the client row).
- "Today" screen from `attentionProvider` (computed and published to Android
  but shown nowhere in the app).
- One-tap payment reminders (share/SMS intent with a composed message).
- Wire the deep links: `AttentionBridge.takeLink()`/`listen()` exist, are
  tested, and have no callers — notification taps currently do nothing.
- Charts: received vs outstanding, aging, lead-source conversion.
- Expenses table (profit is impossible without it).
- Global search; sort/filter on the client list.
- Recurring retainers (auto-generation, missed-retainer alert).
- Share-into-Koru (`SEND`/`PROCESS_TEXT` intent) + CSV import.
- Projects: link a new client project to a client (`projects.dart:467` cannot),
  a detail screen, make stored notes visible.

## Repo chores

- `pubspec.yaml` says `0.2.0+2`, CHANGELOG is at `1.2.1` — reconcile and bump.
- README feature table still lists Talk/Business/Settings only (Projects and
  the Calendar section are missing); project layout still mentions the cut
  fitness/knowledge/drafts screens.
- `HANDOFF.md` says `schemaVersion = 4`; it is now 7.
- Release signing still falls back to the debug key (flagged in HANDOFF as the
  one production blocker).
- `.git/config` carries a plaintext GitHub token (flagged in HANDOFF:
  "rotate all of these").
