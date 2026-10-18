import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../backup.dart';
import '../cloud_providers.dart';
import '../file_save.dart';
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
              'A backup is a plain JSON file, readable in any text editor. '
              'Save it to this phone\u2019s Downloads, or share it somewhere '
              'else \u2014 either way nothing is uploaded on your behalf.',
              style: KoruType.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  /// Writes a backup, then asks where it should go.
  ///
  /// Two destinations, because they answer different worries. Saving to the
  /// phone is what somebody does before reinstalling; sharing is what they do
  /// to get the file off the device entirely. Sharing was the only option
  /// before, which meant the user's own phone was the one place a backup could
  /// not go without another app in the middle.
  Future<void> _backup(BuildContext context, WidgetRef ref) async {
    try {
      final store = await ref.read(storeProvider.future);
      final dir = await getTemporaryDirectory();
      final file = await Backup.writeTo(store, dir);
      final path = file.path;
      final name = file.uri.pathSegments.last;
      if (!context.mounted) return;

      final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  KoruSpace.card,
                  0,
                  KoruSpace.card,
                  KoruSpace.sm,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Your backup is ready',
                    style: KoruType.rowTitle,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.download_rounded),
                title: const Text('Save to this phone'),
                subtitle: const Text('Lands in Downloads, stays there'),
                onTap: () => Navigator.pop(ctx, 'save'),
              ),
              ListTile(
                leading: const Icon(Icons.ios_share_outlined),
                title: const Text('Share'),
                subtitle: const Text('Email, drive, anywhere else'),
                onTap: () => Navigator.pop(ctx, 'share'),
              ),
              const SizedBox(height: KoruSpace.sm),
            ],
          ),
        ),
      );

      if (choice == 'save') {
        final content = await file.readAsString();
        final saved = await const FileSave().saveToDownloads(name, content);
        if (!context.mounted) return;
        toast(context, saved == null
            ? 'Could not save the file'
            : 'Saved to $saved');
      } else if (choice == 'share') {
        await Share.shareXFiles([XFile(path, mimeType: 'application/json')]);
      }
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
