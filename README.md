# Koru

A local-first personal AI companion for Android. It knows your work, your
training and your goals, and it runs on your phone.

Koru is built around one rule: **your life is not training data for anyone else.**
Questions about your work, your training and your goals are answered on the
device. Only questions that genuinely need a frontier model are sent upstream,
and even then a pseudonymous summary goes with them, never your name.

The name is the koru: the unfurling fern frond that is a Māori symbol for new
growth. He is also the app icon, the splash screen, and the character in the
chat bar who blinks, thinks and waves when you tap him.

## What it does

| Tab | What it is for |
| --- | --- |
| Talk | Ask questions. Business, training and goals are answered on device. |
| Business | Clients, amounts, due dates, status, payment capture, overdue flags. |
| Fitness | Weight and measurements, with a real trend rather than a single number. |
| Learn | Topics you are working through, with progress. |
| Settings | Edit your context, manage the cloud key, export or delete everything. |

## How routing works

There is no user-facing routing configuration. The rule is fixed in
`lib/packet.dart` and shown in Settings so you can see what it does:

- **Faith, mental health, medical, legal** goes to a frontier model (OpenRouter).
- **Everything else** is answered on the device by `lib/local/local_assistant.dart`.
- **Crisis, diagnosis, legal ruling** stops the model entirely and shows a card
  with named services and emergency numbers.

The on-device assistant is a deterministic responder, not a language model, and
the UI says so. It answers from your own records: your weight and its trend, your
client pipeline and what is unpaid, your goals. That is the class of question a
memory-based companion should be good at, and answering it locally is what makes
the privacy claim true rather than aspirational.

## Privacy

- Profile, clients, measurements, topics, drafts and chat live in a private
  SQLite database in the app's own directory.
- The cloud API key is encrypted with an AES key held in the **Android
  Keystore** and never leaves it (`lib/secrets.dart`,
  `MainActivity.kt`). What is written to SharedPreferences is ciphertext.
- The nickname is never included in anything sent to a cloud model. Onboarding
  promises that, and `test/packet_test.dart` fails if it stops being true.
- "Delete all local data" removes the database **and** the cloud key.
- No analytics, no crash reporting, no accounts, no ads.

## Building

Requires the Flutter SDK (3.24 or newer) and a JDK 17 toolchain.

```bash
flutter pub get
flutter test          # unit, store and widget tests
flutter analyze       # lints are configured to fail on dead code
flutter run           # on a connected device
flutter build apk --release --split-per-abi
```

Release signing is opt-in. Create `android/key.properties` with
`storeFile`, `storePassword`, `keyAlias` and `keyPassword`; without it the
release build falls back to the debug key, which is fine for CI artifacts but not
for anything you publish.

## Assets

The mascot sprite atlas, the splash illustration, the launcher icons and the
Android launch crest are all generated from code:

```bash
python3 tool/generate_assets.py      # writes assets/ and android/.../res/
python3 tool/preview_frames.py        # writes /tmp/koru_preview.png for review
```

Standard library only, no dependencies, about 15 seconds. The generated PNGs are
committed so a fresh checkout builds with one command, but every pixel is
reproducible from `tool/generate_assets.py` rather than arriving as an opaque
binary.

The atlas layout is described in `lib/mascot/mascot_clips.dart` and mirrored by
the generator. `test/atlas_layout_test.dart` reads the real PNG and fails if the
two ever disagree.

## Project layout

```
lib/
  main.dart              app shell, animated splash, tab navigation
  packet.dart            context packet, routing rules, prompt building
  handoff.dart           human escalation: what "step aside" actually means
  cloud.dart             frontier model call, typed results
  local/local_assistant.dart   the on-device responder
  store.dart             SQLite schema and every query
  models.dart            domain types
  secrets.dart           keystore-backed key storage
  state.dart             Riverpod providers
  mascot/                sprite engine, animation state machine, vector fallback
  screens/               chat, business, fitness, knowledge, drafts, settings
tool/
  generate_assets.py     draws every shipped PNG
  preview_frames.py      labelled contact sheet for reviewing frames
```

## Licence

MIT. See `LICENSE`.
