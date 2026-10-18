import 'cloud_providers.dart';

/// Which model answers.
///
/// There is one. There used to be two — a model served on this device and a
/// frontier model over the internet — and before that three, the third being a
/// rules-based assistant that answered out of the user's records with no model
/// running at all.
///
/// Both of the others are gone, and the reason is worth writing down because it
/// is the reason for the app's size as much as its behaviour. The bundled 1.7B
/// Q1_0 model took the APK from 16 MB to 258 MB and, asked a question, talked
/// about a client instead of answering it, invented exchange rates, repeated
/// itself, and took about thirteen seconds for forty tokens. Every complaint
/// reported about "the AI" was that model. The rules-based one answered in
/// milliseconds, which is exactly why it made a broken engine look like a fast
/// one, so it went too.
///
/// What is left is a model over the internet, which is the one thing this app
/// needs from AI: turning what somebody types into a record they then confirm.
///
/// So this enum is a single value. It survives because the stored profile key
/// does, because every surface still needs the one honest name for it, and
/// because [KoruEngine.parse] has to keep resolving an install's stored string
/// whatever it says. It is no longer a choice, so nothing writes it any more
/// except the migration in `schema.dart`, which heals whatever an older install
/// already had.
enum KoruEngine {
  /// A frontier model over the internet.
  cloud;

  /// The one name this engine has anywhere in the app.
  ///
  /// A getter on a one-value enum on purpose: the app bar, the switcher, the
  /// badge on a reply and Settings all read it, and four copies of the words is
  /// how the same engine came to be called "Cloud model", "cloud", "Cloud" and
  /// "the online model" in four places.
  String get label => 'Cloud model';

  /// Reads a stored engine name, and always lands on the one that exists.
  ///
  /// A total function, not a nullable one, because an install can hold anything
  /// at all in that column: the literal string `'onDevice'` from before the
  /// bundled engine was removed, `'builtIn'` from before the rules-based one
  /// was, or nothing at all on a fresh install. All of them mean the same thing
  /// now — there is one engine and this is it — and anything else can only have
  /// come from a downgrade, a restored backup or a truncated row.
  ///
  /// Whether that one engine can actually answer is a different question, and
  /// one this cannot answer: it depends on whether a key is saved, which lives
  /// in the keystore rather than in the database. That is [EngineLink].
  static KoruEngine parse(String? value) => KoruEngine.values.firstWhere(
        (e) => e.name == value,
        orElse: () => KoruEngine.cloud,
      );
}

/// Whether anything can answer, and which model.
///
/// The whole of the engine question, as one value. The app bar, the switcher,
/// the badge on a reply, Settings and the failure card all have to answer it the
/// same way, and five reads of two keys from the store and the keystore is how
/// any of them ends up claiming a model is connected when it is not.
class EngineLink {
  final KoruEngine engine;

  /// The company that would answer. Defaults to the first one in the list on an
  /// install where nobody has chosen, which is a default rather than a
  /// decision — hence [providerChosen] beside it.
  final CloudProvider provider;

  final String model;

  /// Whether a key is saved for [provider] in the keystore.
  final bool hasKey;

  /// Whether this person has ever picked a company, as opposed to inheriting the
  /// default one.
  ///
  /// The difference between "you have not connected anything" and "you picked
  /// OpenRouter and have not added its key". They are the same repair and very
  /// different sentences, and only this column distinguishes them.
  final bool providerChosen;

  const EngineLink({
    this.engine = KoruEngine.cloud,
    required this.provider,
    required this.model,
    required this.hasKey,
    this.providerChosen = false,
  });

  /// True when a question can leave the phone and be answered.
  ///
  /// The key is the test rather than the selection. Every provider Koru ships
  /// asks for one, and a provider is always "selected" — the default one is
  /// filled in for somebody who has never chosen anything — so a link that read
  /// "connected" from the selection alone would be true on a fresh install and
  /// mean nothing.
  bool get isConnected => hasKey;

  /// The headline, for the app bar and the top of the switcher.
  ///
  /// The company's name rather than the engine's, because "Cloud model" says
  /// something is answering and "OpenRouter" says who. When nothing is
  /// connected it says that instead, which is the state a fresh install and
  /// every install that never added a key are honestly in.
  String get label => isConnected ? provider.label : 'No model connected';

  /// What is missing, in one sentence, and empty when nothing is.
  String get missing => isConnected
      ? ''
      : providerChosen
          ? 'No ${provider.label} key is saved.'
          : 'No model is connected yet.';

  /// The one tap that fixes a link that is not connected.
  EngineRecovery get recovery =>
      providerChosen ? EngineRecovery.addCloudKey : EngineRecovery.connectCloud;

  /// The state when the link could not be read at all.
  ///
  /// A keystore that is gone or locked leaves the app unable to tell whether
  /// anything is connected. That is not the same as a key being absent, but it
  /// is the same remedy and the same honest thing to say: the app cannot answer,
  /// and here is where to fix it. Nothing here is a guess that a model is
  /// missing — it says nothing is connected because nothing is known to be.
  static const EngineLink unreadable = EngineLink(
    provider: CloudProvider(
      id: '',
      label: 'the cloud provider',
      baseUrl: '',
      format: CloudWireFormat.openai,
      keyHint: '',
    ),
    model: '',
    hasKey: false,
  );
}

/// The one thing to do about a model that could not answer.
///
/// Two values rather than three, because there were three: the local model being
/// down is not a state this app has any more.
enum EngineRecovery {
  /// Nobody has picked a company yet. The action opens the switcher, which is
  /// where the picking happens.
  connectCloud,

  /// A company is picked and its key is not saved. The action opens the screen
  /// that takes a key.
  addCloudKey,
}

/// What to say, and what to offer, when no model could answer.
///
/// This is the whole of the answer for that turn. The app had a third engine — a
/// rules-based one that answered from the user's own records — and it reached for
/// it whenever a model could not be reached: a missing key, a model that had not
/// started, a crash. It produced a sentence immediately, so the model looked
/// fast, and it produced rubbish, because it was matching phrases rather than
/// understanding questions. Someone asking for an answer got an answer; they
/// just never got one from a model, and nothing on screen said so.
///
/// So there is no fallback. If nothing can answer, the app says what is missing
/// and offers the tap that fixes it.
class EngineUnavailable {
  const EngineUnavailable({required this.detail, required this.recovery});

  /// What is missing, in the app's own terms. Always shown, never guessed at.
  final String detail;

  final EngineRecovery recovery;

  /// The headline on the card under the reply.
  String get title => switch (recovery) {
        EngineRecovery.connectCloud => 'No model connected',
        EngineRecovery.addCloudKey => 'No key for the cloud model',
      };

  /// The sentence that goes in the bubble.
  ///
  /// Says plainly that nothing answered. Anything softer — a hedge, a summary of
  /// the records, an apology with an answer attached — is the behaviour this
  /// replaced.
  String get text => switch (recovery) {
        EngineRecovery.connectCloud =>
          'I cannot answer that. Nothing is connected — but your records work '
              'without one.',
        EngineRecovery.addCloudKey =>
          'I cannot answer that. $detail, so there is nothing to ask.',
      };

  /// The label on the button that fixes it.
  String get actionLabel => switch (recovery) {
        EngineRecovery.connectCloud => 'Connect a cloud model',
        EngineRecovery.addCloudKey => 'Add a cloud key',
      };
}

/// One earlier turn, carried into the model prompt.
class ChatTurn {
  const ChatTurn(this.role, this.text);

  final ChatRole role;
  final String text;
}

enum ChatRole { user, koru }

/// Re-checks what a model returned before it is shown.
///
/// The routing gate already stops sensitive questions reaching the model, and
/// that is the real control. This is defence in depth, and the list exists
/// because of something measured rather than imagined: the small on-device model
/// that has since been removed was asked about doubling a blood pressure dose
/// and answered with dose advice, and asked whether breaking a contract was
/// allowed and ruled on it. A model has no reliable notion of where its
/// competence ends, so the answer is checked rather than trusted.
///
/// Pure and synchronous so the rules are unit testable without a network.
class ModelOutputGuard {
  const ModelOutputGuard._();

  /// Advice that should only come from a clinician or a lawyer. Matched on
  /// word boundaries, so "illegalise this contract" is not treated as a ruling.
  static const _clinical = [
    'take double', 'double your dose', 'double the dose', 'twice the dose',
    'increase your dose', 'stop taking', 'skip the dose',
    'you have a rash', 'this is cancer', 'this is diabetes',
    'you should stop taking', 'safe to take', 'safe dosage',
  ];

  static const _legal = [
    'is illegal', 'is legal', 'you can sue', 'you cannot sue',
    'is unlawful', 'is lawful', 'you would win the case', 'grounds to sue',
  ];

  static const _crisis = [
    'when not alive', 'not be alive', 'melancholy question', 'feel a void',
  ];

  /// Returns true when [answer] says something that needs a person instead.
  static bool needsHuman(String answer) {
    final q = answer.toLowerCase().replaceAll(RegExp(r"[^a-z0-9' ]"), ' ');
    if (q.trim().isEmpty) return false;
    for (final term in [..._clinical, ..._legal, ..._crisis]) {
      if (_contains(q, term)) return true;
    }
    return false;
  }

  static bool _contains(String haystack, String needle) {
    var from = 0;
    while (true) {
      final at = haystack.indexOf(needle, from);
      if (at < 0) return false;
      final beforeOk = at == 0 || !_isWordChar(haystack[at - 1]);
      final end = at + needle.length;
      final afterOk = end >= haystack.length || !_isWordChar(haystack[end]);
      if (beforeOk && afterOk) return true;
      from = at + 1;
    }
  }

  static bool _isWordChar(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 48 && code <= 122) || code == 39;
  }
}

/// Catches a model claiming it saved something it could not have.
///
/// The model emits words. It cannot write to the database; everything that gets
/// saved is written by Dart after the user approves a card. So any sentence
/// saying it added, saved or created something is false by construction.
///
/// It is also the most damaging thing a helper can say, because it is the one
/// the user cannot check: the chat looks like a receipt, and the record simply
/// is not there. Found from testing, where "add an entry" matched no write
/// cue, fell through to the model, and the model cheerfully reported success.
class WriteClaimGuard {
  const WriteClaimGuard._();

  /// Claims of having completed a write.
  ///
  /// Written without apostrophes on purpose. [claimsWrite] folds punctuation to
  /// spaces before matching, so a needle containing one could never match the
  /// folded text: the answer "I've added Bilal" folds to "i ve added bilal" and
  /// an "i've added" needle sits there forever matching nothing. Both sides go
  /// through the same fold instead.
  static const _claims = <String>[
    'ive added',
    'i have added',
    'i added',
    'ive created',
    'i have created',
    'ive saved',
    'i have saved',
    'ive recorded',
    'i have recorded',
    'ive logged',
    'i have logged',
    'added successfully',
    'saved successfully',
    'all set',
  ];

  /// Folds case and punctuation the same way on both sides of the comparison.
  ///
  /// Apostrophes are deleted rather than spaced out, because they join a word:
  /// "I've" is one word, so folding it to "i ve" leaves the needle "ive added"
  /// unable to match the single most common way a model claims a write. Every
  /// other run of non-alphanumerics becomes a single space, since it separates.
  static String fold(String text) => text
      .toLowerCase()
      .replaceAll("'", '')
      .replaceAll('\u2019', '')
      .replaceAll(RegExp('[^a-z0-9]+'), ' ')
      .trim();

  /// True when [answer] is claiming a write it could not have made.
  ///
  /// Only consulted when no write was proposed. If a card was shown and the user
  /// approved it, a model saying "added" afterwards is correct and the guard
  /// must not fire.
  /// Word-boundary match, so "all set" does not fire inside "install".
  static bool _contains(String text, String needle) =>
      RegExp('\\b${RegExp.escape(needle)}\\b').hasMatch(text);

  static bool claimsWrite(String answer) {
    final q = fold(answer);
    return _claims.any((c) => _contains(q, fold(c)));
  }

  /// What to say instead.
  ///
  /// Names the phrasing that would have worked, because the useful reply to "I
  /// cannot do that" is "say it like this".
  static const nothingWasSaved =
      'I have not saved anything. I cannot save things myself, Koru records '
      'them when you ask in plain English and shows you what it understood '
      'first. Try "add client Bilal for 2000", or paste a list with one '
      'client per line.';
}