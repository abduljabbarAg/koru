import 'dart:convert';

/// The shape that leaves the device when a cloud model is used.
///
/// Hard rule enforced by construction: this class is built only by
/// [ProfileStore.toContextPacket]. Nothing the model previously wrote is ever
/// fed back in, so a model that read a full profile once cannot quote it back
/// in a later packet.
class ContextPacket {
  final String nickname;
  final String lifeStage;
  final String business;
  final String goals;
  final String fitness;
  final String focus;

  const ContextPacket({
    required this.nickname,
    required this.lifeStage,
    required this.business,
    required this.goals,
    required this.fitness,
    required this.focus,
  });

  /// Pseudonymous context: who you are in general terms, never who you are.
  /// No names, no exact figures the user did not intend to share, no history.
  String render() {
    final parts = <String>[
      if (lifeStage.isNotEmpty) 'stage: $lifeStage',
      if (business.isNotEmpty) 'work: $business',
      if (goals.isNotEmpty) 'goals: $goals',
      if (fitness.isNotEmpty) 'fitness: $fitness',
      if (focus.isNotEmpty) 'asking about: $focus',
    ];
    return 'About this user. $nickname. ${parts.join('. ')}.';
  }

  Map<String, dynamic> toJson() => {
        'nickname': nickname,
        'life_stage': lifeStage,
        'business': business,
        'goals': goals,
        'fitness': fitness,
        'focus': focus,
      };

  factory ContextPacket.fromJson(Map<String, dynamic> j) => ContextPacket(
        nickname: j['nickname'] as String? ?? '',
        lifeStage: j['life_stage'] as String? ?? '',
        business: j['business'] as String? ?? '',
        goals: j['goals'] as String? ?? '',
        fitness: j['fitness'] as String? ?? '',
        focus: j['focus'] as String? ?? '',
      );

  String encode() => jsonEncode(toJson());

  /// Word count, used to keep the packet inside a token budget.
  int get wordCount => render().split(RegExp(r'\s+')).length;
}

/// Turns a domain question into a routing decision, with no configuration
/// surface exposed to the user.
///
/// Routing rule, hardcoded by design:
///   faith, mental health, medical, legal  -> cloud, and flag for human handoff
///   everything else                         -> local
class RoutingDecision {
  final bool useCloud;
  final bool needsHuman;
  final String reason;

  const RoutingDecision({
    required this.useCloud,
    required this.needsHuman,
    required this.reason,
  });

  /// Phrasings that mean a person should answer, not a model.
  ///
  /// Matching is on word boundaries, not raw substrings. Substring matching
  /// produced two false positives that both matter: "I want to die laughing"
  /// matched "want to die", and "empty my folder" matched "empty". Neither is
  /// a crisis, and escalating an ordinary request trains the user to ignore
  /// the escalation.
  ///
  /// The list is deliberately generous instead. A false positive costs one
  /// sentence saying this deserves a person; a false negative hands a crisis,
  /// a diagnosis, or a court date to a language model.
  static const _handoff = [
    // crisis and safety
    'suicide', 'suicidal', 'kill myself', 'killing myself', 'self harm',
    'self-harm', 'harm myself', 'hurt myself', 'end my life', 'end it all',
    'no reason to live', 'want to die', 'wanna die', 'better off dead',
    'rather be dead', 'give up on life', 'tired of living',
    // mental health crisis
    'panic attack', 'cant breathe', "can't breathe", 'breaking down',
    'not slept', 'no sleep', 'cant sleep', "can't sleep", 'cannot sleep',
    'can not sleep', 'insomnia', 'slepless', 'wide awake',
    'awake for', 'no reason to get up', 'hopeless', 'helpless',
    'pointless', 'cant function', "can't function", 'not functioning',
    'falling apart', 'breaking', 'burned out', 'burnt out', 'burn out',
    'crying all', 'crying every', 'no energy', 'exhausted',
    'so tired', 'always tired', 'depressed', 'depression', 'numb',
    'no point', 'nothing matters', 'cant go on', "can't go on", 'go on',
    // harm, coercion, safety
    'abuse', 'abusive', 'abused', 'abusing', 'hit me', 'hits me', 'beat me',
    'beating me', 'violent', 'violence', 'not safe', 'unsafe',
    'stalked', 'stalking', 'threat', 'threaten', 'threatens', 'threatened',
    'afraid of', 'scared to', 'frightened', 'terrified',
    // medical, where a model must not decide
    'diagnosis', 'diagnosed', 'diagnose', 'prescription', 'medication',
    'my dose', 'the dose', 'dosage', 'overdose', 'side effect',
    'symptom', 'symptoms', 'blood test', 'lab result', 'x ray', 'mri',
    'biopsy', 'surgery', 'operation', 'chronic pain', 'pregnant',
    'pregnancy', 'miscarriage',
    // legal, where a model must not decide
    'lawsuit', 'in court', 'go to court', 'legal action', 'sue them', 'sue',
    'custody', 'divorce', 'restraining order', 'deportation',
    'deported', 'immigration', 'police', 'arrested', 'charges',
  ];

  static const _cloudDomains = ['faith', 'religion', 'islam', 'mental', 'health', 'medical', 'legal'];

  /// Multi-word terms must match as a phrase, and every term must respect word
  /// boundaries, so "empty my folder" never matches a bare "empty".
  static bool _matches(String haystack, String needle) {
    var from = 0;
    while (true) {
      final at = haystack.indexOf(needle, from);
      if (at < 0) return false;
      final beforeOk = at == 0 || !_isWordChar(haystack[at - 1]);
      final end = at + needle.length;
      final afterOk = end >= haystack.length || !_isWordChar(haystack[end]);
      if (needle.contains(' ') || (beforeOk && afterOk)) return true;
      from = at + 1;
    }
  }

  static bool _isWordChar(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 122 ||
      c.codeUnitAt(0) == 39;

  static RoutingDecision route(String question) {
    final q = question.toLowerCase().replaceAll(RegExp(r"[^a-z0-9' ]"), ' ');

    for (final h in _handoff) {
      if (_matches(q, h)) {
        return const RoutingDecision(
          useCloud: true,
          needsHuman: true,
          reason: 'This one deserves a person, not a model.',
        );
      }
    }
    for (final c in _cloudDomains) {
      if (_matches(q, c)) {
        return const RoutingDecision(
          useCloud: true,
          needsHuman: false,
          reason: 'Sent to a frontier model for a stronger answer.',
        );
      }
    }
    return const RoutingDecision(
      useCloud: false,
      needsHuman: false,
      reason: 'Answered on device.',
    );
  }
}

/// Builds the prompt actually sent upstream.
class PromptBuilder {
  static String build({
    required ContextPacket packet,
    required String question,
    required RoutingDecision routing,
  }) {
    final buf = StringBuffer()
      ..writeln('You are the assistant inside Koru, a personal AI companion.')
      ..writeln('Be brief and concrete. Code first, words second when it is code.')
      ..writeln('The user is pseudonymous: never guess or invent a real name.')
      ..writeln()
      ..writeln(packet.render())
      ..writeln()
      ..writeln('Question: $question');
    if (routing.needsHuman) {
      buf
        ..writeln()
        ..writeln('IMPORTANT: this is a sensitive topic. Do not give a diagnosis,')
        ..writeln('ruling, or legal judgement. Acknowledge, give general framing,')
        ..writeln('and tell them a qualified human should be the one to decide.');
    }
    return buf.toString();
  }
}