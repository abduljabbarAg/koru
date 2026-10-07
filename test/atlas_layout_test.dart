import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koru/mascot/mascot_clips.dart';

/// The atlas is produced by `tool/generate_assets.py` and described here. Those
/// two files have to agree, and nothing else in the build would notice if they
/// stopped agreeing: the app would simply animate the wrong frames, or read past
/// the edge of the image. So this reads the real file.
void main() {
  final atlasFile = File('assets/mascot/koru_atlas.png');

  test('the generated atlas exists', () {
    expect(atlasFile.existsSync(), isTrue,
        reason: 'run: python3 tool/generate_assets.py');
  });

  test('every clip fits inside the atlas', () {
    var index = 0;
    for (final clip in KoruClip.values) {
      index += koruClipLength(clip);
    }
    expect(index, lessThanOrEqualTo(kAtlasCapacity),
        reason: 'clips do not fit in the ${kAtlasCols}x$kAtlasRows grid');
  });

  test('every clip lands inside the atlas image', () {
    for (final clip in KoruClip.values) {
      final last = koruClipStart(clip) + koruClipLength(clip) - 1;
      final cell = koruClipCell(last);
      expect(cell.row, lessThan(kAtlasRows),
          reason: '$clip spills past the bottom of the atlas');
      expect(cell.col, lessThan(kAtlasCols),
          reason: '$clip spills past the right of the atlas');
    }
  });

  test('clips do not overlap', () {
    final starts = KoruClip.values.map(koruClipStart).toList()..sort();
    expect(starts.toSet().length, starts.length, reason: 'two clips share a start index');
    for (var i = 1; i < starts.length; i++) {
      expect(starts[i], greaterThan(starts[i - 1]));
    }
  });

  test('clips are laid out in order', () {
    var expected = 0;
    for (final clip in KoruClip.values) {
      expect(koruClipStart(clip), expected, reason: '$clip is out of order');
      expected += koruClipLength(clip);
    }
  });

  test('a frame index can be clamped instead of throwing', () {
    expect(koruClampFrame(KoruClip.idle, -5), 0);
    expect(koruClampFrame(KoruClip.idle, 999), koruClipLength(KoruClip.idle) - 1);
  });

  test('every clip has a frame time', () {
    for (final clip in KoruClip.values) {
      expect(kClipFrameMs[clip], isNotNull, reason: '$clip has no frame time');
      expect(kClipFrameMs[clip], greaterThan(0));
    }
  });

  test('only idle and think loop forever', () {
    expect(koruClipLoops(KoruClip.idle), isTrue);
    expect(koruClipLoops(KoruClip.think), isTrue);
    for (final clip in [KoruClip.blink, KoruClip.wave, KoruClip.cheer, KoruClip.greet]) {
      expect(koruClipLoops(clip), isFalse, reason: '$clip should play once');
    }
  });

  test('a blink is fast enough to read as a blink', () {
    // A blink that lingers looks like a rendering fault rather than a blink.
    final duration = koruClipLength(KoruClip.blink) * kClipFrameMs[KoruClip.blink]!;
    expect(duration, lessThan(400));
  });
}
