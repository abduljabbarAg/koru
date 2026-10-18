import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state.dart';
import '../widgets.dart';
import 'engine_sheet.dart';

/// The engine control in the chat's app bar.
///
/// It lives here rather than in `ui/thread.dart` because everything in `ui/`
/// knows no providers — the widget itself is [KoruEngineBarButton], a piece of
/// type and colour — and this is the part that has to know what the store says
/// and what the keystore holds.
///
/// The detail line is the reason this is a bar control and not a pill. "CLOUD
/// MODEL" tells somebody that something is answering; "OpenRouter" tells them
/// who, and that is the question behind the complaint this was built for. When
/// nothing is connected it says that in the same place, rather than showing an
/// engine that is not there.
class EngineBarControl extends ConsumerWidget {
  const EngineBarControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = ref.watch(engineLinkProvider).valueOrNull;

    // Null while the store and the keystore are being asked, which is
    // deliberately not read as "nothing is connected": a brief flash of a state
    // that is not true is worse than an absent detail line for a frame.
    if (link == null) {
      return const KoruEngineBarButton(
        title: '',
        detail: null,
        onTap: _noop,
      );
    }

    return KoruEngineBarButton(
      title: link.label,
      detail: link.isConnected ? link.model : null,
      connected: link.isConnected,
      onTap: () => showEngineSwitcher(context),
    );
  }

  /// Placeholder tap while the link is still being read. The control is a
  /// button, so it has to behave like one; opening a sheet that would then say
  /// the same thing is noise.
  static void _noop() {}
}