import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../backup.dart';
import '../cloud_providers.dart';
import '../secrets.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Backing up, restoring, clearing and deleting, together on one page.
///
/// These four are together because they are one decision in four sizes: keep
/// what is here, bring something back, throw away the conversation, throw away
/// everything. Splitting them would put the destructive one on a page of its own
/// where it is reached as easily as the safe ones and understood rather less.
class DataSettingsScreen extends ConsumerWidget {
  const DataSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Data')),
      body: KoruPagePadding(
        bottom: KoruSpace.xxl,
        child: ListView(
          children: [
            KoruCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  KoruRow(
                    leading: KoruIconBadge(
                      icon: Icons.ios_share_outlined,
                      color: KoruColors.leaf,
                      background: KoruColors.leafSoft,
                    ),
                    title: 'Back up my data',
                    subtitle: 'Saves a readable copy of your clients, payments '
                        'and deadlines',
                    onTap: () => _backup(context, ref),
                  ),
                  const Divider(height: 1),
                  KoruRow(
                    leading: KoruIconBadge(
                      icon: Icons.settings_backup_restore_rounded,
                      color: KoruColors.leaf,
                      background: KoruColors.leafSoft,
                    ),
                    title: 'Restore from a backup',
                    subtitle: 'Merges a saved file into what is already here',
                    onTap: () => _restore(context, ref),
                  ),
                  const Divider(height: 1),
                  KoruRow(
                    leading: KoruIconBadge(
                      icon: Icons.delete_sweep_outlined,
                      color: KoruColors.clay,
                      background: KoruColors.claySoft,
                    ),
                    title: 'Clear conversation',
                    subtitle: 'Keeps your profile, clients and logs',
                    onTap: () async {
                      await ref.read(chatProvider.notifier).clear();
                      if (context.mounted) toast(context, 'Conversation cleared');
                    },
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(KoruSpace.card),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: KoruColors.clay,
                        side: KoruBorders.accent(KoruColors.clay),
                      ),
                      onPressed: () => _deleteEverything(context, ref),
                      icon: const Icon(Icons.delete_outline_rounded,
                          size: KoruSize.icon),
                      label: const Text('Delete all local data'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: KoruSpace.lg),
            Text(
              'A backup is a plain JSON file, readable in any text editor, handed '
              'to Android\u2019s share sheet. Where it goes after that is your '
              'choice: nothing is uploaded on your behalf.',
              style: KoruType.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  /// Writes a backup and hands it to the share sheet.
  ///
  /// Sharing is what makes this useful rather than decorative. A file sitting in
  /// private app storage is one uninstall away from gone, and the whole
  /// promise of a local-only app is that this data matters.
  Future<void> _backup(BuildContext context, WidgetRef ref) async {
    try {
      final store = await ref.read(storeProvider.future);
      final dir = await getTemporaryDirectory();
      final file = await Backup.writeTo(store, dir);
      final path = file.path;
      if (context.mounted) toast(context, 'Backup saved');
      await Share.shareXFiles([XFile(path, mimeType: 'application/json')]);
    } catch (e) {
      if (context.mounted) toast(context, 'Could not back up: $e');
    }
  }

  /// Restores from a file the user picked.
  ///
  /// Additive on purpose. The reason anyone restores is that they lost the
  /// current data, so replacing it with an older copy would be a second loss.
  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      final path = picked?.files.single.path;
      if (path == null) return;
      final store = await ref.read(storeProvider.future);
      final report = await Backup.restore(store, await File(path).readAsString());
      ref
        ..invalidate(clientsProvider)
        ..invalidate(paymentsProvider)
        ..invalidate(receivedTotalsProvider)
        ..invalidate(openDeadlinesProvider)
        ..invalidate(guideFactsProvider);
      if (context.mounted) toast(context, report.summary);
    } on FormatException catch (e) {
      if (context.mounted) toast(context, e.message);
    } catch (e) {
      if (context.mounted) toast(context, 'Could not restore: $e');
    }
  }

  /// Clears the key too. The old version left it in memory, so "delete all local
  /// data" did not delete all of the local data.
  Future<void> _deleteEverything(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete everything?'),
        content: const Text(
            'Your profile, clients, logs, topics, drafts, conversation and your '
            'cloud key will all be removed from this device. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: KoruColors.clay),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final store = await ref.read(storeProvider.future);
    await store.wipe();
    final secrets = ref.read(secretsProvider);
    for (final provider in kCloudProviders) {
      await secrets.clearKey(provider.id);
    }

    await ref.read(chatProvider.notifier).clear();
    ref.invalidate(clientsProvider);
    ref.invalidate(paymentsProvider);
    ref.invalidate(receivedTotalsProvider);
    ref.invalidate(openDeadlinesProvider);
    ref.invalidate(packetProvider);
    ref.invalidate(cloudKeyProvider);
    ref.read(onboardedProvider.notifier).state = false;

    if (context.mounted) toast(context, 'All data deleted');
  }
}
