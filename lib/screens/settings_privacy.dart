import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'legal.dart';

/// The one screen that answers "what leaves this phone", and where a question
/// goes once it leaves.
///
/// Kept as its own page because this is the claim the rest of the app rests on.
/// It used to be a card between the engine picker and the cloud key, which is
/// exactly the place nobody reads a privacy statement from.
///
/// The table below says where a question goes and nothing about companies, so
/// the two never collide here: which company serves the model is one page away
/// under Cloud provider.
class PrivacySettingsScreen extends ConsumerWidget {
  const PrivacySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packet = ref.watch(packetProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('What leaves this phone')),
      body: KoruPagePadding(
        bottom: KoruSpace.xxl,
        child: ListView(
          children: [
            KoruCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'When Koru asks a model, only this is sent:',
                    style: KoruType.bodyCompactStrong,
                  ),
                  const SizedBox(height: KoruSpace.sml),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(KoruSpace.md),
                    decoration: BoxDecoration(
                      color: KoruColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(KoruRadius.xs),
                      border: Border.fromBorderSide(KoruBorders.hairline()),
                    ),
                    child: Text(
                      packet.maybeWhen(
                        data: (p) => p.renderForCloud(),
                        orElse: () => '...',
                      ),
                      style: KoruType.mono,
                    ),
                  ),
                  const SizedBox(height: KoruSpace.md),
                  Text(
                    'Pseudonymous, not anonymous. It carries general context and '
                    'never your nickname, your name or your records.',
                    style: KoruType.bodySmall,
                  ),
                ],
              ),
            ),
            const KoruSection(
              label: 'Routing',
              children: [
                _Route('Everything else', 'The cloud model you connected'),
                _Route('Faith, mental health, medical, legal', 'The same model'),
                _Route('Crisis, diagnosis, legal ruling', 'Hand to a person'),
                _Route('No model connected', 'Nothing is sent'),
              ],
            ),
            // The policy is the long version of this screen, so it is reachable
            // from the place where somebody is already asking the question.
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const PrivacyPolicyScreen()),
              ),
              icon: const Icon(Icons.lock_outline_rounded,
                size: KoruSize.iconSm),
              label: const Text('Read the full privacy policy'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row of the routing table: what kind of question, and where it goes.
class _Route extends StatelessWidget {
  const _Route(this.topic, this.where);

  final String topic;
  final String where;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KoruSpace.row,
        vertical: KoruSpace.mdl,
      ),
      child: Row(
        children: [
          Expanded(child: Text(topic, style: KoruType.bodyCompactStrong)),
          Text(
            where,
            style: KoruType.meta.copyWith(
              color: KoruColors.leaf,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}