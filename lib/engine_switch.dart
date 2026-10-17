/// The one place an engine, a provider or a model is chosen.
///
/// The chat's switcher and the Settings pickers both call these. They used to
/// each write the store and invalidate the providers itself, which is exactly
/// how two screens end up disagreeing about which engine is running: one wrote
/// and forgot to invalidate, or invalidated a provider the other had already
/// read. There is one write and one invalidation per choice now, and every
/// caller goes through it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cloud_providers.dart';
import 'engine.dart';
import 'local/bundled_engine.dart';
import 'state.dart';

/// Switches which engine answers.
///
/// Same write the Settings picker has always done, so the two cannot drift, and
/// the chat reads the same key the moment the write lands.
Future<void> selectEngine(WidgetRef ref, KoruEngine engine) async {
  final store = await ref.read(storeProvider.future);
  await store.put('engine', engine.name);
  ref.invalidate(engineProvider);
}

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
}

/// Points the engine at one of the .gguf files this app can see.
///
/// The bundled model is stored as an empty path rather than as its own path.
/// That is what the launcher reads to decide between "start the default" and
/// "start this file", so writing the bundled path would work today and break the
/// day the bundled file is unpacked somewhere else.
Future<void> selectLocalModel(WidgetRef ref, LocalModelFile model) async {
  final store = await ref.read(storeProvider.future);
  await store.put('model_path', isBundledModel(model) ? '' : model.path);
  ref.invalidate(chosenModelProvider);
}

/// Whether this row is the model that ships inside the app.
///
/// The platform lists it first and marks it "(bundled)". The old name is also
/// checked, because an install from before the rename still has that file on
/// disk and still offers it, and a label that no longer says "bundled" must not
/// be able to turn the default into a chosen file.
bool isBundledModel(LocalModelFile model) =>
    model.label.contains('(bundled)') ||
    model.label.startsWith(BundledEngine.bundledModelId) ||
    model.label.startsWith('Qwen2.5');