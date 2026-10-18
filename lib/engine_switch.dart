/// The one place a provider is chosen.
///
/// The switcher sheet in the chat and the Settings pickers both call this. They
/// used to each write the store and invalidate the providers itself, which is
/// exactly how two screens end up disagreeing about which company answers: one
/// wrote and forgot to invalidate, or invalidated a provider the other had
/// already read. There is one write and one invalidation per choice now, and
/// every caller goes through it.
///
/// Nothing here chooses an *engine*. There is one, it is the cloud model, and
/// the only decision left about it is the key.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cloud_providers.dart';
import 'state.dart';

/// Switches the cloud provider, and the model that goes with it.
///
/// The model follows only when the stored one is not one the new provider
/// offers: a provider's own list is what the provider will accept, and sending
/// it a model from a different house is a 404 dressed as a broken key. A model
/// the new provider does offer is left alone, because somebody who chose
/// `gpt-4o-mini` over `gpt-4o` on purpose should not have it overwritten by a
/// switch of company.
Future<void> selectCloudProvider(WidgetRef ref, String providerId) async {
  final store = await ref.read(storeProvider.future);
  final provider = providerById(providerId);
  await store.put('cloud_provider', provider.id);

  final model = await store.get('cloud_model');
  if (model == null || model.isEmpty || !provider.models.contains(model)) {
    if (provider.models.isNotEmpty) {
      await store.put('cloud_model', provider.models.first);
    }
  }
  ref.invalidate(cloudSelectionProvider);
  ref.invalidate(engineLinkProvider);
}