import 'dart:math' as math;

import 'mascot_clips.dart';

/// Decides which frame the mascot shows at a given moment.
///
/// Deliberately free of Flutter imports and of its own clock: every method takes
/// `now` in milliseconds, so the whole state machine is unit testable by
/// stepping time forward. The widget is then a thin renderer over this.
///
/// The model is the one that makes a character feel alive rather than looped:
/// a long idle breathe, an occasional blink that does not fall on a fixed
/// cadence, and one-shot clips that interrupt the loop and hand control back.
class KoruAnimator {
  final math.Random _random = math.Random();

  KoruClip _loop = KoruClip.idle;
  int _loopStartMs = 0;

  KoruClip? _once;
  int _onceStartMs = 0;
  int _onceLengthMs = 0;

  int _nextBlinkAtMs = 0;
  bool _busy = false;

  bool _started = false;

  /// True while a request is outstanding, which pins the mascot to the thinking
  /// clip so the user always has a visible reason for the wait.
  bool get busy => _busy;

  /// The clip that owns the long-running loop right now.
  KoruClip get loop => _loop;

  /// The one-shot clip currently interrupting the loop, if any.
  KoruClip? get oneShot => _once;

  /// Starts the timeline at [now].
  void start(int now) {
    if (_started) return;
    _started = true;
    _loop = KoruClip.idle;
    _loopStartMs = now;
    _nextBlinkAtMs = now + _nextBlinkDelay();
  }

  int _nextBlinkDelay() =>
      kBlinkEveryMs + _random.nextInt(kBlinkVarianceMs);

  /// Tells the mascot a request is in flight. Returns true if anything changed,
  /// so callers can skip a redundant rebuild.
  bool setBusy(bool value, int now) {
    start(now);
    if (_busy == value) return false;
    _busy = value;
    // A one-shot greeting should not outlive the switch into thinking.
    _once = null;
    _loop = value ? KoruClip.think : KoruClip.idle;
    _loopStartMs = now;
    if (!value) _nextBlinkAtMs = now + _nextBlinkDelay();
    return true;
  }

  /// Interrupts the loop with a clip that plays once and then returns.
  ///
  /// A new one-shot always wins, otherwise a wave triggered while the mascot is
  /// already waving would restart mid-swing and look like a stutter.
  bool play(KoruClip clip, int now) {
    start(now);
    if (!koruClipLoops(clip)) {
      if (_once == clip) return false;
      _once = clip;
      _onceStartMs = now;
      _onceLengthMs = koruClipLength(clip) * kClipFrameMs[clip]!;
      return true;
    }
    if (_loop == clip) return false;
    _loop = clip;
    _loopStartMs = now;
    return true;
  }

  /// Convenience wrappers for the three moments that matter.
  bool greet(int now) => play(KoruClip.greet, now);
  bool cheer(int now) => play(KoruClip.cheer, now);
  bool wave(int now) => play(KoruClip.wave, now);

  /// Returns to the plain idle loop.
  bool idle(int now) {
    start(now);
    if (!_busy && _loop == KoruClip.idle && _once == null) return false;
    _once = null;
    _loop = _busy ? KoruClip.think : KoruClip.idle;
    _loopStartMs = now;
    return true;
  }

  /// Current clip at [now], advancing the timeline first.
  KoruClip clipAt(int now) {
    _advance(now);
    return _once ?? _loop;
  }

  /// Current frame within [clip] at [now].
  int frameAt(KoruClip clip, int now) {
    _advance(now);
    if (_once == clip) {
      final elapsed = now - _onceStartMs;
      if (elapsed < 0) return 0;
      return koruClampFrame(clip, elapsed ~/ kClipFrameMs[clip]!);
    }
    final elapsed = now - _loopStartMs;
    if (elapsed < 0) return 0;
    final len = koruClipLength(clip);
    if (len == 0) return 0;
    return (elapsed ~/ kClipFrameMs[clip]!) % len;
  }

  /// Total atlas index for the frame shown at [now].
  int atlasIndexAt(int now) {
    final clip = clipAt(now);
    return koruClipStart(clip) + frameAt(clip, now);
  }

  void _advance(int now) {
    start(now);

    if (_once != null) {
      if (now - _onceStartMs >= _onceLengthMs) _once = null;
      return; // never blink over the top of a one-shot
    }

    if (!_busy && now >= _nextBlinkAtMs) {
      _once = KoruClip.blink;
      _onceStartMs = now;
      _onceLengthMs = koruClipLength(KoruClip.blink) * kClipFrameMs[KoruClip.blink]!;
      _nextBlinkAtMs = now + _nextBlinkDelay();
    }
  }

  /// True once the mascot has finished a one-shot and settled, which the chat
  /// screen uses to decide whether the idle blip is still worth playing.
  bool isSettled(int now) {
    _advance(now);
    return _once == null;
  }

  /// Total length of a one-shot clip in ms, for callers that want to schedule
  /// something after the animation rather than guessing.
  static int clipDurationMs(KoruClip clip) =>
      koruClipLength(clip) * kClipFrameMs[clip]!;
}
