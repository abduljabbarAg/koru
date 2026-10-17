import 'attention_bridge.dart';

/// How a person answered the permission explanation.
///
/// Three states rather than the one boolean this replaces. The boolean could not
/// tell apart somebody who said no from somebody who was never shown the screen,
/// and those two need opposite treatment: one must be left alone, the other must
/// be asked. Collapsing them into "asked" is what let the screen stay hidden
/// from every user who had upgraded.
enum ConsentOutcome {
  /// Has never answered the explanation.
  ///
  /// This is also what an upgrade from the older release resolves to, on
  /// purpose. Those users were prompted once by a snackbar that appeared four
  /// seconds after launch and was covered by the system dialog it was meant to
  /// explain. They were asked, but they were never shown anything they could
  /// read, so recording them as having answered would suppress a screen they
  /// have genuinely never seen.
  notAsked,

  /// Went through the explanation and let the prompts be raised.
  granted,

  /// Read it and said not now.
  ///
  /// A real answer rather than a failure to answer, and treated as one: it is
  /// never re-asked at launch. Settings is where a changed mind goes, because
  /// the whole promise of a skippable screen is that skipping is allowed.
  declined,
}

/// Where the answer is kept.
///
/// A separate key from the flag the previous release wrote. That key cannot be
/// reused: it already means two different things depending on which release set
/// it, and it is left exactly where it is so an older build reading this store
/// still finds what it expects.
const permissionConsentKey = 'permission_consent';

/// The flag the previous release wrote, read once and never written again.
///
/// Kept because the older builds in the wild still read it, and because deleting
/// a key that means something to other code is how a downgrade silently changes
/// what an install does. It is deliberately not consulted to suppress anything.
const legacyAskedPermissionsKey = 'asked_permissions';

/// Whether the permission explanation still owes this person a look.
///
/// Pure and synchronous so the decision can be tested without a store, a
/// platform or a widget. The wrong signal this replaces was not a small mistake:
/// every upgrading user carries it set, so the screen could never appear for
/// them, and the reported symptom was "permissions don't ask".
class PermissionConsent {
  const PermissionConsent({
    required this.outcome,
    required this.health,
    required this.calendarGranted,
  });

  /// What has actually been granted, or not.
  final KoruHealth health;

  final bool calendarGranted;

  final ConsentOutcome outcome;

  /// Nothing to offer, whatever the store says.
  ///
  /// Used before onboarding, where the explanation is the wrong screen: somebody
  /// who has not entered a nickname yet is not being asked for notifications by
  /// a half-built app, and the onboarding flow is what introduces itself. Stated
  /// here rather than assembled at the call site so the "pretend it is all
  /// granted" trick is named once and has a reason.
  static const PermissionConsent nothingToAskAbout = PermissionConsent(
    outcome: ConsentOutcome.granted,
    health: KoruHealth(notifications: true, batteryExempt: true),
    calendarGranted: true,
  );

  /// Builds the decision from what is on disk and what the system says.
  ///
  /// [values] is the store's whole contents, read in one call rather than three
  /// so the decision cannot be taken against a half-read store.
  factory PermissionConsent.fromStore(
    Map<String, String> values, {
    required KoruHealth health,
    required bool calendarGranted,
  }) {
    return PermissionConsent(
      outcome: parseOutcome(values[permissionConsentKey]),
      health: health,
      calendarGranted: calendarGranted,
    );
  }

  /// Reads the recorded answer, treating anything unrecognised as "not asked".
  ///
  /// A value written by a future version this one has never heard of is not a
  /// reason to keep somebody out of a screen they may need, so it degrades to
  /// the only state that is safe to recover from.
  static ConsentOutcome parseOutcome(String? raw) => switch (raw) {
        'granted' => ConsentOutcome.granted,
        'declined' => ConsentOutcome.declined,
        _ => ConsentOutcome.notAsked,
      };

  /// What is still worth asking about.
  ///
  /// Notifications and the calendar are the two real grants. The "staying awake"
  /// settings are counted too, because the third page of the explanation is
  /// about exactly those, and a person who allowed notifications and was then
  /// dropped into a battery screen has still not seen the whole thing.
  bool get somethingMissing =>
      !health.notifications ||
      !health.batteryExempt ||
      health.autostart == false ||
      !calendarGranted;

  /// Whether to put the explanation in front of this person right now.
  ///
  /// An answered question is never re-asked at launch, in either direction.
  /// Re-asking somebody who granted teaches people to tap through dialogs
  /// without reading them, which costs the permission that mattered the first
  /// time; re-asking somebody who declined is nagging, and a refusal answered
  /// with a fresh dialog is not respect, it is persistence.
  ///
  /// So only [ConsentOutcome.notAsked] can be offered, and only while something
  /// is genuinely missing. That is what makes the upgrade path work: the old
  /// flag resolves to notAsked, so a user who upgraded and has no notifications
  /// gets the screen exactly once, while a user who upgraded and already has
  /// everything is not shown a screen with nothing to say.
  bool get shouldOffer => switch (outcome) {
        ConsentOutcome.granted || ConsentOutcome.declined => false,
        ConsentOutcome.notAsked => somethingMissing,
      };

  /// One line for Settings, so the state is legible without opening anything.
  String get summary => switch (outcome) {
        ConsentOutcome.granted => 'You have been through this.',
        ConsentOutcome.declined =>
          'You said not now. Nothing was lost and you can change it below.',
        ConsentOutcome.notAsked => somethingMissing
            ? 'Koru has not asked yet.'
            : 'Everything Koru needs is already allowed.',
      };
}