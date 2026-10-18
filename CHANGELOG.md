# Changelog

## Unreleased

### Changed

- **The shell is three tabs.** Today, Clients, Money — the fifth tab is gone
  rather than renamed. Tasks and Revenue were tabs showing records the queue and
  the client list already showed, so Tasks became the browse view one tap behind
  the morning queue ("All work") and Revenue became Money. "Tell Koru" floats in
  the middle of the bar as the app's quick-add, because a person arriving for the
  first time should meet their work before they meet configuration; Settings
  stays in the header of every tab.
- **The morning happens once a day.** Today opens with one card: Koru greets you
  by name, the queue briefs in a sentence, and the quote of the day rides inside
  the card instead of an extra line at the bottom of the screen. One tap
  dismisses it for the day, and the flag is the date, so tomorrow is genuinely a
  new morning. The all-clear gets a small celebration — Koru cheers, the card
  scales in, the phone gives one soft thump.
- **Recording a payment is celebrated.** The one unambiguously good news in this
  app used to end in a grey snackbar sentence. The amount now rises into view in
  the green that means received, Koru cheers behind it, and it is gone in a
  second and a half — long enough to feel, short enough to never be in the way.
  The toast underneath still carries the number that matters: what is left.
- **Onboarding is three pages and ends with a real client.** It was seven
  questions — stage, work situation, capacity, currency, goals, help focus and a
  review — asked before the app had done anything for the person, and it ended on
  an empty app. Now: meet Koru and a nickname, the one answer the rest of the app
  cannot live without (the currency), and the first client, which is what makes
  Today worth opening on day one. Capacity keeps its default and moves to
  Settings; goals live in Your context.
- **Settings groups twelve rows into five.** "Who answers", "Cloud provider" and
  "What leaves this phone" pull on the same subject and now share one group
  ("The model"); the four legal documents are one door deep ("About & legal")
  instead of half the index.
- **The launcher icon is adaptive.** API 26+ gets the frond mark on a leaf
  background, which the launcher masks into its own shape, the way it masks every
  other icon on the phone; older phones keep the legacy tile. The generator in
  `tool/generate_assets.py` writes both from one drawing, so they cannot drift.
- **The not-connected screen tells the truth about the app.** It used to say
  Koru "cannot turn what you type into a record" without a model, which was never
  true — "add client Bilal for 2000" is read on the phone, with no key at all.
  It now says what a model is actually for: questions. The word "Talk" left the
  copy as well; everywhere in the app now asks you to tell Koru.

### Removed

- **The on-device model, and with it every second engine.** The bundled
  llama.cpp binary and the Bonsai-1.7B-Q1_0 weights are gone from the app, the
  Dart client that spoke to them, the model picker, "bring your own model", the
  engine log screen and the launch warm-up that started a server before the
  splash had finished. The APK goes from 258 MB to roughly 10.

  This is not only about size. Every complaint reported about the assistant was
  that model: asked a question, it talked about a client instead of answering,
  invented exchange rates, repeated itself, and took about thirteen seconds for
  forty tokens. Cloud models are far better at the one job this app needs from
  AI, which is turning what somebody types into a record they then confirm.

  Installs that were on `onDevice` are moved to the cloud engine by a v12
  migration and land in the honest not-connected state if no key is saved. With
  nothing connected, Koru says so and offers the tap that connects one — there
  is no fallback that answers from the records with no model behind it.

### Fixed

- **The permission explanation is reachable on a first run.** "I have to close
  the app and start again then i see the permission screen." The gate decided
  the question once, at launch, and answered "nothing to ask about" for anybody
  who had not finished onboarding — which is every genuinely fresh install. The
  answer was then held in a field that was never recomputed, so onboarding
  finished, the gate rebuilt, and the screen had already been ruled out for the
  rest of the session. Only the second launch asked the question with
  onboarding behind it. It is now decided the moment onboarding finishes, and the
  read is bounded so a platform channel that never answers cannot leave somebody
  standing on a loading screen.
- **A question asked while an answer is arriving is asked.** "I ask a question,
  I get an answer. I ask another question, I get the exact same answer."
  `ask()` returned without sending anything whenever a turn was under way, and
  the composer had already cleared itself, so the question was destroyed before
  it left the building and the thread went on showing the previous answer — no
  request was made, so nothing downstream of it could depend on the new input.
  An answer on this phone takes about thirteen seconds, so that window was most
  of the time somebody was reading the last answer and thinking of the next one.
  A question asked during a turn is now held and sent as soon as that turn is
  finished, carrying the exchange that came before it. The launch warm-up, which
  is the one other thing that could be in flight, now waits behind a turn rather
  than competing with it for the engine's single slot.
- **The cloud engines are given the conversation.** OpenAI-format providers were
  sent the earlier turns and Anthropic and Gemini were sent the bare question,
  so a follow-up to those two was asked against the same records as the turn
  before it with nothing to connect the two. All three now get the exchange with
  the new question last, in the shape each one requires.
- **A few sentences that read as the wrong record.** "change client Bilal status
  to paid" was read as a client called "Bilal status", "delete the client called
  Bilal" as a client called "called Bilal", "the shop is now done when the roof
  is on" set progress to 100%, and "60% done" lost its percent sign before it was
  read. All four are the same class of thing: a word the sentence needed treated
  as part of a name, or a sign treated as punctuation.
- **A write is reported as what it was.** An edit or a delete was announced with
  the same "Added … You can undo this from Clients" as an addition, including for
  the two things that cannot be undone. Each write now says what it did, and a
  delete says plainly that there is no undo for it.

### Added

- **The model can change and remove projects, and write notes.**
  `write_intent.dart` had intents for creating a client, editing one, deleting
  one, creating a project and recording a payment, and nothing for the other
  three. Editing a project (its name, what it is for, the plan, how far along),
  deleting one, and adding a note to a client or a project are now recognised,
  resolved against the real records, and proposed as a card to approve. They run
  on both engines, because the parser runs before either is chosen. A delete is
  styled and worded as a delete — clay rather than gold, and "Delete it" rather
  than "Save it" — since that is the one card where the difference between what
  is being added and what is being lost is the decision.

### Added

- **The engine control in the chat's top bar opens the engine picker.** Tap the
  control in the app bar — before anything has been asked, or in the middle of a
  conversation — and it lists the two engines with what each one costs: the
  same two Settings offers, written to the same key. Nothing about the engine
  is a trip to Settings any more, and nothing about it is hidden behind having a
  reply to tap.
- The control shows the detail the pill never had room for: which model is on the
  phone, which company answers online, and tokens a second once a local model
  has actually answered. The pill on a reply is now a label only — it still
  records where that reply came from, and it is no longer a control sitting in a
  different place on every message.
- **Choosing "Local model" starts it there and then.** One tap, in the sheet:
  the model is written, the engine is launched, and the sheet stays up showing
  real progress until the server answers. On a cold install that is a 248 MB
  copy out of the APK, so the wait is reported rather than guessed at —
  "Copying 248 MB out of the app. Once, on first use.", then "Waking the server
  up 42%".
- **Cloud and model sub-pickers.** Choosing the cloud model opens the provider
  list, with the ones that already have a key marked; choosing the local model
  opens the .gguf models this app can see, the bundled one first and ticked, plus
  anything added with the file picker. Picking a different model while a cold
  start is still running restarts the engine on that one rather than joining the
  start in flight and quietly serving the other.
- **A failed start says what failed, in the sheet, with a retry.** The reason
  comes from the engine's own log. It used to fall back to the built-in
  assistant, which answers in milliseconds and is indistinguishable from a model
  being fast.

### Removed

- **The built-in engine. There are two engines now, and both are models.** It
  answered out of the user's own records by phrase matching, produced a sentence
  in milliseconds whatever was asked, and was reached for whenever a real model
  could not be: a model that had not started, a key that was not set, a crash.
  That is the shape of the complaint it caused — "the AI is there and it answers
  rubbish" — because the app looked exactly as alive as a working assistant
  while nothing was generating anything, and the difference was a parenthetical
  note underneath a Koru badge. Nothing in Koru substitutes an answer for a model
  now.
- **The assistant it deleted:** `lib/local/local_assistant.dart`, the ~1,470-line
  advice library under `lib/local/replies/`, and `lib/local/facts.dart`. Writes
  never went through it — a plain parser resolves an instruction to record
  something and comes back as a card to approve, on every engine — so clients,
  projects, deadlines and calendar entries are recorded exactly as before.
- **The fallback answering in both engines.** An unreachable model on this phone
  no longer answers from the records with a note about it; a missing cloud key
  no longer answers from the records at all.
- Installs that were on the built-in engine still have `'builtIn'` in the
  profile table. A v10 migration rewrites that to the model inside the app, and
  the read falls back to it for anything this build does not recognise, so an
  upgrading install lands on a working engine rather than on no engine. The
  rules-based assistant was not carried over as the fallback: a cold start is
  honest, a substitute answer is not.

### Changed

- **Nothing answers while the model is not running.** The reply says which engine
  is missing and carries one button: start the local model, add a cloud key, or
  choose who answers. The start is the same one-tap start the switcher makes, in
  the thread where the question was asked, because "the model is not running, go
  and find the button" is how "I cannot select the local model" felt.
- **One name per engine, everywhere: "Local model" and "Cloud model".** The
  local engine had four names across the app — *On this phone*, *Model on this
  phone*, *MODEL ON THIS PHONE* and *on this phone* — and the cloud engine had
  *Online model*, so the same two engines were four things to read across four
  screens. Every one of those described where the answer comes from rather than
  saying what it is, and a label that explains itself is a label that has to be
  read twice. The two engines are now **Local model / Cloud model** in the
  switcher, the app-bar control, the badge on a reply, Settings, onboarding, the
  legal pages and every failure card. The provider behind the cloud engine keeps
  its own name — **Cloud provider**, which is the company you hand the key to,
  and never an engine. The Settings index is grouped under the two questions
  they answer — *What answers you* (Your context, Who answers) and *What leaves
  this phone* (What leaves this phone, Cloud provider) — with permissions below
  both.
- **The switcher sheet is a surface again.** It was opened with a transparent
  background and painted none of its own, so its tiles were drawn straight onto
  the page behind it: two near-identical creams on top of each other, which
  reads as a sheet that failed to render. Every sheet now paints its own
  background, top edge and shadow, and a chosen row is marked by an outline, a
  tick and its title as well as by its tint — so it is still obvious with the
  colour taken away.
- **The on-device model is now Bonsai-1.7B-Q1_0, not Qwen2.5-0.5B.** A 1-bit
  1.7B that is 231 MB on disk — half the download of the model it replaces and
  markedly sharper, at about the same resident size. It only works because the
  bundled engine is now llama.cpp rather than glen, which could not read the
  format at all: Q1_0 has been `GGML_TYPE_Q1_0 = 41` in stock ggml all along,
  and glen's "unknown dtype 41" was a missing case in glen.
- **The engine builds again.** `tool/build_engine_android.sh` pointed at a
  cmake toolchain file that exists in no llama.cpp release, so the cross
  compile could never have configured. It now uses the NDK's own
  `android.toolchain.cmake`, links statically — one executable has no library
  search path to get wrong on a phone — and strips the result: 187 MB of debug
  symbols down to a 13.8 MB binary.
- The CI engine job cloned nothing, ran `cargo test` on a C++ project, and
  installed a Rust toolchain it did not use. It now clones llama.cpp at the
  pinned b11574 and fetches Bonsai with its checksum.
- The bundled-engine panel in Settings starts through the same code path as the
  chat rather than carrying its own copy, which was writing the model id and
  file size of a model this build no longer ships. It also stopped telling people
  to drop a .gguf into `Android/data` by hand: there is a file picker.

### Fixed

- **The engine now starts while the app is still opening.** The complaint was
  "first token is too slow, and this model is smaller so why is it slower". It
  is not the model: measured on the phone, streaming first token is 0.46 s and
  non-streaming first byte is 23.98 s, generation is already streamed, and the
  engine is ~3.0 s from process spawn to listening. That three seconds was being
  spent *after* the question went in, because the warm-up could not begin until
  the store was open, onboarding had been checked and the permission consent had
  been resolved. It now runs first thing in `main.dart`, ahead of every one of
  those, so the model is already up while the user reads the splash — and on a
  first run the 248 MB unpack happens during onboarding, the one stretch of time
  where it costs the user nothing. Nothing waits on it: the chat is readable and
  typeable throughout.
- **A question sent before the model was ready is answered, not refused.** It
  used to ask a port that had nothing on it yet and come back "I cannot answer
  that", one second before the model would have answered. Every local turn now
  waits for a start that is already under way, and the bubble says *Starting the
  local model* while it waits — the one wait a person could otherwise mistake
  for a hang. No engine is ever silently swapped, and nothing is answered from
  the app itself.
- **Backgrounding no longer costs the engine.** Nothing stops the server on the
  way out or on ordinary navigation, so the second question of a session is as
  fast as the first. `MainActivity.onDestroy` still stops it, which is the right
  place: that only runs when the activity is genuinely going away. Coming back
  to the foreground asks for a start again if the model went away with the
  process, which is the one case where it can have died unasked.
- **The first-run unpack is honest about what it is.** Copying 248 MB out of the
  APK and waiting for the engine are two different waits, and both used to be
  reported as "0%", so the slow half looked like a frozen bar and then jumped.
  The copy is now reported as its own state with a sweeping bar and a sentence
  saying what is happening and how much — on the splash, on the engine bar, in
  the switcher and in the chat banner — and it is only reported when the platform
  says the model is not on disk yet, so a returning user is never told about a
  copy that is not happening.
- **The chat's engine banner never went away.** `ChatState.copyWith` could not
  set a field back to null, so `engineProgress: null` silently kept the last
  value and the banner above the composer went on saying the model was waking
  up long after it was answering. The engine badge now reports from the same
  state, and would have inherited the same lie.
- **`MainActivity.kt` did not compile.** A merge left `val chosen` declared
  twice in the same scope, so no APK containing the engine could have been
  built from the committed tree. Found while building the first one.
- The bundled-model panel labelled itself from the Qwen filename; it now takes
  the label from whichever model actually shipped.
- **The longest suggested question overflowed the chat on a small phone.** The
  chips holding the offered questions set their text without a bound, so on a
  320-point screen "Schedule a call with Bilal tomorrow at 3pm" drew a striped
  bar through the opening screen. Status pills in a row had the same problem with
  a long one. Both now wrap or ellipsise. Every screen the app can be on is
  checked at that width now.

## 1.5.0

Dark mode, a Today screen, and the mascot in the notification bar.

Also: Koru now explains what it wants permissions for, answers like somebody
rather than a search box, and no longer loses the client you named.

### Added

- **Dark mode.** Follows the system, including when the phone is switched while
  the app is open. The palette was a bag of constants, and a constant cannot
  have a dark mode because it does not know what it is painted on; the colours
  are resolved from the active palette now. Every dark value was chosen by
  running the contrast arithmetic, because a colour that clears 4.5:1 on cream
  fails badly on near-black and the ink colours invert completely. Both
  palettes are checked by test.
- **A Today screen.** What needs doing today: overdue, due today, happening
  today, coming up, and the projects that have gone quiet. Built on the same
  attention list the notification, the widget and the badge already use, so the
  four cannot disagree about what is urgent.
- **Haptics** on a write that lands, and a tick when switching tabs. A tap that
  changes somebody's records should be felt; the card is gone before a toast is
  read.
- **The mascot in the notification bar.** The status bar icon was Android's
  generic info dot. It is now Koru, drawn as a silhouette with the face cut out
  of it, because a tinted 24dp icon turns any filled detail into a smudge. The
  thing that speaks at you at nine in the morning is the thing that answered
  when you tapped.
- **Koru explains the permissions first.** One message covering all three,
  before the first Android dialog, because "Allow Koru to send notifications?"
  gives nobody any way to judge the answer. Calendar is now asked for as well.
  It is asked once the app is actually usable, not over the onboarding form.
- **Koru's own face while it is working.** The thinking state showed three
  dots. Dots say something is happening somewhere; the mascot says who is
  doing it, and it is still there when the answer arrives.
- **A no-AI chat that talks back.** "yes", "no", "anything else", "and him",
  "is Bilal late", "did I get paid this month" are all answered. A question that
  can be answered with yes or no now gets yes or no *and the number*, because a
  bare yes to "am I behind" is not useful.
- **Names are the names that were said.** A project called "the shop" is called
  "the shop"; it is no longer title-cased, and "for Bilal" is no longer part of
  the name.
- **Errors that are not error strings.** "database or disk is full" is for
  whoever is debugging. What a person who just tapped something needs is that it
  did not work and that trying again is reasonable.

## 1.4.0

Calendar entries can have a length, repeat, and be changed.

### Added

- **Lengths.** "for 2 hours", "for 90 minutes", "an hour and a half". A bare
  "for 2" is deliberately not read as a length: in a sentence about a meeting
  that is two o'clock far more often, and inventing a block nobody asked for is
  worse than showing an all-day entry.
- **Repeats.** Daily, weekly, fortnightly, monthly and yearly. Stored as one
  row rather than expanded into copies, because copies drift from each other
  the moment one is moved and a meeting that moved has to stay moved. Monthly
  rolls by date arithmetic and not by thirty days, so 31 January plus thirty
  days is not the right meeting.
- **Editing an entry.** It could be created and deleted but never changed, so
  the only way to fix a meeting was to delete it and say it again. There is now
  a sheet, and "move the call with Bilal to Thursday" resolves against the real
  entries and proposes a change. Moving something clears its synced flag, or the
  phone's copy would never be updated and the two calendars would disagree.
- **Replies render.** Cloud answers arrived with **bold, bullets and numbered
  steps still showing their asterisks. Bold, italics, headings, bullets,
  numbered steps and inline code are handled, and nothing else: a full markdown
  parser would also accept links and images, and a link nobody asked for is a
  worse failure on a phone than an unrendered pipe. What the user typed stays
  plain, because a stray asterisk from a price is not emphasis.
- **Reading back while an answer streams.** The view followed the bottom on
  every arriving token, so the only way to read a long answer was to wait for it
  to finish. It now follows only while you are at the bottom, and a pill
  appears when you are not.
- **Timestamps on your own messages**, inside the bubble rather than in a row
  above it. A row per message is what pushed the approval cards below the fold
  last time this was attempted.

## 1.3.0

Notifications now open something, and a release can no longer be signed with
the debug key by accident.

### Fixed

- **Tapping a notification did nothing.** The link was parsed, decoded and
  tested, and then never read: `takeLink` had no callers anywhere in the app, so
  a tap started the process and dropped the request. Which the user cannot
  distinguish from the notification never having fired. A link that was already
  waiting is taken on cold start, and one that arrives while the app is open is
  listened for; a client link opens that client's own screen.
- **Three colours failed WCAG AA for body text.** Measured: gold 2.98:1 on
  cream, `inkFaint` 3.68:1, clay 3.79:1, against 4.5:1 required. Gold was the
  worst and it marks an active client, so the least legible colour in the app
  was carrying the status people read to decide who to chase. All six text
  colours now clear 4.5:1 on both backgrounds, with a test that runs the real
  arithmetic.
- **No release could be upgraded in place.** `versionCode` sat at 2 across every
  1.x release, so Android refused every update and each new APK needed a manual
  uninstall first. Now 1.3.0+13.
- **A release signed with the debug key now fails the build** instead of
  succeeding quietly. It used to fall back so CI stayed green, which meant an
  APK called "release" could be debug-signed with nothing saying so.
- **Koru's mascot is back to how it was.** The beard and glasses are gone from
  both the generator and the fallback portrait, and the atlas, splash and crest
  were regenerated: all three are byte-identical to their pre-beard form.

### Docs

- `schemaVersion` in HANDOFF said 4; it has been 7 for several releases. The
  projects, project notes and events tables are now listed too.
- The README feature table was missing Projects and the calendar section.

### Added

- **Calendar entries.** Say "schedule a call with Bilal tomorrow at 3pm at the
  studio" in Talk and Koru shows what it understood, as it does for every
  write, and saves it when you approve. Entries have a date, a time, a place
  and can be deleted from the Business screen, where a new Calendar section
  shows the next seven days. Deadlines and entries are separate on purpose: a
  deadline has to be finished by a date, an entry happens at a time.
- **Copy to your phone calendar.** An opt-in switch in Settings, and a
  per-entry button on the Business screen. The copy is one way, the in-app
  calendar is the source of truth, and nothing is marked synced that has not
  actually landed.
- **A much wider on-device assistant.** It answers "how are you", "thanks",
  "what day is it", "what is 15% of 2000", "how much does Bilal owe" and
  "who should I chase" without a model, and it lists your calendar merged with
  what is due. The small talk varies per question and stays deterministic: the
  same question always gives the same answer, and no question reaches a model
  to do it.
- **Chat follows the answer.** The thread stays with the stream while tokens
  arrive and lands on the new turn when you send, instead of sitting still
  until the reply finishes. Replies carry their time and can be long-pressed
  to copy.

### Fixed

- **"Delete everything" now deletes everything.** Projects, project notes and
  the new calendar table were left behind, which is the one thing an app that
  promises local-only storage must not do.
- **The local model can see your projects.** They were in its facts list and
  never rendered into its brief, so it knew who owed money and nothing about
  what any of it was for.
- A `ValueNotifier` was allocated per chat bubble per rebuild and never
  disposed, and the handoff card lost its dismissed state every time the
  screen redrew.

## 1.2.1

The beard only existed on the fallback path.

### Fixed

- **Koru's beard and glasses now actually show.** They were drawn in the
  fallback vector portrait, and the sprite atlas is what renders whenever it
  decodes, which is always. So the release announced a bearded character and
  shipped the old one. The beard and the spectacles are now drawn by
  `tool/generate_assets.py`, the same script that already owned every pixel of
  the atlas, the splash and the crest, and the whole set was regenerated from it
  rather than patched as binary.

## 1.2.0

Everything on the list, finished.

### Added

- **Projects, with notes.** A Projects tab, client and personal side by side.
  Each has a target, a plan, progress and a running note. Progress is a slider
  and the reason for it is a required field, because a number with no reason is
  the confident guess the rest of this app tries not to make. Adding a note
  moves the project to the top of the list, so it never lands somewhere
  invisible.
- **The model can finally see projects.** They have been in the database since
  the schema landed and were in nothing it could read. It knew who owed money
  and nothing about what any of it was for. Now it gets the project, how far
  along it is, what done looks like and the last thing you said. The built-in
  assistant answers "what am I working on" from the same records.
- **Change and delete a client by name.** "bilal now owes 4000", "change the
  amount on acme to 3000", "delete client bilal". An edit leaves every field the
  sentence did not mention exactly as it was. A delete keeps the payments: a
  ledger that paid a client who no longer exists is history, and deleting those
  rows would quietly change totals already reported.
- **Deadlines go to your calendar.** One tap hands the event to your own
  calendar app, filled in, and you press save. It is an intent rather than a
  direct write because writing to a calendar needs a permission covering every
  calendar on the device, which is a steep ask to save one date, and it means
  the event lands in whichever calendar you actually use. Set for midday, since
  a due date is a day rather than an instant and an instant fires before you are
  awake.
- **Constrained decoding in glen.** `GLen_FORCE` makes the model open its reply
  with a required string, masked into the logits before sampling so it composes
  with temperature and top-k rather than replacing them. A 0.5B asked for
  structured output will open a brace and then write prose; that is a vocabulary
  problem, not a prompt problem.
- **Koru has a beard and glasses.** Drawn in code, so it scales and blinks
  properly.

### Fixed

- **Every save is read back before it is reported.** `apply` returning without
  throwing is not evidence: sqflite can report success for a write a constraint
  quietly discarded. Now the database is read afterwards, and a partial import
  says "I added 17 of 20" and names the three that did not go in. The app is
  held to the same rule as the model: no save is reported that has not been
  looked at.
- **Adding a model from the app works.** The import handler was written against
  the notification channel while the app asked the engine channel, so every
  attempt failed with nothing useful.

## 1.1.0

The model claimed it had saved things. It cannot have.

### Fixed

- **"Add an entry" was saved nowhere, and the app said it had been.** The
  parser knew "add a client" and nothing else, so "add an entry" fell through to
  the model. The model writes text and has no access to the database, so it
  answered from the shape of the sentence that it had done it. The chat looked
  like a receipt and the record was not there. The vocabulary now covers entry,
  record and contact, and a write that is missing the one thing it needs becomes
  the question that unblocks it rather than a guess.
- **A model can no longer claim to have saved anything.** Nothing is saved by a
  model, ever. Every record is written by the app after you approve a card, so
  any sentence saying it added, saved or logged something is false by
  construction. Replaced with what actually happened, and the phrasing that
  would have worked.
- **The on-device option admitted it was not running.** Since 1.0.0 the APK
  ships no engine and no model, so choosing it found nothing to start and
  answered from your records in a few milliseconds, which reads exactly like a
  model being fast. Settings now says so.

### Added

- **"add client 2000" asks who, instead of inventing a client called 2000.**
  Numbers are still not treated as names.

## 1.0.1

Cloud had no memory, and cloud looked slow.

### Fixed

- **The cloud model had no conversation at all.** Every request was a system
  prompt and one question, so a follow up had nothing to refer back to and "what
  does this mean" was unanswerable. Earlier turns now go out as real messages,
  with the role name each provider expects, because "koru" is an Anthropic 400
  rather than a shrug.
- **Cloud looked slower than the 0.5B on the phone.** It was one request with
  nothing shown until the whole reply arrived. The latency was never lower; it
  was just being paid silently. Cloud now streams into the reply as it arrives,
  and anything already streamed survives a timeout or a dropped connection.
- **Both prompts led with prohibitions**, and a model reads a list of never do
  this as a list of things it is unwilling to do. Asked to add a client it would
  decline. They now lead with what the app does and what it can record. The
  medical and legal line is kept, as one sentence, with ModelOutputGuard and the
  routing gate doing the real enforcement.

### Added

- **Models can be added from inside the app.** Settings, Add a model, pick the
  file. Previously the only way in was being told to open a file manager and type
  a path out of an error message.

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
