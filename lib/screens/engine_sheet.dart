import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cloud_providers.dart';
import '../engine.dart';
import '../engine_switch.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'settings_cloud.dart';

/// Opens the switcher that the engine control in the app bar opens.
///
/// Titled "Who answers" rather than "Settings" on purpose, and the same words
/// the Settings index uses for the same page: the person tapping it wants to
/// change this, not go somewhere. Everything it writes goes through
/// [selectCloudProvider], so Settings and the chat cannot end up showing
/// different providers.
Future<void> showEngineSwitcher(BuildContext context) {
  return showKoruSheet<void>(
    context,
    title: 'Who answers',
    subtitle: 'One model, over the internet. Koru needs a key for it, and the '
        'key stays on this phone.',
    builder: (_) => const _CloudSwitcher(),
  );
}

/// The one honest question, and the list that answers it.
///
/// There is no list of engines here any more, because there is no choice. What
/// is left to choose is which company answers, and whether anything is
/// connected at all — and the sheet leads with that state rather than making
/// somebody work it out from a list of companies with no tick on any of them.
class _CloudSwitcher extends ConsumerWidget {
  const _CloudSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = ref.watch(engineLinkProvider).valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (link == null)
          const KoruLoading(label: 'Asking what is connected')
        else ...[
          _ConnectionCard(link: link),
          const SizedBox(height: KoruSpace.md),
          Text(
            'Which company answers online. The key for each one is kept '
            'separately, so switching does not need a new key.',
            style: KoruType.caption.copyWith(height: 1.45),
          ),
          const SizedBox(height: KoruSpace.md),
          for (final provider in kCloudProviders)
            _ProviderTile(provider, link.provider.id),
          // Said where the choice is made rather than buried in a privacy policy.
          const SizedBox(height: KoruSpace.xs),
          Text(
            'Anything about a crisis, a diagnosis or a court date goes to a '
            'person instead, whatever company you pick.',
            style: KoruType.caption.copyWith(height: 1.45),
          ),
        ],
      ],
    );
  }
}

/// What is answering, said plainly, with the tap that changes it.
///
/// A fresh install and every install that never added a key land here, so this
/// card is not an error state — it is the first thing a new user sees, and it
/// has to read as "here is the one thing to do" rather than as a failure.
class _ConnectionCard extends ConsumerWidget {
  const _ConnectionCard({required this.link});

  final EngineLink link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (link.isConnected) {
      return KoruNotice(
        title: 'Connected',
        message: '${link.provider.label} is answering, on ${link.model}. '
            'Everything you type that needs a model goes there, and the card it '
            'shows you is saved only when you say so.',
        icon: Icons.check_circle_rounded,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KoruNotice(
          title: 'Nothing is connected',
          message: 'Koru can keep your clients, your money and your calendar '
              'without any of this — but it cannot turn what you type into a '
              'record until a model is connected. Pick a company below and add '
              'its key.',
          icon: Icons.cloud_off_rounded,
          tone: KoruTones.gold,
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(KoruSize.buttonInCard),
          ),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const CloudSettingsScreen()),
          ),
          icon: const Icon(Icons.key_outlined, size: KoruSize.icon),
          label: const Text('Add a key'),
        ),
      ],
    );
  }
}

class _ProviderTile extends ConsumerWidget {
  const _ProviderTile(this.provider, this.currentId);

  final CloudProvider provider;
  final String currentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Whether this provider already has a key, so the list can mark the ones
    // that could answer right now. Twenty reads of the keystore is cheap next to
    // a question that comes back as "add a key first" for the third time.
    final hasKey =
        ref.watch(cloudKeyProvider(provider.id)).valueOrNull?.isNotEmpty ?? false;
    return KoruSelectableTile(
      label: provider.label,
      blurb: provider.note ??
          '${provider.models.length} model'
              '${provider.models.length == 1 ? '' : 's'} available',
      selected: currentId == provider.id,
      icon: Icons.cloud_outlined,
      trailing: hasKey
          ? KoruPill(
              label: 'KEY SAVED',
              color: KoruColors.leaf,
              background: KoruColors.leafSoft,
            )
          : null,
      onTap: () async {
        await selectCloudProvider(ref, provider.id);
        if (!context.mounted) return;
        // Only pushed for when the new company has no key: a tap on a company
        // that can already answer should not interrupt with a form.
        if (hasKey) {
          Navigator.of(context).pop();
          return;
        }
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const CloudSettingsScreen()),
        );
      },
    );
  }
}