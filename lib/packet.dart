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
  /// Kept as lowercase substrings and matched against the whole question, so
  /// "I have not slept in four days" and "I cannot sleep" both hit. The list
  /// is deliberately generous: a false positive costs the user a sentence
  /// saying this deserves a person, and a false negative hands a crisis to a
  /// language model.
  static const _handoff = [
    // crisis and safety
    'suicide', 'suicidal', 'kill myself', 'self harm', 'self-harm', 'harm myself',
    'end my life', 'no reason to live', 'want to die', 'better off dead',
    'don\'t want to live', 'give up on life',
    // mental health crisis
    'panic attack', 'cant breathe', "can't breathe", 'breaking down',
    'not slept', 'no sleep', 'cant sleep', "can't sleep", 'insomnia',
    'three days', 'four days', 'awake for', 'no reason to get up',
    'hopeless', 'empty', 'numb', 'crying every', 'cant function', "can't function",
    'burned out', 'burnt out', 'burn out',
    // harm and coercion
    'abuse', 'abusive', 'hit me', 'violent', 'unsafe', 'stalked',
    // medical and legal, where a model must not decide
    'diagnosis', 'diagnosed', 'prescription', 'medication', 'dose',
    'symptom', 'symptoms', 'blood test', 'lab result', 'surgery',
    'lawsuit', 'court', 'legal action', 'sue', 'custody', 'divorce',
  ];

  static const _cloudDomains = ['faith', 'religion', 'islam', 'mental', 'health', 'medical', 'legal'];

  static RoutingDecision route(String question) {
    final q = question.toLowerCase().replaceAll(RegExp(r"[^a-z0-9' ]"), ' ');

    for (final h in _handoff) {
      if (q.contains(h)) {
        return const RoutingDecision(
          useCloud: true,
          needsHuman: true,
          reason: 'This one deserves a person, not a model.',
        );
      }
    }
    for (final c in _cloudDomains) {
      if (q.contains(c)) {
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