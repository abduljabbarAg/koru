# Koru

A local-first business buddy for freelancers, on Android. It knows your clients,
what they owe you and what is due, and it runs on your phone.

Koru is built around one rule: **your clients and your money are not training
data for anyone else.** Everything it keeps — clients, money owed, deadlines,
the calendar, projects, tasks, backups — is in a private database on the phone
and works with the network off. The one thing that needs the network is Koru's
own answers, and those go to the cloud model you connect yourself with a
pseudonymous summary attached, never your name.

The loop it exists for is: **clients, what is owed, what is due, and money
received.** It started as a general life companion with fitness and learning
tracks, and those were cut because breadth had produced shallow features nobody
used and a mascot that talked about body measurements instead of invoices.

The name is the koru: the unfurling fern frond that is a Māori symbol for new
growth. He is also the app icon, the splash screen, and the character in the
chat bar who blinks, thinks and waves when you tap him.

## What it does

| Tab | What it is for |
| --- | --- |
| Talk | Ask questions, and say things like "add client Bilal for 2000". |
| Business | Clients, balances, deadlines, the calendar, the pipeline, and a capacity meter. |
| Projects | Client and personal work, each with a target, progress and a running note. |
| Settings | Currency, client capacity, the cloud key, backup and deletion. |

Fitness, learning and drafts were removed. Each existed with zero writers, so
the drafts screen showed nothing forever. The tables survive for older installs
and are still cleared by "delete everything"; the features are gone.

## How routing works

There is no user-facing routing configuration. The rule is fixed in
`lib/packet.dart` and shown in Settings so you can see what it does:

- **Everything else** is asked of the cloud model you connected.
- **Crisis, diagnosis, legal ruling** stops the model entirely and shows a card
  with named services and emergency numbers.

There is one model and it is online. The bundled 1.7B model that used to ship in
the APK is gone: it took the package from 16 MB to 258 MB, and every complaint
reported about the assistant — talking about a client instead of answering,
inventing exchange rates, repeating itself, thirteen seconds for forty tokens —
was that model. A rules-based responder stood in for it when it was not running,
and that was worse: it answered in milliseconds and read exactly like a fast
model. So there is no fallback any more. With nothing connected, Koru says so and
offers the tap that connects one.

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
  cloud.dart             the model call, typed results
  engine.dart            the one engine, whether it is connected, the output guards
  store.dart             SQLite access; schema.dart is the migration history
  schema.dart            every migration, in order
  models.dart            domain types
  secrets.dart           keystore-backed key storage
  state.dart             Riverpod providers
  mascot/                sprite engine, animation state machine, vector fallback
  screens/               chat, work, clients, revenue, settings
tool/
  generate_assets.py     draws every shipped PNG
  preview_frames.py      labelled contact sheet for reviewing frames
```

## Licence

MIT. See `LICENSE`.
