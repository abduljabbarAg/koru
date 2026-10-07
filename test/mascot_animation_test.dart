import 'package:flutter_test/flutter_test.dart';
import 'package:koru/mascot/mascot_animation.dart';
import 'package:koru/mascot/mascot_clips.dart';

/// The animator takes time as a parameter rather than reading a clock, so the
/// whole state machine can be stepped by hand.
void main() {
  late KoruAnimator a;

  setUp(() => a = KoruAnimator(seed: 7)..start(0));

  test('starts idle on frame zero', () {
    expect(a.clipAt(0), KoruClip.idle);
    expect(a.frameAt(KoruClip.idle, 0), 0);
    expect(a.oneShot, isNull);
    expect(a.busy, isFalse);
  });

  test('idle loops through its frames and wraps', () {
    final length = koruClipLength(KoruClip.idle);
    final step = kClipFrameMs[KoruClip.idle]!;
    for (var i = 0; i < length; i++) {
      expect(a.frameAt(KoruClip.idle, i * step), i);
    }
    expect(a.frameAt(KoruClip.idle, length * step), 0);
  });

  test('time before the start does not produce a negative frame', () {
    expect(a.frameAt(KoruClip.idle, -500), 0);
  });

  test('busy pins the mascot to thinking', () {
    expect(a.setBusy(true, 100), isTrue);
    expect(a.clipAt(100), KoruClip.think);
    expect(a.loop, KoruClip.think);
  });

  test('setting busy to the same value changes nothing', () {
    expect(a.setBusy(true, 0), isTrue);
    expect(a.setBusy(true, 10), isFalse);
  });

  test('clearing busy returns to idle', () {
    a.setBusy(true, 0);
    expect(a.setBusy(false, 500), isTrue);
    expect(a.clipAt(500), KoruClip.idle);
    expect(a.busy, isFalse);
  });

  test('a one-shot plays once then hands control back', () {
    a.wave(0);
    expect(a.oneShot, KoruClip.wave);

    final duration = KoruAnimator.clipDurationMs(KoruClip.wave);
    expect(a.clipAt(duration - 1), KoruClip.wave);
    expect(a.clipAt(duration), KoruClip.idle);
    expect(a.oneShot, isNull);
  });

  test('a one-shot outranks thinking', () {
    a.setBusy(true, 0);
    a.cheer(100);
    expect(a.clipAt(100), KoruClip.cheer);
  });

  test('going busy again drops a running one-shot', () {
    a.wave(0);
    a.setBusy(true, 10);
    expect(a.oneShot, isNull);
    expect(a.clipAt(10), KoruClip.think);
  });

  test('restarting the same one-shot is a no-op', () {
    expect(a.wave(0), isTrue);
    expect(a.wave(100), isFalse, reason: 'would visibly stutter mid-swing');
  });

  test('a newer one-shot replaces an older one', () {
    a.wave(0);
    a.cheer(10);
    expect(a.oneShot, KoruClip.cheer);
  });

  test('frames stay inside the clip while a one-shot runs', () {
    a.greet(0);
    final step = kClipFrameMs[KoruClip.greet]!;
    final length = koruClipLength(KoruClip.greet);
    for (var i = 0; i < length; i++) {
      expect(a.frameAt(KoruClip.greet, i * step), i);
    }
  });

  test('the mascot blinks on its own while idle', () {
    // Somewhere inside two blink intervals there has to be a blink, otherwise the
    // character looks like a sticker.
    var blinked = false;
    for (var t = 0; t < kBlinkEveryMs + kBlinkVarianceMs; t += 20) {
      if (a.clipAt(t) == KoruClip.blink) {
        blinked = true;
        break;
      }
    }
    expect(blinked, isTrue, reason: 'no blink fired within one interval');
  });

  test('blinking does not happen while thinking', () {
    a.setBusy(true, 0);
    for (var t = 0; t < kBlinkEveryMs + kBlinkVarianceMs; t += 20) {
      expect(a.clipAt(t), isNot(KoruClip.blink));
    }
  });

  test('a blink never interrupts another one-shot', () {
    a.wave(0);
    final step = 10;
    final end = KoruAnimator.clipDurationMs(KoruClip.wave);
    for (var t = 0; t < end; t += step) {
      expect(a.clipAt(t), KoruClip.wave);
    }
  });

  test('two blinks are not metronomic', () {
    // Consecutive blink start times must differ, otherwise the character blinks
    // like a metronome and reads as mechanical.
    final times = <int>[];
    var t = 0;
    for (var i = 0; i < 20000; i += 10) {
      if (a.clipAt(t) == KoruClip.blink && (times.isEmpty || t > times.last)) {
        times.add(t);
        t += KoruAnimator.clipDurationMs(KoruClip.blink);
      }
    }
    expect(times.length, greaterThan(2));
    final gaps = <int>[];
    for (var i = 1; i < times.length; i++) {
      gaps.add(times[i] - times[i - 1]);
    }
    expect(gaps.toSet().length, greaterThan(1), reason: 'blink cadence never varies');
  });

  test('isSettled reports when the one-shot has finished', () {
    a.greet(0);
    expect(a.isSettled(0), isFalse);
    expect(a.isSettled(KoruAnimator.clipDurationMs(KoruClip.greet) + 1), isTrue);
  });

  test('idle is idempotent', () {
    expect(a.idle(0), isFalse, reason: 'already idle, nothing to do');
    a.setBusy(true, 0);
    expect(a.idle(100), isTrue);
  });

  test('atlas index stays inside the image', () {
    for (var t = 0; t < 8000; t += 37) {
      a.greet(t);
      expect(a.atlasIndexAt(t), lessThan(kAtlasCapacity));
      expect(a.atlasIndexAt(t), greaterThanOrEqualTo(0));
    }
  });

  test('start is only honoured once', () {
    final b = KoruAnimator()..start(1000);
    b.start(0);
    expect(b.frameAt(KoruClip.idle, 0), 0,
        reason: 'a late start call must not rewind the timeline');
  });
}
