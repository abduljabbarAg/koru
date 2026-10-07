import 'packet.dart';

/// What "bring in a person" actually means in the product.
///
/// The routing layer already knows when a question is not a model's to answer.
/// Previously that knowledge produced one line of preamble in the chat bubble,
/// which is not a safety feature: the user still had to notice the text and
/// still had to already know who to call.
///
/// [HandoffPlan] is the rest of that path. When a decision says
/// [RoutingDecision.needsHuman], the chat renders a card with named services and
/// emergency numbers, and the local answer is suppressed rather than padded.
class HandoffPlan {
  const HandoffPlan({
    required this.headline,
    required this.body,
    required this.resources,
    this.urgent = false,
  });

  final String headline;
  final String body;
  final List<Resource> resources;

  /// True when this is an emergency, in which case the emergency number is
  /// surfaced first and the card is styled as an alert.
  final bool urgent;
}

class Resource {
  const Resource({
    required this.name,
    required this.detail,
    required this.number,
    this.hours = '24 hours',
  });

  final String name;
  final String detail;
  final String number;
  final String hours;
}

/// True when [question] describes an immediate emergency rather than a topic a
/// professional should weigh in on.
bool isImmediateDanger(String question) {
  final q = RoutingDecision.normalise(question);
  const urgent = [
    'kill myself', 'killing myself', 'end my life', 'end it all',
    'suicide', 'suicidal', 'harm myself', 'hurt myself', 'self harm',
    'self-harm', 'want to die', 'wanna die', 'no reason to live',
    'better off dead', 'overdose', 'not safe', 'hit me', 'hits me',
    'beat me', 'beating me',
  ];
  for (final term in urgent) {
    if (q.contains(term)) return true;
  }
  return false;
}

/// The plan to show. Emergency phrasing gets the alert treatment and leads with
/// the emergency number; everything else still gets real, named services.
HandoffPlan handoffPlanFor(RoutingDecision decision, String question) {
  if (!decision.needsHuman) {
    throw ArgumentError('handoffPlanFor needs a decision that asks for a human');
  }
  if (isImmediateDanger(question)) {
    return const HandoffPlan(
      urgent: true,
      headline: 'Talk to someone right now',
      body: 'I am not the right place for this, and I do not want to guess. '
          'These lines are free and answer around the clock. If you are in '
          'immediate danger, call the emergency number first.',
      resources: const [
        Resource(
          name: 'Emergency',
          detail: 'Police, ambulance, fire',
          number: '999',
          hours: '24 hours',
        ),
        Resource(
          name: 'Urgent mental health line',
          detail: 'Free, confidential, staffed by people',
          number: '800 4673',
          hours: '24 hours',
        ),
      ],
    );
  }
  return const HandoffPlan(
    headline: 'This one deserves a person',
    body: 'Koru can give you general framing, but not a diagnosis, a dose, or a '
        'ruling. Someone qualified should be the one to decide this.',
    resources: [
      Resource(
        name: 'A doctor or clinic',
        detail: 'For anything about a diagnosis, a medication or a test result',
        number: 'Book with your usual clinic',
      ),
      Resource(
        name: 'A licensed adviser',
        detail: 'For anything with a deadline or a court date attached',
        number: 'Book a consultation',
      ),
      Resource(
        name: 'Someone you trust',
        detail: 'For anything that feels like too much to hold alone',
        number: 'Call or message them today',
      ),
    ],
  );
}
