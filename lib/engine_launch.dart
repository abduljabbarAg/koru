import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'engine.dart';
import 'state.dart';

/// Starts the local model at launch, before anything else has been awaited.
///
/// The complaint this fixes is "the first token is too slow, and a smaller model
/// should not be slower". Measured on the phone, it is not the model: streaming
/// first token is 0.46 s, non-streaming first byte is 23.98 s, generation is
/// already streamed, and the engine is ~3.0 s from process spawn to listening.
/// So the work is moved rather than tuned. Three seconds the app owes nobody is
/// better spent while the user is reading onboarding than after they press send,
/// and the 248 MB first-run unpack is better spent at the one moment in a
/// session where the user has nothing else to do.
///
/// Started from `main.dart` and deliberately not awaited there. It runs beside
/// the splash, beside onboarding and beside the chat, and nothing in the UI waits
/// on it. The only thing it delays is the first question, and only for as long
/// as the engine genuinely takes.
///
/// Not gated on onboarding. [KoruEngine.parse] lands an unset or unrecognised
/// value on [KoruEngine.onDevice], which is the engine that needs no key and no
/// network, so starting it can never be wrong — and for somebody opening the app
/// for the first time, onboarding is exactly the several screens in which the
/// copy should happen.
///
/// The single owner of "start the model on my behalf". The chat screen used to
/// ask for it too, from `load()`, and that could only ever queue a second start
/// behind this one: a chat screen cannot mount before the gate has.
final engineWarmUpProvider = FutureProvider<void>((ref) async {
  await ref.read(chatProvider.notifier).warmUpEngine();
});

/// What the app does when it comes back to the foreground.
///
/// Nothing is stopped on the way out, deliberately and permanently. A stop there
/// would mean the second question of a session pays the whole of the cold start
/// again — ~3.0 s of engine spawn, plus a cold prompt prefix — for a background
/// switch somebody made for a second and undid. MainActivity.onDestroy does stop
/// the engine, and that is the right place for it: onDestroy only runs when the
/// activity is genuinely going away, not when the app is merely on the other app.
/// This app's Dart side never asks for a stop outside a deliberate model switch.
///
/// Coming back is the only moment worth acting on, because it is the only moment
/// the engine can have died without anybody asking it to: Android reclaiming the
/// process takes the server with it. Asking for a start again costs one probe
/// when the model is already up, and saves the entire wait when it is not.
void resumeLocalEngine(WidgetRef ref) {
  if (ref.read(chatProvider.notifier).engineUp) return;
  unawaited(ref.read(chatProvider.notifier).warmUpEngine());
}