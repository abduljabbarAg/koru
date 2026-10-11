# Changelog

## 0.7.2

Koru now assumes it will be stopped, and says so when it has not been set up
properly.

### Added

- **Koru puts itself back together.** A boot receiver and a slow hourly alarm
  re-post the last known state, so a service the phone stopped is restored
  instead of staying silent. The alarm is inexact on purpose: an exact one would
  wake the phone to a precise minute to discover nothing had changed, and
  Android 12+ treats that as a misuse of a capability meant for alarms.
- **Permission checks, named one by one.** Notifications, battery optimisation
  and, where the phone has such a screen, autostart. Each is granted separately
  and can be refused separately, so "Koru cannot show notifications" is shown
  rather than "Koru has a problem", which nobody can act on.
- **Asked once.** On first run, in the least annoying order, and never again. A
  prompt that returns every launch teaches people to dismiss dialogs without
  reading them, which costs the permission that actually mattered. Declining
  everything still gets you into the app; a helper that holds the door until you
  agree to everything is not a helper.
- **Autostart is reported as not applicable, not failed,** on phones that have
  no such screen. A stock device is not shown a red cross for a setting it does
  not have.

## 0.7.1

Adding a client now means something, and Koru can answer the question the app
exists for.

### Fixed

- **Every total on the Business page read zero.** Not a display bug: the client
  form asked for an amount and made it optional, so the normal outcome was a
  client with nothing in it. Every figure is agreed minus received, so a client
  with no agreed amount contributes nothing to owed, nothing to outstanding, and
  never becomes overdue. The notifications and the widget were working correctly
  and had nothing to ever say about it.
- **"What is due today" was answered with "I could not match that".** The
  sentence contains none of the words the business intent matched on, so it fell
  through to the fallback and Koru told the user it could not help with its own
  deadlines. It now answers, split into late money, late work, due today and
  coming up this week.

### Changed

- **Adding a client is one flow, not two.** Agreed amount is required. Payment
  terms replace the hand typed due date: choose net 7, net 14, net 30 or on
  completion, pick when you invoiced, and the due date is worked out and shown
  back to you. An exact date can still override it.
- **A deposit is a payment.** It goes into the ledger rather than being
  subtracted from the amount, because money is computed from the ledger
  everywhere and a second copy that only affected one screen would eventually
  disagree with it.

## 0.7.0

Koru outside the app: on the home screen, and in the shade when it has
something to say.

### Added

- **A home screen widget.** Koru sits on the home screen and shows what needs
  you. The face changes with the situation, and it is driven by the same list
  that drives the notification and the badge, so the three cannot disagree. A
  widget showing a content face over an overdue invoice would be worse than no
  widget at all, so "cheer" means nothing is outstanding, "thinking" means money
  or a deadline is, and a quiet project on its own is neither.
- **Notifications that survive the app being closed.** A foreground service, which
  is what Android requires to keep checking for overdue work once the app is not
  running. It shows one permanent, silent, low importance notification. That is
  the deal every reminder app on the store makes, and it is quiet on purpose: no
  sound, no heads up, nothing that trains you to swipe Koru away.
- **Tapping a notification opens the thing it was about**, even from a cold
  start. The link survives the process being killed and rebuilt, which is the
  normal case when tapping a notification.
- **Projects, and the difference between client work and your own.**
  Personal projects have no money on them at all, not a hidden zero, so they
  cannot leak into a balance or a "who owes you" answer. Notes accumulate in
  order because they are what progress is worked out from.

### Changed

- **The local engine starts itself** when it is the selected engine, instead of
  needing a trip to Settings every launch.
- **The splash bar is real.** It held for the engine and says which of the two
  slow things is happening, rather than sweeping forever regardless.

## 0.6.1

The 0.6.0 conversation memory had a bug that made the app feel like it was
dying. It was my fault and it is worth writing down exactly what happened.

### Fixed

- **The local engine could crash and take the conversation with it.** A prompt
  longer than the engine's 1024 token KV cache indexed past the end of the
  cache and panicked the process. The REPL compacted long conversations; the
  HTTP server the app actually talks to never did. A panic killed the server,
  so the next question started a cold engine, the one after that started from an
  even longer transcript, and the app got slower and slower rather than just
  slow. Measured on the device, the request that triggered it ground for 96
  seconds and returned nothing. serve now fits the prompt to the window by
  dropping the oldest middle messages, and the cache write itself refuses to go
  out of bounds rather than killing the process.
- **History is budgeted in tokens, not characters.** 0.6.0 allowed 8 turns of
  400 characters, about 1600 tokens, which does not fit. It is now capped so the
  prompt leaves genuine headroom for the answer.
- **The tokens per second badge was measuring the wrong thing.** It divided by
  the whole request including prefill. Prefill is roughly 15 tokens a second
  here and decode is 4, and the first question prefills while every follow-up
  reuses the cached prefix, so an engine that never changed speed was reported
  as 0.3 tok/s on a cold ask and 4 tok/s on a warm one. It now reports decode
  only, and shows the prefill wait separately because it is the longest silent
  part of a first answer.

## 0.6.0

Replies that arrive the way they are typed, and a model that knows what was
said before. All five of the complaints from testing v0.5.0.

### Fixed

- **Only the first token ever appeared.** One letter landed instantly, then the
  rest of the answer arrived in a single jump several seconds later. The model
  was streaming correctly the whole time; the client threw every token after the
  first away. A pending flag meaning "this message is still being generated" was
  being set from "this message has no text yet", so the first token ended the
  generation as far as the screen was concerned. The 334 passing tests missed it
  because the fake model emitted all its tokens in one synchronous loop, so no
  frame was ever drawn between the first and the last. There is now a fake that
  yields between tokens like a real socket does, and it fails without this fix.
- **"create new client Primedose" said the client could not be found.** The
  parser tried one kind of write at a time in a fixed order, so a sentence
  carrying more than one cue was always classified as whichever kind happened to
  be checked first, and it could reach the model instead of the parser. The cue
  that appears earliest in the sentence now wins, and the client phrasings
  people actually type are recognised.

### Added

- **The model remembers the conversation.** Earlier turns now travel as real
  chat messages, so "how much is that?" resolves. They are deliberately kept out
  of the system prompt: glen reuses the longest common token prefix across
  turns, and a prompt that changed every turn would mean a full prefill every
  turn. On this phone that is the difference between 1.2 seconds and over a
  minute, and the question no longer appears in the prompt at all since it is
  already the user message.
- **Stop.** The send button becomes a stop button while an answer is being
  written. A greyed-out button for fifteen seconds is the app looking busy; a
  stop square is the app offering a way out. Tokens that arrive afterwards
  cannot repaint the bubble.
- **Edit a message.** Long press anything you sent, change it, ask again. The
  abandoned exchange is dropped from the screen and from the stored transcript,
  so there is never two answers to the same question with nothing saying which
  one is current.

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
