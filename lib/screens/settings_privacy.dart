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
/// It used to be a card between the engine and the cloud key, which is exactly
/// the place nobody reads a privacy statement from.
class PrivacySettingsScreen extends ConsumerWidget {
  const PrivacySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packet = ref.watch(packetProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('What leaves this phone')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'When a cloud model is used, only this is sent:',
                    style: TextStyle(fontSize: 13.5, color: KoruColors.inkSoft),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: KoruColors.cream,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: KoruColors.line),
                    ),
                    child: Text(
                      packet.maybeWhen(data: (p) => p.renderForCloud(), orElse: () => '...'),
                      style: TextStyle(
                          fontSize: 12.5, color: KoruColors.ink, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Pseudonymous, not anonymous. It carries general context and '
                    'never your nickname, your name or your records.',
                    style: TextStyle(fontSize: 12.5, color: KoruColors.inkFaint, height: 1.45),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          const SectionLabel('Routing'),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Route('Faith, mental health, medical, legal', 'Cloud model'),
                  SizedBox(height: 10),
                  _Route('Everything else', 'On device'),
                  SizedBox(height: 10),
                  _Route('Crisis, diagnosis, legal ruling', 'Hand to a person'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          // The policy is the long version of this screen, so it is reachable
          // from the place where somebody is already asking the question.
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const PrivacyPolicyScreen()),
            ),
            icon: const Icon(Icons.lock_outline_rounded, size: 16),
            label: const Text('Read the full privacy policy'),
          ),
        ],
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
    return Row(
      children: [
        Expanded(
          child: Text(topic,
              style: TextStyle(fontSize: 13.5, color: KoruColors.ink)),
        ),
        Text(where,
            style: TextStyle(
                fontSize: 12.5, color: KoruColors.leaf, fontWeight: FontWeight.w700)),
      ],
    );
  }
}
