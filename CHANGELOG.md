# Changelog

## 1.0.0

Cloud first. The on-device model is out of the app.

### Changed

- **The local engine and its model are no longer bundled.** 486 MB on top of a
  16 MB app, on every install, for a model that was not earning its place. Cloud
  is now the default engine, and a local model can still be dropped into the
  app's models folder if you want one. One line in the build puts it back.
- **Twenty cloud providers, searchable.** Atria, Cerebras, Fireworks, NVIDIA NIM,
  Hugging Face, Moonshot, Perplexity, Z.ai, MiniMax and Inception join the ones
  already there. Search matches provider label, provider id and every model id at
  once, so looking for "glm" finds it without knowing whether that is Z.ai,
  Zhipu or a custom endpoint. A search matching nothing returns nothing, rather
  than quietly falling back to the full list.
- **Atria Dawn Preview**, Shanghai AI Laboratory's agentic model, served OpenAI
  compatible. Its model id is capitalisation sensitive.

## 0.9.2

The local model can be chosen, so a sharper one can be brought in.

### Added

- **Bring your own model.** The bundled 0.5B is no longer the best thing this
  phone can run: a 1.7B ternary model fits in about 600 MB resident and is
  markedly sharper, at 11.18 perplexity against 21.95 on the same prose. It is
  also three times slower, so it is offered alongside rather than instead of the
  fast one, and the picker keeps the bundled model first.
- **Models are also looked for in the app's external folder**, which is reachable
  from Downloads without rooting. The private one is not, so without this,
  bringing your own model would have been impossible in practice.

### Notes

- The bigger model is deliberately not bundled. At 442 MB it would take every
  install past 900 MB to serve a choice most people make once.

## 0.9.1

The model is told what the app is, and the indicator stops saying "waking up".

### Changed

- **The model now knows what the app is for.** The system prompt said only what
  it must not do, so with no idea what it was for it refused anything outside the
  facts, and asked about a client it began an answer, abandoned it mid-sentence
  and produced "I am Koru, a personal assistant" instead. It now knows the app
  keeps clients, money, deadlines and projects, that it can record any of them,
  and the phrasing that does so. Six lines, with a test capping it, because every
  line is prefill the user waits through.
- **The waiting indicator names the job.** It opened on "Waking up" for every
  request and only moved when the engine reported a token, so anything not going
  through the local model sat on "Waking up" for the whole answer. It now says
  checking what is due, looking up clients, reading a pasted list, or working out
  what you meant.

### Fixed

- **Permissions are asked on the splash, before onboarding.** Asked after
  onboarding finished, a first run ended with no prompt at all. Nothing on that
  path is awaited, so a system dialog can never hold the start screen open.

## 0.9.0

The app no longer gets stuck on its own start screen.

### Fixed

- **The splash could hang forever.** It held itself until the local engine
  reported progress, which made the start screen hostage to work happening behind
  it: a system dialog for battery optimisation, a slow model copy, or a health
  check that never answered. Any of those left you on the splash with nothing to
  tap and no way forward. It now leaves on a plain timer that none of that can
  starve, and the engine reports progress in the chat instead, where being slow
  costs nothing because there is other work to do.
- **Permissions were not asked on the first run.** They were asked from the
  start-up path and only when onboarding was already complete, which is exactly
  backwards: on a fresh install the condition was false, nothing was asked, the
  flag was written anyway, and they turned up on the second launch. Asked at the
  end of the first run now, and the flag is written only after the prompts have
  actually been shown.

### Changed

- **The waiting indicator animates and says what is happening.** Three flat dots
  became a cycle through a flat, rising and triangle shape, driven by one
  controller so the stages cannot drift apart. Beside it, a label names the phase:
  waking up, reading your records, writing an answer, working out what you meant.
  Dots answered "is it working" but not "is it working on the right thing", and on
  this phone a prefill and a decode feel identical as an animation. The switch is
  not guessed, it happens exactly when the first token lands.

## 0.8.1

Chat stopped dying after a Stop, and editing stopped eating the conversation.

### Fixed

- **One press of Stop killed the chat for the rest of the session.** The flag
  stop() set was only cleared on a line that came *after* an early return
  testing that same flag, so it never cleared. Every message sent afterwards was
  dropped before it reached the screen, and nothing said so. Reported as "edit
  breaks chat" and "my message does not even show". Replaced with a generation
  counter: starting a request is what makes the previous one stale, so there is
  nothing left behind to be forgotten.
- **Editing during a reply destroyed the conversation.** It deleted the stored
  records and trimmed the screen before checking whether it could finish, so an
  edit while an answer was running wiped everything and added nothing in its
  place. Everything is now checked first, and each refusal explains itself.
- **Editing a reply from Koru did nothing at all.** It now says which message is
  his and why it cannot be edited, rather than closing the sheet and appearing
  to break.
- **The first question of a session is no longer a cold start.** glen's warm-up
  encodes the word "warm" into a scratch cache it then throws away, which shares
  no prefix with a real question and helps nothing. One background request now
  carries the real system prompt, so the first question starts from a filled
  cache instead of prefilling cold.

## 0.8.0

Koru is allowed to make a sound, and bulk import has a plan in front of it.

### Changed

- **Koru now has two notification channels rather than one quiet one.** Money
  already late and work due today make a sound; everything else, and the ongoing
  status, stay silent. The old reasoning was that a helper which nags gets swiped
  away unread, which was half right: a silent deadline is a deadline that gets
  missed, and that cost lands on the user rather than on us.
- **Sound on change, not on every check.** The hourly alarm re-posts state, so an
  alert that sounded each hour for a deadline that has not moved would be exactly
  the nag this avoids. Koru speaks when the set of urgent things differs from
  last time, sorted, so the same three in a different order is not a change.
- **A payment for a client who has been deleted is refused.** The payments table
  carried no foreign key, so such a payment was written and then belonged to
  nobody: money recorded, invisible from every balance, no error anywhere.

### Added

- **Bulk import of a client list**, read one row per line and shown as a numbered
  plan before anything is written. Applied as one transaction, so a partly
  imported list is impossible. Lines the parser could not read are listed on the
  card rather than dropped, and the same list cannot be pasted twice.

## 0.7.3

Koru is present while you set him up, and you see what he was told before he
starts answering from it.

### Changed

- **Koru appears on every setup screen, not just the first.** He introduced
  himself and then vanished for the five screens where you were actually filling
  things in. A character present during setup is a guide; one only present to
  say hello is decoration. His expression follows the step, so the face carries
  information rather than just moving.
- **There is a review screen before anything is saved.** The old flow went
  straight from the last question to the home screen, so the first thing anyone
  learned about their assistant was by it being wrong later: six answers,
  silently stored, no chance to see them.
- **Skipped answers are shown as skipped, and can be jumped back to.** That
  silence is the same one that made the client screen read zero. Nothing
  defaulted to a real value and nothing said so, so the app looked like it was
  ignoring what was typed.

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
