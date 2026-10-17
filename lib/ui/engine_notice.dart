import 'package:flutter/material.dart';

import '../engine.dart';
import '../theme.dart';
import '../widgets.dart';

/// The card under a reply when no engine could answer, and the one tap that
/// fixes it.
///
/// It is a card rather than a sentence in the bubble because the sentence is not
/// enough on its own. "The local model is not running" leaves somebody
/// reading it wondering whether to close the app, wait, or press something, and
/// the previous behaviour — answering from the app's own rules instead — is what
/// happens when an app says something true and then leaves the person to act on
/// it alone.
///
/// Laid out like [HandoffCard] on purpose. Both are the app saying it is not the
/// thing to talk to right now, so they share a shape: an icon, one line saying
/// what, one line saying why, and then the next step.
class KoruEngineDownCard extends StatelessWidget {
  const KoruEngineDownCard({
    super.key,
    required this.unavailable,
    required this.onFix,
  });

  final EngineUnavailable unavailable;

  /// Carries out [EngineUnavailable.actionLabel].
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      label: unavailable.text,
      child: Padding(
        padding: const EdgeInsets.only(top: KoruSpace.sml),
        child: KoruCard(
          accent: KoruTones.clay.ink,
          background: KoruTones.clay.fill,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  KoruIconBadge(
                    icon: Icons.power_settings_new_rounded,
                    color: KoruTones.clay.ink,
                    background: KoruColors.surface,
                  ),
                  const SizedBox(width: KoruSpace.md),
                  Expanded(
                    child: Text(
                      unavailable.title,
                      style: KoruType.rowTitleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: KoruSpace.md),
              Text(unavailable.detail, style: KoruType.bodySmall),
              const SizedBox(height: KoruSpace.md),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, KoruSize.buttonInCard),
                ),
                onPressed: onFix,
                icon: const Icon(Icons.arrow_forward_rounded,
                    size: KoruSize.iconSm),
                label: Text(unavailable.actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}