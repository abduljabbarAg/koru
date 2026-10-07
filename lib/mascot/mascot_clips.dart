/// Sprite atlas layout. Pure Dart with no Flutter import so it can be unit
/// tested directly, and so the frame maths can be reasoned about without a
/// rendering surface.
///
/// These constants are a mirror of `tool/generate_assets.dart`. If the atlas
/// layout changes there, it must change here too, and `test/atlas_layout_test.dart`
/// exists to make that mismatch loud.
library;

/// Logical size of one atlas cell, in pixels.
const int kCell = 192;

/// Columns in the atlas image.
const int kAtlasCols = 8;

/// Rows in the atlas image.
const int kAtlasRows = 4;

/// Named animations, each a horizontal run of frames inside the atlas.
enum KoruClip { idle, blink, wave, think, cheer, greet }

/// Frame count per clip. Must match the generator's `clips` map.
const Map<KoruClip, int> kClipFrames = {
  KoruClip.idle: 6,
  KoruClip.blink: 4,
  KoruClip.wave: 8,
  KoruClip.think: 4,
  KoruClip.cheer: 6,
  KoruClip.greet: 4,
};

/// Total frame slots the atlas provides.
const int kAtlasCapacity = kAtlasCols * kAtlasRows;

/// Index of the first frame of [clip] within the atlas.
int koruClipStart(KoruClip clip) {
  var n = 0;
  for (final c in KoruClip.values) {
    if (c == clip) break;
    n += kClipFrames[c]!;
  }
  return n;
}

/// Number of frames in [clip].
int koruClipLength(KoruClip clip) => kClipFrames[clip]!;

/// Which cell of the atlas holds global frame [index].
({int col, int row}) koruClipCell(int index) =>
    (col: index % kAtlasCols, row: index ~/ kAtlasCols);

/// Flips [frame] out of range rather than throwing, so a bad timer can never
/// take the app down.
int koruClampFrame(KoruClip clip, int frame) {
  final len = koruClipLength(clip);
  if (len <= 0) return 0;
  return frame.clamp(0, len - 1);
}

/// Playback timings, in milliseconds per frame, chosen so each clip reads at the
/// speed the motion implies. A blink has to be quick or it looks like a glitch;
/// a wave needs room to read as a wave.
const Map<KoruClip, int> kClipFrameMs = {
  KoruClip.idle: 190,
  KoruClip.blink: 55,
  KoruClip.wave: 105,
  KoruClip.think: 260,
  KoruClip.cheer: 95,
  KoruClip.greet: 130,
};

/// True when [clip] is meant to loop forever rather than return to idle.
bool koruClipLoops(KoruClip clip) =>
    clip == KoruClip.idle || clip == KoruClip.think;

/// Idle loop length in ms, used to schedule a blink relative to the breathing
/// cycle so the two never land on the same frame forever.
const int kIdleLoopMs = 6 * 190;

/// How often the mascot blinks while idle, in ms. Roughly human, and varied by
/// [kBlinkVarianceMs] so a blink does not become metronomic.
const int kBlinkEveryMs = 3400;
const int kBlinkVarianceMs = 1800;

/// Length of the idle blip that plays the moment a reply arrives.
const int kBlipMs = 2 * 190;
