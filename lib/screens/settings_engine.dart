import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'settings_cloud.dart';

/// Which model answers, and whether anything can answer at all.
///
/// Titled the same words the switcher sheet opens with, because it is the same
/// question asked in the same place: "who answers". There is no engine list and
/// no model file picker behind it any more — there is one model, and connecting
/// it is a key.
///
/// It is its own page rather than being folded into the cloud provider screen
/// because it answers a different question. That screen is "how do I give this
/// company a key"; this one is "is anything connected, and what does Koru do
/// without it", which is what somebody opening Settings to check on the app
/// wants to know.
class EngineSettingsScreen extends ConsumerWidget {
  const EngineSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = ref.watch(engineLinkProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Who answers')),
      body: KoruPagePadding(
        bottom: KoruSpace.xxl,
        child: ListView(
          children: [
            if (link == null)
              const KoruLoading(label: 'Asking what is connected')
            else
              _Connection(link: link),
            const SizedBox(height: KoruSpace.section),
            const _WhatStillWorks(),
          ],
        ),
      ),
    );
  }
}

/// The state, and the one tap that changes it.
class _Connection extends ConsumerWidget {
  const _Connection({required this.link});

  final EngineLink link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return KoruCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KoruIconBadge(
            icon: link.isConnected
                ? Icons.check_circle_rounded
                : Icons.cloud_off_rounded,
            color: link.isConnected ? KoruColors.leaf : KoruTones.gold.ink,
            background:
                link.isConnected ? KoruColors.leafSoft : KoruTones.gold.fill,
          ),
          const SizedBox(height: KoruSpace.md),
          Text(
            link.isConnected ? 'Connected' : 'Nothing is connected',
            style: KoruType.rowTitleLarge,
          ),
          const SizedBox(height: KoruSpace.xs),
          Text(
            link.isConnected
                ? '${link.provider.label} answers, on ${link.model}.'
                : link.missing,
            style: KoruType.bodySmall,
          ),
          const SizedBox(height: KoruSpace.lg),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(KoruSize.button),
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CloudSettingsScreen()),
            ),
            icon: const Icon(Icons.key_outlined, size: KoruSize.icon),
            label: Text(
              link.isConnected
                  ? 'Change the key, company or model'
                  : 'Connect a cloud model',
            ),
          ),
        ],
      ),
    );
  }
}

/// What the app does without any of this.
///
/// On the page rather than in a policy document, because "is this app useful if
/// I never give it a key" is the question behind somebody opening Settings at
/// all, and the honest answer is a list rather than a reassurance.
class _WhatStillWorks extends StatelessWidget {
  const _WhatStillWorks();

  @override
  Widget build(BuildContext context) {
    return KoruCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('With no model connected', style: KoruType.rowTitleLarge),
          const SizedBox(height: KoruSpace.xs),
          Text(
            'Your clients, your money, your deadlines, your calendar, your '
            'projects and your backups all work exactly as they do now, and '
            'nothing about them leaves the phone.',
            style: KoruType.bodySmall,
          ),
          const SizedBox(height: KoruSpace.md),
          Text(
            'What you cannot do is type a sentence and have Koru turn it into a '
            'record, or ask it a question about your work. It will say so '
            'rather than answer from your records with no model behind it.',
            style: KoruType.bodySmall,
          ),
        ],
      ),
    );
  }
}