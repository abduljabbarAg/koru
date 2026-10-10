# Changelog

## 0.4.0

The freelancer loop, made real. The tables for payments and deadlines existed
with tests and no UI, and the pay button did not use them.

### Added

- **Money as a ledger.** The pay button used to set a client to paid and
  overwrite the invoiced amount with whatever was typed in, which destroyed the
  original figure and could not express a part payment at all. Money is now
  appended to a ledger, and a client settles only when the ledger says so.
- **A client screen.** Payments, deadlines, notes and retainer terms for one
  client. The data was per client across three tables with nowhere to show it.
- **Retainers.** A separate monthly amount that reports last paid and next due.
  Deliberately not folded into the balance: a retainer has no invoice to be
  behind on, so a balance would invent money owed that nobody billed.
- **A capacity limit.** Asked for in onboarding, changeable in Settings, shown
  as a bar. Below capacity is an opportunity; at capacity is a warning. Only
  work actually under way counts.
- **A pipeline sorted by age**, flagging prospects untouched for 21 days.
- **Backup and restore.** Readable JSON handed to the share sheet, and an
  additive restore that never overwrites what is already there.
- **A currency setting**, asked for in onboarding. Display and prompt only;
  amounts are stored as bare doubles so there is no migration.
- **Writes from chat.** "add client Bilal for 2000" and "Bilal paid 500" are
  recognised by a plain Dart parser, resolved against the real clients, and
  shown as an editable card. Nothing is written until you approve it.
- **The model is told what clients owe**, so it can discuss it rather than
  guess from a status column.

### Fixed

- **The chat went silent while the model read the prompt.** The engine ran the
  whole prefill loop before writing the SSE headers, so the client had received
  no bytes at all and `send()` had not returned. Prefill carries your records
  and takes seconds; the answer then arrived a quarter-second at a time, which
  read as a hang followed by a drip. Headers now go out first and prefill
  reports progress.
- **The built-in assistant told you to chase money you already had.** It summed
  invoice amounts rather than reading the ledger.
- **"Delete everything" left the payments and deadlines behind.** `wipe()` had
  never been updated when those tables were added.
- **"What is coming up" was a shrug.** It is one of the app's own suggestions
  and matched none of the assistant's keywords.

### Removed

- **Fitness.** A whole tab, with the loudest claims in the product. Gone from
  the screen, nav, packet, guide, model prompt and assistant. Onboarding asks
  for a client capacity instead of your weight and height.
- **Learning and drafts.** Both existed with zero writers.

## 0.2.0

The local-first promise, made real.

### Added

- **Koru, the mascot.** A generated sprite atlas with idle, blink, wave, think,
  cheer and greet clips, plus an animation state machine that handles blinking
  on a varied cadence so it does not read as a metronome. He appears on the
  splash screen, in the chat bar, in the chat empty state and on the drafts
  screen, and he is tappable. All artwork is generated from
  `tool/generate_assets.py`.
- **A real on-device assistant.** `RoutingDecision.useCloud` was computed,
  displayed in Settings, and then ignored, so every question went to a paid API.
  There is now an on-device responder that answers status, fitness, business and
  goal questions from your own records without a network call.
- **Drafts.** Onboarding has promised "drafts, never sends" since 0.1. There was
  no table and no code path behind it. There is now a `drafts` table, a screen,
  and an approve/discard flow.
- **Learn tab.** The `knowledge` table existed since the first commit and had
  never been read or written. It now has a screen and is wired up.
- **Human handoff.** The crisis path produced one line of chat preamble. It now
  shows a card with named services, distinguishes an emergency from a topic that
  needs a professional, and suppresses the model answer entirely.
- **Keystore-backed API key.** Settings said "stored on this device" while the
  key sat in a `StateProvider`, i.e. in memory, vanishing on every restart and
  surviving "delete all data". It is now encrypted with an Android Keystore AES
  key, and deletion clears it.
- **Persistent chat.** History lived only in a `Notifier`, so closing the app
  lost the conversation.
- **Business**: due dates, notes, editing, and payment capture. The columns
  existed and nothing could set them.
- **Fitness**: editing, deleting, a BMI column per log, and a weight trend chart.
- **Settings**: your context is editable. Onboarding said "you can change this
  later in Settings" and Settings could only display it.
- Chat history, drafts and knowledge are cleared by "delete all local data".
- Launcher icons, splash illustration and Android launch crest, all generated.

### Fixed

- **The nickname leaked to cloud models.** Onboarding promised it never left the
  device, and it was being placed into the system prompt. There are now separate
  local and cloud renderings, and a test that fails if they merge.
- `help_focus` was written during onboarding and never read, leaving
  `ContextPacket.focus` permanently empty.
- The fitness summary silently dropped height whenever a measurement was logged.
- Cloud replies were parsed with a hand-rolled scanner that broke on escaped
  quotes and grabbed the wrong field. Now uses `jsonDecode`, with typed results
  so a network failure is not shown to the user as if it were an answer.
- `wipe()` left the `knowledge` table untouched.

### Changed

- Release APKs are still signed with the debug key unless `android/key.properties`
  is provided. See README.
- CI publishes a GitHub release on a `v*` tag, and no longer uploads only an
  arm64 artifact.
- `analysis_options.yaml` treats unused imports, variables and elements as
  errors. Roughly a third of the original codebase was dead code.

## 0.1.0

- First release: onboarding, chat with OpenRouter, business and fitness tracking,
  SQLite storage, crisis routing, APK build in CI.
