// Business advice for the built-in assistant.
//
// The half of a freelancer's day that is not a database question: what to
// charge, when to invoice, how to chase, whether to take the job. The
// deterministic assistant used to shrug at all of it and point at the cloud,
// which is exactly the class of question a person asks their phone in the
// twenty seconds before a call, and it has to be answerable offline.
//
// Every reply is concrete: a rule of thumb with a number in it, the next step,
// and a sentence the user can copy and send. Where the user's own records are
// relevant they are quoted back by name and figure, because advice about
// "clients" is wallpaper and advice about "Acme, 1500, twelve days late" is
// useful.
//
// Voice: plain, warm, slightly wry, British English, short paragraphs. Never
// corporate, never "as an AI", never a bare acknowledgement.
//
// Pure functions over [LocalFacts]: no clock, no I/O, so all of this is unit
// testable without a database or a widget tree. The classifier in
// `local_assistant.dart` reads the cue lists below, so the rules for what
// counts as a quoting question live next to the answer it produces.

import '../../models.dart';
import '../facts.dart';

/// One domain of advice, with the cues that claim a question for it and the
/// replies it produces.
class BusinessAdvice {
  const BusinessAdvice();

  // -- cues the classifier reads --------------------------------------
  //
  // Phrases match as substrings of the folded question; single risky words
  // match whole, because "private" contains "vat", "operate" contains "rate",
  // and "generate" contains "rate" again. Two lists per domain is the price of
  // not answering "is my contract private" with VAT law.

  static const quotePhrases = [
    'how much should i charge', 'what should i charge', 'should i charge',
    'how much to charge', 'what to charge', 'charge for this', 'charge for it',
    'quoting for', 'quote for', 'send a quote', 'send them a quote',
    'write a quote', 'writing a quote', 'price this job', 'pricing a job',
    'how to quote', 'how do i quote', 'how much for this job',
    'how much for the job', 'how much for a logo', 'how much for a website',
    'how much for a project', 'how much for this project', 'how much for it',
    'what would you charge', 'give them a price', 'put a price on',
  ];
  static const quoteWords = ['quote', 'quoting', 'quot'];

  static const ratePhrases = [
    'day rate', 'daily rate', 'hourly rate', 'my rate', 'our rate',
    'raise my rate', 'raise rates', 'raise your rate', 'increase my rate',
    'increase rates', 'rate too low', 'rates too low', 'charging enough',
    'undercharging', 'under charge', 'too cheap', 'too low', 'what rate',
    'rate for', 'how much an hour', 'per hour should', 'per day should',
    'hourly basis', 'charge by the hour', 'charge by hour', 'hourly',
  ];
  static const rateWords = ['rate', 'rates'];

  static const invoicePhrases = [
    'should i invoice', 'when to invoice', 'when should i invoice',
    'time to invoice', 'invoice them', 'raise an invoice', 'raising an invoice',
    'how to invoice', 'invoice wording', 'invoice template', 'wording for the invoice',
    'payment terms', 'net 14', 'net 30', 'net 7', 'due on completion',
    'invoice look like', 'invoice say', 'put on the invoice',
    "don't invoice", 'dont invoice', "shouldn't invoice", 'shouldnt invoice',
    'hold the invoice', 'not invoice yet', "isn't ready to invoice",
    'isnt ready to invoice',
  ];

  static const latePhrases = [
    'hasn\'t paid', 'has not paid', 'hasnt paid', 'not paid me', 'still not paid',
    'still has not paid', 'ignored my invoice', 'ignoring my invoice',
    'not paying', 'refuses to pay', 'wont pay', 'won\'t pay',
    'haven\'t paid', 'havent paid', 'didn\'t pay', 'didnt pay',
    'client is late', 'they are ignoring', 'being ignored', 'chase them',
    'chase him', 'chase her', 'how do i chase', 'how to chase',
    'chasing a client', 'payment reminder', 'reminder for payment',
    'second reminder', 'final demand', 'letter before action',
    'late paying', 'payment is late', 'money is late', 'still waiting on',
    'ghosted me', 'gone quiet', 'gone silent',
    'hold off on chasing', 'hold off chasing', 'wait before chasing',
    'pause the chase', 'stop chasing', 'not chase them',
  ];

  static const vatPhrases = [
    'hmrc', 'self assessment', 'tax return', 'set aside', 'setting aside',
    'putting aside', 'tax bill', 'tax money', 'taxman', 'accountant',
    'sole trader', 'registered for', 'register for', 'do i need to register',
    'money for tax', 'tax bill coming',
  ];
  static const vatWords = ['vat', 'tax'];

  static const cashflowPhrases = [
    'cash flow', 'cashflow', 'dry spell', 'feast and famine', 'slow month',
    'lean month', 'no work coming', 'money coming in', 'how long can i last',
    'run out of money', 'runway', 'out of savings', 'no income',
    'pipeline is thin', 'too many invoices',
  ];

  static const depositPhrases = [
    'take a deposit', 'deposit up front', 'up front', 'upfront',
    'pay upfront', 'half up front', 'money before you start',
    'before you start work', 'deposit for', 'ask for a deposit',
    'should i take a deposit', 'do you take deposits',
  ];
  static const depositWords = ['deposit', 'deposits'];

  static const retainerPhrases = [
    'retainer', 'monthly fee', 'ongoing work', 'rolling contract',
    'every month for', 'monthly retainer', 'retainor', 'retainer client',
    'regular monthly', 'monthly for ongoing',
  ];

  static const scopePhrases = [
    'scope creep', 'extra work', 'keeps asking', 'keep asking for',
    'changing the brief', 'changed the brief', 'one more thing',
    'while you are at it', 'outside the scope', 'free work',
    'they want more', 'more than we agreed', 'not in the quote',
    'not in the original', 'added more to', 'extra revisions',
    'another round of revisions', 'unlimited revisions',
  ];

  static const noPhrases = [
    'say no to', 'how do i say no', 'turn down', 'turning down',
    'decline the', 'decline this', 'pass on the job', 'pass on this',
    'refuse the work', 'reject the job', 'not taking the job',
    'turn this client down', 'turning work down', 'should i take this job',
    'should i take this on', 'not sure i want',
  ];

  static const negotiatePhrases = [
    'negotiate', 'negotiating', 'haggling', 'discount', 'discounts',
    'cheaper', 'lower the price', 'reduce the price', 'knock money off',
    'knock off the', 'meet me on price', 'price is too high', 'wants it for less',
    'wants a lower', 'price down', 'talk the price', 'barter', 'haggle',
    'cut the price', 'reduce my price', 'give them a discount',
  ];

  static const explainPhrases = [
    'explain the invoice', 'explain the cost', 'explain the price',
    'explain the charge', 'explain my rates', 'explain my charge',
    'justify', 'itemise', 'itemize',
    'break down the cost', 'break down the price',
    'questioned the invoice', 'questioned my invoice', 'questioned my',
    'querying the invoice', 'query on the invoice', 'asking why it',
    'client asked why', 'why is this so', 'why so expensive',
    'argue about the', 'disputed the', 'explain this charge',
    'they want an explanation',
  ];

  static const refundPhrases = [
    'refund', 'money back', 'give them their', 'return their deposit',
    'refund a deposit', 'refund the', 'asking for money back',
    'wants a refund', 'have to refund', 'should i refund',
  ];
  static const refundWords = ['refund', 'refunds'];

  static const cancelPhrases = [
    'cancelled', 'canceled', 'cancel the project', 'cancel the work',
    'pulled out', 'pulled the plug', 'backed out', 'no show', 'no-show',
    'did not show', 'didnt show', 'kill fee', 'cancellation', 'cancelation',
    'they dumped me', 'project was cancelled', 'job was cancelled',
    'scrapped the', 'axing the', 'axing my',
  ];

  static const contractPhrases = [
    'contract', 'agreement', 'terms of service', 'terms and conditions',
    'scope of work', 'get it in writing', 'in writing', 'paperwork',
    'sign something', 'indemnity', 'liability', 'contractor agreement',
    'simple contract', 'do i need a contract',
  ];
  // Whole words only: "sign" must not match inside "design", and "nda" lives
  // happily inside "calendar", which would answer the diary with contract law.
  static const contractWords = ['sign', 'nda'];

  static const onboardPhrases = [
    'onboard', 'onboarding', 'kick off', 'kickoff', 'first call with',
    'discovery call', 'intro call', 'starting work with', 'just won',
    'signed a new', 'won a new', 'new gig', 'new job starting',
    'starting with a', 'first project for',
  ];

  static const timelinePhrases = [
    'how long will', 'how long should', 'how long to', 'timeline',
    'by when can', 'realistic deadline', 'when will it be done',
    'project schedule', 'timeframe', 'time frame', 'how much time',
    'how long have i got', 'estimate how long', 'long is this going',
  ];

  static const workloadPhrases = [
    'too busy', 'swamped', 'overwhelmed', 'too much work', 'too much on',
    'burning out', 'drowning', 'no time for', 'working every',
    'behind on everything', 'cant keep up', 'cannot keep up',
    'everything at once', 'booked up', 'no breathing space',
  ];

  static const hiringPhrases = [
    'hire', 'hiring', 'subcontract', 'sub contract', 'sub-contract',
    'outsource', 'outsourcing', 'freelancer to help', 'find a designer',
    'find a developer', 'delegate', 'virtual assistant', 'pass work to',
    'someone to help me', 'take on a',
  ];

  static const toolsPhrases = [
    'what tool', 'which tool', 'software for', 'what app', 'which app',
    'app for', 'recommend', 'what do you use', 'better than', 'switch to',
    'invoice software', 'tool to', 'tool for', 'software to',
  ];

  static const draftPhrases = [
    'draft', 'write an email', 'write a message', 'write an email to',
    'wording', 'phrase it', 'how do i phrase', 'what should i say',
    'what to say', 'message saying', 'email saying', 'reply saying',
    'text saying', 'script for', 'say to them', 'word it',
  ];

  // -- quoting -----------------------------------------------------------

  String quote(LocalFacts f, String q) {
    if (_neg(q)) {
      return _pick([
        'Right — do not send a number yet. Work out the days it will take, '
            'multiply by the rate you actually want, add a third for the '
            'surprises, and only then put a figure in writing. A quote given '
            'from the hip is a quote you will resent halfway through.',
        'Fair. Sit on it. A price pulled out of your head on a Tuesday comes '
            'back to bite you in week three of the job. Sleep on it, then send '
            'the number you would be happy to do the work for.',
      ], q);
    }
    final base = _pick([
      'Work backwards from days, not vibes. Work out the days the job '
          'genuinely takes, multiply by the daily rate you want to land on '
          '(not the one you are embarrassed to say out loud), then add about '
          'a third for revisions, waiting and the thing they forgot to '
          'mention.\n\n'
          'Example: four days of work at 400 a day is 1600. Add a third: '
          'quote 2100, deliver in four days, and everyone is happy when it '
          'runs to five.\n\n'
          'In the quote itself: the figure, what is included, what is '
          'explicitly not, the payment terms, and a line saying changes to '
          'the brief get re-quoted. That last line is the one that saves you.',

      'Three steps. One: write down every deliverable in plain words, and '
          'half-deliverables too — the "quick tweaks" that always eat a week. '
          'Two: put a day estimate against each and total it. Three: multiply '
          'by your day rate and add a third as a buffer.\n\n'
          'Never send a bare number. Send the number with the list of what it '
          'covers, because a price with no scope attached is a price they '
          'will try to stretch. Something like: "2100 for the homepage, '
          'checkout and two rounds of revisions; further changes quoted '
          'separately."\n\n'
          'And send it as a document with a validity date — "this quote holds '
          'for 30 days" — so a number from March does not come back to haunt '
          'you in August.',

      'The short version: price the job you described, not the job you hope '
          'it turns out to be.\n\n'
          'List the deliverables. Estimate each in days, including the boring '
          'parts nobody mentions — admin, calls, exporting files, the second '
          'round of revisions. Total the days. Multiply by the rate you want. '
          'Then add a third.\n\n'
          'A worked example: 3 days design, 2 days build, 1 day revisions = '
          '6 days. At 350 a day that is 2100. Quote 2800 with a note that '
          'extra pages are 350 each. You will usually land near 2100 and '
          'occasionally get 2800, and the extra is your sanity fund.\n\n'
          'If the number scares you, it is probably about right.',
    ], q);
    return '$base${_quoteTail(f)}';
  }

  String _quoteTail(LocalFacts f) {
    final lead = f.clients.where((c) => c.status == 'lead' && c.amount != null).toList();
    if (lead.isEmpty) return '';
    final c = lead.first;
    return '\n\nOn file: ${c.name} is a lead at ${_plain(c.amount!)}. If that '
        'number came from a guess rather than a day count, re-derive it with '
        'the method above before you send it.';
  }

  // -- rates --------------------------------------------------------------

  String rate(LocalFacts f, String q) {
    if (_neg(q)) {
      return _pick([
        'Understood — hold your rates where they are for now. When you do '
            'move them, raise them for new clients first; it is the least '
            'frightening way to find out what the market pays.',
        'Fair enough. Worth knowing though: the fastest raise you will ever '
            'give yourself is the next new-client quote. Nothing existing has '
            'to change for that one to move your average up.',
      ], q);
    }
    return _pick([
      'Three ways to work out a rate, in increasing order of honesty.\n\n'
          'One: what you need. Annual outgoings you must cover, say 36000, '
          'divided by billable days. Working 180 days a year that is 200 a '
          'day — and that is the floor, not the target.\n\n'
          'Two: what the work is worth. If a site you build in a week makes '
          'the client 50000 a year, quoting 2000 is leaving almost everything '
          'on the table.\n\n'
          'Three: what you charge now, plus 20%. If you hesitate at the new '
          'number, that hesitation is usually just habit. Quote the new rate '
          'to the next three enquiries and see what the silence rate actually '
          'is — my bet is it barely moves.\n\n'
          'Practical rule: raise for new clients immediately; raise existing '
          'clients at renewal, with a month\'s notice, framed as a review '
          'rather than an ambush.',

      'Work out the day rate from the bottom up.\n\n'
          'Take what a comfortable year costs you — rent, bills, tax, '
          'pension, software, the lot. Divide by the number of days you can '
          'realistically bill. Freelancers usually bill about 60% of working '
          'days once you count invoicing, chasing, pitching and staring at '
          'the wall. So 40000 a year over roughly 150 billable days is '
          '265-ish a day.\n\n'
          'Now sanity-check it against the market and against the value of '
          'the work. If you are the cheapest person in the room, you are not '
          'winning on skill, you are winning on price, and that is a race '
          'with one ending.\n\n'
          'If a client baulks at your rate, do not discount straight away. '
          'Ask what budget they had in mind — often the gap is smaller than '
          'you feared, and sometimes they will simply move to it.',

      'Say the number out loud before you say it to them, and say it once.\n\n'
          '"My day rate is 350." Full stop. No upward inflection, no '
          '"around", no apology. The people who underrate themselves almost '
          'always bury the number inside a sentence — "well, I suppose it '
          'would be something like 200-ish?" — and the client hears the '
          'lowest figure in the heap.\n\n'
          'A quick self-audit: add up last quarter\'s invoices, divide by '
          'days you actually worked on them. That is your real rate today. If '
          'it is lower than the rate you would like, the fix is usually fewer '
          'small jobs rather than more big ones — the admin around a 300 job '
          'costs about the same as around a 3000 one.',
    ], q);
  }

  // -- invoicing ----------------------------------------------------------

  String invoice(LocalFacts f, String q) {
    if (_neg(q)) {
      return _pick([
        'Holding the invoice, understood. Just do not hold it past the '
            'work being signed off: "when you are happy with it, I will send '
            'the invoice" is a sentence that keeps you polite and gets you '
            'paid. If the work is done and approved, the invoice should go '
            'today — an invoice never sent is money that does not exist.',
        'Right — not yet. Fine, if they have not signed off the work. If '
            'they have, send it anyway: today, not Friday, not "once this '
            'other thing settles". The clock on their payment terms cannot '
            'start until the invoice lands.',
      ], q);
    }
    final late = f.clients.where((c) => f.balanceOf(c) > 0).toList();
    final base = _pick([
      'Invoice the moment the work is delivered and signed off — not at the '
          'end of the month, not when you feel less awkward about it.\n\n'
          'What to put on it: your name and contact details, a unique number, '
          'the date, their purchase order if they have one, a plain-English '
          'description ("homepage design, three rounds of revisions"), the '
          'amount, the payment terms, and your bank details. Due date on the '
          'face of it. Late-payment interest clause if you are feeling '
          'grown-up — it does not need to be fancy to be enforceable.\n\n'
          'Terms to ask for: 14 days is a good default for individuals, 30 '
          'for larger companies who will not budge. "On completion" is fine '
          'for small jobs. Avoid "end of month following" — that is 60 days '
          'by another name.\n\n'
          'Example line they can send to their finance team: "Please add '
          'Acme to your payment system — invoice attached, due in 14 days, '
          'PO to follow."',

      'As soon as it is done. The two of you agreed the work; the work is '
          'done; the invoice is the least creative part of the job and it '
          'should take ten minutes.\n\n'
          'A good invoice says: what was done, in their language; the amount, '
          'broken down if there are parts; the terms; the due date; how to '
          'pay. A bad invoice says "website final v3" and nothing else, and '
          'it sits in an inbox while somebody tries to remember what it was '
          'for.\n\n'
          'If you are VAT registered, show your VAT number and the VAT '
          'split. If you are not, do not pretend to be.\n\n'
          'Send it as a PDF from an address they can reply to, and put the '
          'due date in the subject line: "Invoice 0042 — 2100, due 14 '
          'March". Future you, chasing in April, will be grateful.',

      'The short version: invoice today if the work is done, and set terms '
          'that match how you want to be paid.\n\n'
          '14 days is the sweet spot for most freelancers — long enough that '
          'nobody feels ambushed, short enough that the money is still warm. '
          'Write the terms on the invoice itself, not just in the email.\n\n'
          'Then, and this is the part everyone skips: diarise the follow-up. '
          'The day after it is due, a one-line nudge. A week later, a firmer '
          'one. Most late payments are not malice, they are a finance system '
          'that needs a human to press a button, and your reminder is that '
          'button.',
    ], q);
    if (late.isEmpty) return base;
    final c = late.first;
    final bal = f.balanceOf(c);
    return '$base\n\nWhile you are here: ${c.name} still has ${_plain(bal)} '
        'outstanding. If that was invoiced a while ago, the next step is not '
        'another nudge, it is a phone call.';
  }

  // -- late payment -------------------------------------------------------

  String latePayment(LocalFacts f, String q) {
    if (_neg(q)) {
      return _pick([
        'Understood — leave them alone for now. Worth a quiet diarised '
            'check though: late payers rarely announce themselves, they just '
            'keep not paying until somebody makes it awkward.',
        'Fair enough. Put a date in your calendar to look again, though. The '
            'cost of chasing drops sharply after about a month, which is the '
            'opposite of how it feels.',
      ], q);
    }
    final owing = f.clients.where((c) => f.balanceOf(c) > 0).toList()
      ..sort((a, b) {
        final aLate = a.isOverdueOn(f.today) ? 1 : 0;
        final bLate = b.isOverdueOn(f.today) ? 1 : 0;
        if (aLate != bLate) return bLate - aLate;
        return f.balanceOf(b).compareTo(f.balanceOf(a));
      });
    final base = _pick([
      'Escalate in three steps, and start today if it is already late.\n\n'
          'One, the assuming-goodwill nudge — a short message, no apology, '
          'that treats it as an oversight: "Hi Sam, invoice 0042 for 1600 '
          'was due on the 3rd — could you let me know when it is scheduled? '
          'Thanks."\n\n'
          'Two, a week later, the firm one: "Following up on invoice 0042, '
          'now 7 days overdue. I would like to keep working together, so '
          'could you confirm a payment date this week?"\n\n'
          'Three, the formal one: mention the Late Payment of Commercial '
          'Debts rules — statutory interest plus a fixed compensation fee '
          'kicks in automatically for business-to-business invoices — and '
          'say you will pause further work until it is settled. Then pause '
          'the work.\n\n'
          'What actually gets money moving, in order: a phone call, a '
          'WhatsApp, an email copied to whoever signs things off. Email on '
          'its own is the weakest of the four.',

      'Chase in writing, early, and without apologising for chasing.\n\n'
          'The classic mistake is the soft chase — "just checking in on this '
          'when you get a sec!" — which is so easy to ignore that it might as '
          'well not have been sent. The version that works assumes busyness, '
          'not bad faith, and asks for a date: "Hi Priya, invoice 0039 for '
          '900 was due on the 20th. Could you confirm when it will be paid? '
          'Happy to resend if it went missing."\n\n'
          'If a second reminder fails, change channel rather than volume: '
          'call. If that fails, send a letter-before-action — a short formal '
          'letter giving 14 days, mentioning statutory interest. It sounds '
          'heavy, but it is a standard business letter and it works far more '
          'often than it needs to.\n\n'
          'And for the next job: stage payments. Half up front, half on '
          'delivery means half of any future mess never happens.',

      'The rule of thumb: two weeks late, it is an oversight. Two months '
          'late, it is a decision.\n\n'
          'Oversight: friendly, specific, one-line nudge with the invoice '
          'number and amount, and a "could you resend the details if it '
          'went to someone else" escape hatch — a surprising number of late '
          'payments are a finance inbox nobody owns.\n\n'
          'Decision: stop the work, stop being polite about it, and put '
          'everything in writing from now on. Ask for a payment plan in '
          'writing if they genuinely cannot pay in one go — half now, half '
          'in 30 days, in writing, is better than a promise and a prayer.\n\n'
          'Keep a note of every chase: date, channel, what they said. If it '
          'ever becomes a claim, that log is the whole case.',
    ], q);
    if (owing.isEmpty) return base;
    final c = owing.first;
    final days = c.daysUntilDue(f.today);
    final when = days == null
        ? ''
        : days < 0
            ? ', ${-days} day${days == -1 ? '' : 's'} past the due date'
            : ', due in $days day${days == 1 ? '' : 's'}';
    return '$base\n\nOn file right now: ${c.name} owes '
        '${_plain(f.balanceOf(c))}$when. The first nudge above is today\'s '
        'job.';
  }

  // -- VAT and tax ---------------------------------------------------------

  String vat(LocalFacts f, String q) {
    if (_neg(q)) {
      return _pick([
        'Understood. If you are not registered, that is a perfectly normal '
            'place to be — just keep the turnover figure somewhere you can '
            'find it, because the threshold moves and it is measured on a '
            'rolling twelve months, not the tax year.',
        'Fair enough. The one habit worth keeping either way: move about a '
            'quarter of everything that lands into a separate account the '
            'moment it lands. Tax money that is already gone cannot be '
            'spent by accident.',
      ], q);
    }
    return _pick([
      'A few rules of thumb, none of them a substitute for an hour with an '
          'accountant (which is usually cheaper than the mistakes).\n\n'
          'Money for tax: move roughly 20–25% of every payment into a '
          'separate account as it arrives. Sole trader, that roughly covers '
          'income tax and National Insurance on a typical freelance income; '
          'limited company, it comfortably covers corporation tax and most '
          'of what you will draw.\n\n'
          'VAT: if you are registered, you charge VAT on your invoices and '
          'claim back VAT on business costs, and the difference goes to '
          'HMRC, usually quarterly. If you are not registered and you are '
          'close to the registration threshold, watch the rolling twelve '
          'month total — cross it and you must register, sometimes '
          'backdating the liability.\n\n'
          'Keep every invoice and receipt, even the small ones. An hour a '
          'month now, or a fortnight in a panic next January. Your future '
          'self is not more organised than your current self, they are just '
          'more desperate.',

      'The short version: set the money aside before you touch it, and keep '
          'the paperwork boring.\n\n'
          'Practically: one bank account for income, one for tax, and a '
          'standing transfer of about a fifth the moment a payment lands. '
          'When the tax bill comes it is an inconvenience rather than a '
          'disaster, and that is the whole game.\n\n'
          'If you are VAT registered, the VAT you charged is not your money '
          '— it is HMRC\'s, sitting in your account. Move that portion aside '
          'too, on the day, every time.\n\n'
          'On accountants: a good one pays for themselves the first time '
          'they find something you would have missed. Ask other freelancers '
          'rather than picking the cheapest listing. And bring them records '
          'monthly, not one heroic envelope in February.',

      'Since you asked, the bit freelancers get wrong most often:\n\n'
          'One: treating the VAT on invoices as revenue. It is not. It '
          'belongs to HMRC.\n\n'
          'Two: spending the tax money. It was never yours. A separate '
          'account, fed on the day you are paid, is the only reliable fix.\n\n'
          'Three: missing the registration threshold. It is measured over a '
          'rolling twelve months, so a good autumn can push you over for a '
          'job you quoted in spring. Keep an eye on it.\n\n'
          'Four: receipts in a shoebox. Photograph them the day you get '
          'them. Every receipt is a tiny tax reduction you are otherwise '
          'handing back.\n\n'
          'And keep a note of what you have earned this tax year in this '
          'app — ask me "how much have I received" and it is on file here '
          'anyway.',
    ], q);
  }

  // -- cash flow -----------------------------------------------------------

  String cashflow(LocalFacts f, String q) {
    if (_neg(q)) {
      return _pick([
        'Understood. If cash is comfortable, that is the moment to make it '
            'do something — set the tax aside, pay down anything expensive, '
            'and top up the buffer rather than letting it quietly get spent.',
        'Fair enough. Worth keeping the habit of asking the question anyway: '
            'a dry spell that is forecast is an inconvenience; one that '
            'arrives unannounced is a crisis.',
      ], q);
    }
    final owed = f.clients.where((c) => f.balanceOf(c) > 0).toList();
    final total = owed.fold<double>(0, (a, c) => a + f.balanceOf(c));
    final head = owed.isEmpty
        ? 'Nothing outstanding on file, which means every number below is '
            'about money already banked.'
        : 'On file you are owed ${_plain(total)} across ${owed.length} '
            '${owed.length == 1 ? 'client' : 'clients'} — chasing that is the '
            'cheapest cash flow improvement available to you.';
    return '''$head

Cash flow is timing, not profit. A profitable month can still bounce a bill
because the money lands in March and the bill is due in February.

Three levers, in the order they actually work:

One, pull income forward. Half up front is the single biggest fix. Even
shifting from "on delivery" to "half now, half on delivery" changes your
month.

Two, push costs out, politely. Suppliers and software subscriptions are
usually negotiable on annual plans, and "can we move to quarterly" is a
normal request.

Three, smooth the spikes. When a big payment lands, do not let it all feel
like yours: tax aside first, then a buffer of two months of your basic
outgoings, then the rest is actually yours.

Short-term panicked version: list every bill that leaves in the next 30
days, list every payment you are confident about, and act only on the gap.
The gap is usually smaller than the dread.

For what it is worth: you are owed what is on file. The single highest-value
hour available to you this week is probably sending one more reminder.''';
  }

  // -- deposits -----------------------------------------------------------

  String deposit(LocalFacts f, String q) {
    if (_neg(q)) {
      return _pick([
        'Understood. Just know what you are choosing: without a deposit you '
            'are financing their project, at zero interest, from your own '
            'account. For trusted repeat clients that is a kindness worth '
            'doing. For strangers it is how unpaid work starts.',
        'Fair enough — for a small job with someone reliable it is a fine '
            'call. If this is a big job or a new client, though, even a '
            'token 20% up front changes the psychology of the whole thing.',
      ], q);
    }
    return _pick([
      'Yes — half up front for new clients is the default worth having.\n\n'
          'Why it works: it filters out the people who were never going to '
          'pay, it covers your first week of effort, and — the part nobody '
          'says out loud — a client who has paid something behaves '
          'differently. They reply faster, they commit to decisions, the '
          'project has weight.\n\n'
          'How to ask for it without it sounding like distrust: make it '
          'policy, not suspicion. "I take a 50% deposit to book the slot in '
          'the diary, with the balance on delivery." Same sentence every '
          'time, said lightly, at the point of saying yes.\n\n'
          'What to do with it: book it in, mark the job as started, and do '
          'not treat it as fully earned until the work is delivered. On the '
          'record here, a deposit is just the first payment against the '
          'total — say "Acme paid 800" and the balance works itself out.',

      'For new clients, yes. For people you have worked with for years, '
          'your call.\n\n'
          'The useful splits, hardest to softest:\n\n'
          '50% up front, 50% on delivery — the freelancer\'s classic, and '
          'the right default.\n\n'
          'A third / third / third — deposit, midpoint, delivery — for '
          'longer projects, so cash keeps arriving.\n\n'
          'A small booking fee (10–20%) then the rest on delivery — easiest '
          'to swallow for cautious clients, and still enough to separate the '
          'serious from the curious.\n\n'
          'Whatever you pick, put it in the quote and the first email, not '
          'in a later awkward paragraph. The deposit conversation is '
          'painless at day zero and horrible at day ten.',

      'Short answer: take it.\n\n'
          'The deposit is not really about the money, it is about mutuality. '
          'Once they have paid, you are both in it. Without it you are doing '
          'favours for a stranger with a deadline.\n\n'
          'Script you can copy: "Great — to get started I take a 50% deposit '
          'to hold the slot, with the balance due on delivery. I will send '
          'the invoice and a short scope note today, and we can start '
          'Monday."\n\n'
          'One caution: if the deposit is refundable, say so, and say under '
          'what conditions. Ambiguity about deposits is where client '
          'relationships go to die.',
    ], q);
  }

  // -- retainers -----------------------------------------------------------

  String retainer(LocalFacts f, String q) {
    if (_neg(q)) {
      return _pick([
        'Understood — a retainer is not automatically the right shape. If '
            'the work comes in unpredictable bursts, pay-as-you-go is '
            'honest and simpler for both sides.',
        'Fair enough. If you do ever want one, the easiest sell is to offer '
            'it to the client who already asks for the most ad-hoc work — '
            'they are buying certainty too.',
      ], q);
    }
    final retainers = f.clients.where((c) => c.isRetainer).toList();
    final head = retainers.isEmpty
        ? 'You have no retainers on file. The usual way in is to offer one '
            'to the client who already sends you the most surprise work.'
        : 'On file: ${retainers.map((c) => '${c.name} at ${_plain(c.monthly!)}/month').join(', ')}.';
    return '''$head

A retainer is not "a discount for regular work", it is a different product:
they are buying your availability, not a deliverable.

What makes one work:

- Define the unit in writing. Hours ("up to 10 hours a month") or outcomes
  ("two rounds of updates a month"). Never "as needed" — that is a blank
  cheque drawn on your evenings.
- Put a rollover rule in it. Unused hours expire at month end, or half of
  them roll. Without this, one quiet month followed by a frantic one empties
  your calendar for free.
- Invoice monthly, in advance. Retainers are cash flow smoothing; charging
  after the fact defeats the point.
- Review the price every six months. Costs rise; the retainer from last
  winter is quietly worth less.

How to pitch it: "Rather than quoting each time, some clients prefer a
monthly retainer of X for up to Y hours — it means you get priority and I
can plan around you." Priority is the word that sells it.

And keep a retainer client in this app like any other — the monthly figure
lives on their record, so you always know what is contracted.''';
  }

  // -- scope creep ---------------------------------------------------------

  String scopeCreep(LocalFacts f, String q) {
    if (_neg(q)) {
      return _pick([
        'Understood — letting this one go is a decision, and sometimes a '
            'wise one. Just make it a decision: note what you absorbed, and '
            'put the boundary in the next quote so the same job does not '
            'grow twice.',
        'Fair enough. If you do absorb it, do it visibly: "I will do this '
            'one as a favour this time" costs you nothing in dignity and '
            'buys a lot of goodwill, where silent absorption just teaches '
            'them that the edges are soft.',
      ], q);
    }
    return _pick([
      'Scope creep is rarely malicious — it is usually a client who genuinely '
          'forgets what was agreed, not one who is cheating you. The fix is '
          'friendly and written.\n\n'
          'The script: "Happy to do that — it sits outside what we agreed, '
          'so it will be an extra 350 and about three days. Shall I fold it '
          'into this phase, or quote it separately?" Notice what that does: '
          'it does not accuse, it prices, and it hands them a decision.\n\n'
          'Three structural fixes that stop it recurring:\n\n'
          'One, a scope note in the original quote — deliverables listed, '
          'and "changes to the brief are quoted separately" at the bottom.\n\n'
          'Two, a revision limit. "Two rounds of revisions included" is not '
          'mean, it is professional, and the third round becomes a '
          'conversation rather than a hostage situation.\n\n'
          'Three, a change log. One line per extra request with the price. '
          'Clients who see the running total stop asking so casually.',

      'The rule: everything outside the written scope is a change order, '
          'however small it looks.\n\n'
          'Not because small extras cost much — they do not — but because '
          'unpriced extras reset the client\'s expectation of where the '
          'edges are. Today it is a quick extra page. In three weeks it is '
          '"can you just also do the app".\n\n'
          'The sentence that pays for itself: "That is a change to the '
          'scope, so I will send a quick quote for it — should take ten '
          'minutes."\n\n'
          'Deliver it warmly, with a number, within the hour. Surprise '
          'invoices are hostile; surprise quotes for surprise requests are '
          'just how the job works. Most of the time they say yes, because '
          'the thing they asked for turns out to be worth the money to '
          'them — and that is how you learn your prices were probably too '
          'low anyway.',
    ], q);
  }

  // -- saying no -----------------------------------------------------------

  String sayNo(LocalFacts f, String q) {
    if (_neg(q)) {
      return _pick([
        'Understood — if you are not saying no, decide soon and say so '
            'warmly. A maybe that drifts for a week is worse for both of you '
            'than a fast, kind yes.',
        'Fair enough. If it is a yes leaning on a no somewhere, the kindest '
            'version is a clear answer with a reason, not a soft maybe.',
      ], q);
    }
    return _pick([
      'Say it warm, say it fast, and do not over-explain. A short no keeps '
          'the relationship; a vague maybe burns it slowly.\n\n'
          'The script: "Thank you for thinking of me for this — I am going '
          'to pass, as the timing does not work with what I have committed '
          'to. If it helps, [Name] does this kind of work well."\n\n'
          'What that does: thanks them, declines clearly, gives a reason '
          'that is about capacity rather than them, and offers a referral '
          'which costs you nothing and makes you look generous.\n\n'
          'Variations worth having in your pocket:\n\n'
          'For bad money: "This one is outside the budget I can do it for — '
          'happy to share what a version at X would look like if useful."\n\n'
          'For bad fit: "I do not think I am the right person for this, and '
          'you deserve someone who is."\n\n'
          'For bad vibes: no reason at all. "Thanks, but this one is not '
          'for me." You are allowed to end a sentence there.',

      'A no is a sentence, not a negotiation. The mistake is dressing it up '
          'so politely that the client hears "ask me again".\n\n'
          'Template: "Thanks for asking — I will pass on this one." Full '
          'stop. Add a reason only if you want to; add a referral only if '
          'you have one.\n\n'
          'If they push back, resist the urge to invent reasons to defend '
          'the no. "It is not the right fit for me at the moment" repeated '
          'calmly is complete.\n\n'
          'And do not forget the actual operational bit: if you have had a '
          'call or they sent a brief, reply to that thread. A no that '
          'arrives as silence is remembered differently from a no that '
          'arrives as kindness.',
    ], q);
  }

  // -- negotiation ---------------------------------------------------------

  String negotiate(LocalFacts f, String q) {
    if (_neg(q)) {
      return _pick([
        'Understood — hold the line on price. If they walk over the number, '
            'it says something about the project, not about you.',
        'Fair enough. If it comes back round, you have not lost anything by '
            'the price staying where it is; "that is the best I can do and '
            'I am keen to do it" is a complete sentence.',
      ], q);
    }
    return _pick([
      'Never discount without getting something. The trade is the whole '
          'art.\n\n'
          '"I can do it for 1800 rather than 2100 if we cut the second round '
          'of revisions." "I can meet 1900 if you can pay 50% up front." '
          '"Happy to do the smaller budget version — here is what falls '
          'out."\n\n'
          'Each of those protects something: your margin, your cash flow, or '
          'the scope. A straight discount protects nothing and is remembered '
          'as your real price forever.\n\n'
          'If the number is simply too far apart, say so honestly and stop: '
          '"I do not think I can get there and do the job properly, which '
          'is not fair on either of us. If the budget moves, I would still '
          'love to do it."\n\n'
          'And the underrated move: ask what budget they had in mind before '
          'you negotiate against yourself. Half the time the gap was 200, '
          'not 2000.',

      'The three moves that work, roughly in order.\n\n'
          'One, trade, never cut. Every concession gets a concession: a '
          'lower price buys an earlier start date, a longer deadline, a '
          'smaller scope, or payment up front. "I can do 1600 if we start '
          'in three weeks rather than tomorrow."\n\n'
          'Two, reframe the scope before the number. Often the budget is '
          'fine for less. "At that budget, I would suggest we do the '
          'checkout in phase two — want me to requote?" You keep your rate, '
          'they keep their budget, and phase two is a second project.\n\n'
          'Three, if you do discount, discount once and name it. "As a '
          'one-off, I can do 1900." Never let a discount become the new '
          'anchor for the next job — quote the standard rate again and see '
          'if they blink. Usually they do not, because they were negotiating, '
          'not counting.',

      'One more thing that helps: know your walk-away number before the '
          'conversation, not during it.\n\n'
          'If the budget is 1200 and the job genuinely takes five days at '
          'your rate, the answer is a smaller version of the job, or a no. '
          'The version of you that has already agreed the floor does not get '
          'talked past at 11pm on a Wednesday.\n\n'
          'Useful lines:\n\n'
          '"What is it about the number that feels high?" — makes them '
          'articulate the real objection, which is rarely the money.\n\n'
          '"I want to do this, and I want to do it at a price that lets me '
          'do it properly. Here is what I can do at your budget." — keeps '
          'you on their side of the table while holding the rate.\n\n'
          '"Let me send a revised quote showing both options." — buys you '
          'time and usually ends the haggling, because spreadsheets are '
          'harder to argue with than voices.',
    ], q);
  }

  // -- explaining a charge -------------------------------------------------

  String explainCharge(LocalFacts f, String q) {
    if (_neg(q)) {
      return _pick([
        'Understood — leave it. Some invoices get queried once and then '
            'silently paid, which is often what this is.',
        'Fair enough. If it does come back, the answer is almost always the '
            'same: calmly restate what was delivered, at the rate agreed, '
            'and let the work speak.',
      ], q);
    }
    return _pick([
      'The trick is to explain the scope, not defend the price.\n\n'
          'Clients do not really think your rate is too high; they think '
          'they do not understand what they got for it. So show them.\n\n'
          'Script: "Happy to walk through it — the 2100 covers the '
          'discovery session, the design of four key screens, the build, '
          'and two rounds of revisions. The bit that usually takes people '
          'by surprise is the build: about two days of it is invisible '
          'work — testing on real devices, performance, the boring parts '
          'that stop it breaking."\n\n'
          'Then, if they are still unhappy, offer the trade rather than the '
          'cut: "If it is over what you had planned, I can take the '
          'animations out and do it for 1700."\n\n'
          'Never open with a discount. An invoice questioned is usually an '
          'invoice being processed, and the first person to flinch teaches '
          'them the price was soft.',

      'What works: warmth, specifics, and zero defensiveness.\n\n'
          '"Great question — happy to break it down." Then the actual '
          'breakdown: design 1200, build 700, project management and '
          'revisions 200. Numbers, in a list, without adjectives.\n\n'
          'If they push on a line item, that is where you find out what the '
          'real objection is. Sometimes it is money; often it is that they '
          'never understood what "discovery" was and are embarrassed to '
          'ask. One sentence fixes it: "That is the two hours we spent '
          'agreeing what we were building before I started — cheaper than '
          'building the wrong thing."\n\n'
          'And if the query is genuinely wrong — they are disputing work '
          'that was done — do not get drawn into a thread. "The work '
          'listed was agreed on [date] in writing. Happy to get on a call '
          'and walk through it together." Call, not chat. Tone survives '
          'badly in text.',
    ], q);
  }

  // -- refunds -------------------------------------------------------------

  String refund(LocalFacts f, String q) {
    if (_neg(q)) {
      return _pick([
        'Understood — keep the money and hold the line. If they escalate, '
            'the written scope and the deposit terms are what you lean on, '
            'and they are usually enough.',
        'Fair enough. If it is a relationship you want to keep, a part '
            'refund against the work already done is a middle path — but '
            'decide that from the paperwork, not from the guilt.',
      ], q);
    }
    return _pick([
      'A refund is a business decision, not a moral referendum. Work out '
          'what you owe them in time and goodwill, then decide.\n\n'
          'The usual rules:\n\n'
          'Work not started: refund the deposit, less any honest admin fee '
          'if you said there would be one. Fighting over a deposit you have '
          'not earned costs more reputation than it saves.\n\n'
          'Work part-done: they owe for the work done, at the agreed rate. '
          '"I can refund the second half and keep 800 for the work '
          'completed to date" is clean and defensible.\n\n'
          'Work delivered and they just do not like it: that is not a '
          'refund situation, that is a revisions conversation — within the '
          'limit you agreed.\n\n'
          'Whatever you decide, put it in writing, mark it in your records '
          'the day it happens, and end the message with something warm. The '
          'client who leaves with a fair refund comes back; the one who '
          'leaves feeling beaten tells everyone.',

      'Short version: refund what you have not earned, keep what you have, '
          'and say so in one clear message.\n\n'
          '"Understood — I will refund 1000 of the 1500 deposit, keeping '
          '500 for the work completed to date. That will be back with you '
          'within [x] days. I am sorry this one did not work out, and I '
          'genuinely wish you well with it."\n\n'
          'That message does four things: it decides, it explains, it '
          'commits to a date, and it ends the relationship without poison. '
          'Send it as soon as you have decided, not when you have processed '
          'it — the update arriving first is what stops the second email.',
    ], q);
  }

  // -- cancellations -------------------------------------------------------

  String cancellation(LocalFacts f, String q) {
    if (_neg(q)) {
      return _pick([
        'Understood — keep it alive then. Worth a quick note in the record '
            'about what is holding it up, because "they went quiet" in '
            'six months is a story you will have forgotten.',
        'Fair enough. If it does wobble later, a short "still keen, here is '
            'where we got to" email reactivates more projects than any '
            'follow-up technique.',
      ], q);
    }
    return _pick([
      'First: find out whether it is cancelled or just going quiet, because '
          'they need different answers.\n\n'
          'If cancelled mid-job, the honest position is: work completed to '
          'date is payable, at the agreed rate. The way to make that land '
          'well is to have said it at the start — a line in the quote like '
          '"cancellation part-way through is charged for work completed, '
          'plus 20% to cover the booked slot" is standard and rarely '
          'argued with afterwards.\n\n'
          'What to actually say: "Sorry to hear it — I will stop here and '
          'invoice for the work completed to date, which comes to X. All '
          'the files so far are yours, and I am happy to hand over in a '
          'call if that helps."\n\n'
          'Then: hand over the files anyway. The way people are treated at '
          'the end of a cancelled project is what they remember, and what '
          'they tell the next person who asks about you.\n\n'
          'For no-shows and silent disappearances: one firm message asking '
          'for a decision by a date, then the invoice for work done, then '
          'stop chasing politely after two goes.',

      'The rule: cancellation costs are about the slot, not the hurt.\n\n'
          'You blocked time. That time had value whether or not they used '
          'it. A cancellation fee of 20–25% of the project for a late '
          'cancellation is normal, and for a booking fee forfeited is even '
          'more normal.\n\n'
          'If they cancelled early and fairly — a week out, no work done — '
          'refund cleanly and wish them well. If they cancelled the day '
          'before a start date you turned other work down for, the '
          'forfeited deposit is exactly what it was for, and you can say '
          'so, kindly: "The deposit covered holding your slot, which meant '
          'I turned down other work that week, so I am not able to refund '
          'it — but I would happily rebook you for [date]."\n\n'
          'Either way, mark it in your records so the next quote for them '
          'starts from what actually happened.',
    ], q);
  }

  // -- contracts -----------------------------------------------------------

  String contract(LocalFacts f, String q) {
    if (_neg(q)) {
      return _pick([
        'Understood — but do not skip the written summary, even if you skip '
            'the contract. One email saying "so: scope, price, timeline, '
            'terms" is a contract for most practical purposes and takes '
            'four minutes.',
        'Fair enough for a small favour of a job. For anything with a real '
            'number attached, the paperwork is the cheapest insurance you '
            'will ever buy — an hour now versus a month of "that is not what '
            'we agreed" later.',
      ], q);
    }
    return _pick([
      'You do not need a lawyer for most freelance work; you need five '
          'things in writing, agreed before anything starts.\n\n'
          'One, scope: what is being delivered, listed. Two, price: the '
          'number and the payment terms. Three, timeline: when, and what '
          'happens if they are slow to respond — a "feedback within 5 '
          'working days or the schedule shifts" clause saves endless '
          'arguments. Four, revisions: how many rounds are included. Five, '
          'cancellation: what is owed if it stops part-way.\n\n'
          'All five fit in a short email. "Just to confirm what we agreed: '
          'I will build X for Y, on Z terms, starting [date], with two '
          'rounds of revisions included. Reply to confirm and I will get '
          'started." A client replying "yes, confirmed" has signed a '
          'contract, for practical purposes.\n\n'
          'Upgrade to a proper document when: the number is big enough that '
          'losing it would hurt, the client is a corporation with a legal '
          'team, or you are handing over something they will make money '
          'from for years. Then a fixed-fee contract from a reputable '
          'template is money well spent.',

      'The short version: get the five pillars in writing, even if the '
          'writing is one email.\n\n'
          'Scope. Price and terms. Timeline. Revision limit. What happens on '
          'cancellation.\n\n'
          'Send it yourself — do not wait for their paperwork. "Confirming '
          'what we agreed" is a friendly email, not a legal threat, and it '
          'becomes exhibit A the moment anything wobbles.\n\n'
          'Watch for the clauses larger clients send your way: unlimited '
          'revisions, "work for hire" on everything you produce including '
          'your own tools, payment 60 days after invoice, and indemnities '
          'you cannot possibly honour. All four are negotiable, and '
          '"can we discuss this clause" is a perfectly normal sentence to '
          'put in writing.\n\n'
          'And keep your own template. The first job you do with the fifth '
          'new client this year should not involve writing a contract from '
          'scratch for the fifth time.',
    ], q);
  }

  // -- onboarding ----------------------------------------------------------

  String onboarding(LocalFacts f, String q) {
    if (_neg(q)) {
      return _pick([
        'Understood — no formal process needed for this one. Even so, one '
            'email confirming scope, price and start date protects you both '
            'for about four minutes of effort.',
        'Fair enough. The light-touch version: write the scope note anyway. '
            'It is not bureaucracy, it is the thing you will be grateful '
            'for in week four when the "quick extra" arrives.',
      ], q);
    }
    return _pick([
      'The first week with a new client sets the whole relationship. Spend '
          'an hour making it deliberate.\n\n'
          'Day one: send the welcome note. Scope, price, timeline, invoice '
          'terms, and how you like to work — what you need from them, and '
          'by when. It reads as professionalism because it is.\n\n'
          'Then get the three things that block everything: who signs off '
          '(there is always one person, and it is rarely the one on the '
          'call), where the assets live, and how decisions get made — '
          'email, a shared doc, a weekly call.\n\n'
          'Book the first check-in before you need it: "I will send the '
          'first cut on the 14th — shall we look at it together on the '
          '15th?" A client who sees work in progress early never becomes a '
          'client who is surprised.\n\n'
          'And record them here the day they start — "add client Acme for '
          '2100" — so the chasing machinery exists before there is anything '
          'to chase.',

      'A smooth onboarding is mostly just removing the questions before '
          'they are asked.\n\n'
          'In the first exchange, answer: what happens first, what you need '
          'from them, when they will see something, how feedback works, and '
          'when the money moves. Five lines. That is the whole ceremony.\n\n'
          'The part that feels awkward and is actually a kindness: say what '
          'you are not doing. "This covers the homepage and checkout; '
          'blogging and the logo are out of scope for this figure." Now '
          'the extra request in week three has a documented boundary to '
          'bounce off.\n\n'
          'If they are a proper company, ask for a purchase order now, not '
          'when you invoice. Getting a PO retroactively can add 30 days to '
          'payment, and it is nobody\'s fault, and it still happens.\n\n'
          'Last one: put the first payment on the record the day it lands. '
          'A new client is a new name in this app, and from then on their '
          'balance is a fact rather than a worry.',
    ], q);
  }

  // -- timelines -----------------------------------------------------------

  String timeline(LocalFacts f, String q) {
    if (_neg(q)) {
      return _pick([
        'Understood — no date yet. If the client is pressing for one, '
            '"I can give you a firmer date once we have agreed the scope" '
            'is a complete and professional answer.',
        'Fair enough. When you are ready to commit, estimate from the day '
            'count rather than the hope, and add a week you do not tell '
            'anyone about.',
      ], q);
    }
    final open = f.deadlines.where((d) => !d.done).length;
    final head = open == 0
        ? 'Nothing is on your deadline list, so this is pure planning.'
        : 'You have $open open deadline${open == 1 ? '' : 's'} on file — worth '
            'scheduling this around those rather than on top of them.';
    return '''$head

Estimate a timeline the way you would estimate a price: from the day count,
not the deadline you would like to hit.

- Write the phases: discovery, first cut, revisions, handover. Give each a
  day count. Halve your optimism for the revision phase specifically — that
  is where calendars go to die.
- Add a buffer of about 20% that you never mention. "Three weeks" with a
  week hidden inside is how you finish on time looking relaxed.
- Put your own buffer dates in this app as deadlines, so the calendar sees
  the real plan rather than the client-facing one.

Then communicate in halves, not wholes. "First cut Wednesday, full thing the
week after" beats three weeks of silence followed by a delivery — clients
who are updated weekly almost never complain about dates.

If they need it faster, do not simply say yes: "I can do the 14th if we trim
X" is the sentence that keeps both the date and the margin honest.

And when they change something mid-flight: "That will push us to the 21st,
as it adds about three days" — in writing, the same day. Dates do not shift
quietly.''';
  }

  // -- workload ------------------------------------------------------------

  String workload(LocalFacts f, String q) {
    if (_neg(q)) {
      return _pick([
        'Understood — you are on top of it. If that changes, the two-minute '
            'version of this conversation is: list everything, price the '
            'days, say no to one thing.',
        'Fair enough. Worth checking anyway that the diary matches what you '
            'have promised — ask me "what is due" and you will see the real '
            'list.',
      ], q);
    }
    final dueSoon = f.deadlines.where((d) => !d.done).length;
    final open = f.clients.where((c) => c.status == 'active').length;
    final head = (dueSoon == 0 && open == 0)
        ? 'On file nothing is screaming: no open deadlines and no active '
            'client jobs. So the overload is either off the books or in '
            'your head — which is still real, just addressable differently.'
        : 'On file: $open active client job${open == 1 ? '' : 's'} and '
            '$dueSoon open deadline${dueSoon == 1 ? '' : 's'}. That is the '
            'real list, and it is usually shorter than the one in your head '
            'at midnight.';
    return '''$head

Being swamped is almost never one big thing; it is fifteen small ones with no
order. So:

One, empty your head. Write every commitment — client work, admin, the
favour, the thing you said you would look at. Twenty minutes, everything
down, no prioritising yet.

Two, mark what actually has to happen this week. Usually about four items.
Everything else is either delegable, deferrable, or declineable.

Three, protect the days. Block the deep-work days in the diary before the
meetings eat them. A calendar with no white space is a plan to do nothing
well.

Four, at the edge of the list, say no to one thing. Not five — one. The
maths of overload only ever needs one subtraction to start working.

If the workload is money-driven rather than time-driven, ask me about
chasing what you are owed: the fastest relief is usually already invoiced
and sitting in someone else's inbox.''';
  }

  // -- hiring --------------------------------------------------------------

  String hiring(LocalFacts f, String q) {
    if (_neg(q)) {
      return _pick([
        'Understood — keeping it solo for now. If it comes round again, the '
            'first hire that pays for itself is usually the boring work: '
            'admin, invoicing, file wrangling.',
        'Fair enough. When you do want the time back, subcontract the parts '
            'you are slowest at first, not the parts you like least — the '
            'first is a costing, the second is just drift.',
      ], q);
    }
    return _pick([
      'Hire for the hours you keep not doing, not for the work you dislike.\n\n'
          'The reliable first moves, cheapest first:\n\n'
          'One, subcontract a defined slice. A specific deliverable, a fixed '
          'price, a date. "Build the email templates for 600, done by the '
          '14th." You keep the client relationship and the margin.\n\n'
          'Two, buy back admin. Bookkeeping, invoice chasing, inbox triage — '
          'a few hours a week of a virtual assistant usually returns more '
          'billable time than any tool.\n\n'
          'Three, only then hire toward delivery. And with someone new, run '
          'one small paid job end-to-end before you promise anything bigger '
          'to a client on their behalf.\n\n'
          'What to watch: your margin. If you charge 2100 and pay 1200 for '
          'the work, the remaining 900 has to cover your sales, management '
          'and risk — which is fine as an occasional trade of time for '
          'sanity, less fine as a business model.\n\n'
          'And write down how they work before they start: file structure, '
          'naming, the tone. "Like me" is not an instruction.',

      'The short version: subcontract the defined bits, automate or '
          'delegate the admin, hire people only after a paid trial.\n\n'
          'Where to find them: the people you already know are still the '
          'best source — a recommendation from a freelancer friend beats '
          'any platform. Communities and portfolios second; job ads last.\n\n'
          'How to run it: one small paid trial project with a real deadline '
          'and a real client deliverable. Not a test task — nobody good '
          'does those, and it tells you nothing about how they communicate '
          'when it matters.\n\n'
          'The part nobody tells you: your first subcontractor will cost you '
          'time before it saves any. Management is a job. Budget two weeks '
          'of double effort and you will be pleasantly surprised by one.',
    ], q);
  }

  // -- tools ---------------------------------------------------------------

  String tools(LocalFacts f, String q) {
    if (_neg(q)) {
      return _pick([
        'Understood — no new subscriptions today. Fair: half of running a '
            'small business is resisting software that promises to run it '
            'for you.',
        'Fair enough. If the current setup mostly works, that is rarer than '
            'it sounds and worth leaving alone.',
      ], q);
    }
    return _pick([
      'The honest answer: the best tool is the one you will actually open '
          'on a bad Thursday.\n\n'
          'For invoicing, something with recurring invoices and automatic '
          'reminders, because the reminders are the feature. For time '
          'tracking, whatever is on your phone with one tap — if logging an '
          'hour takes a minute, you will stop logging hours within a week. '
          'For contracts, a template you reuse beats any subscription. For '
          'getting paid, bank transfer details on the invoice and a '
          'standing Friday slot for chasing.\n\n'
          'The test before subscribing to anything: what will it do that a '
          'spreadsheet and a calendar reminder cannot? If the answer is '
          'mainly "it looks professional", you are buying stationery.\n\n'
          'And the rule that saves the most money: every six months, list '
          'what you pay for software, be honest about what got used, cancel '
          'the rest. Subscriptions are the only bills that increase by '
          'doing nothing.',

      'Keep the stack small enough to fit in your head. Three tools, done '
          'well: one for invoices and chasing, one for files, one for the '
          'diary. Anything beyond that should replace something rather than '
          'join it.\n\n'
          'Signals a tool is actually earning its fee:\n\n'
          '- It chases money without you thinking about it.\n'
          '- It saved you an argument, because the scope was in it.\n'
          '- A client commented on how easy it was to pay.\n\n'
          'Signals it is not: you have not opened it in a fortnight, or you '
          'maintain it the way you maintain a houseplant.\n\n'
          'One thing worth paying for, always: proper backups of whatever '
          'holds your client list. Everything else can be rebuilt; that '
          'cannot. This app keeps your records on your phone — export them '
          'now and then.',
    ], q);
  }

  // -- drafting a message --------------------------------------------------

  /// Picks the situation from the question and produces a message the user
  /// can actually send, with the client's name and figure where the records
  /// have one.
  String draftMessage(LocalFacts f, String q) {
    final owing = f.clients.where((c) => f.balanceOf(c) > 0).toList()
      ..sort((a, b) {
        final aLate = a.isOverdueOn(f.today) ? 1 : 0;
        final bLate = b.isOverdueOn(f.today) ? 1 : 0;
        if (aLate != bLate) return bLate - aLate;
        return f.balanceOf(b).compareTo(f.balanceOf(a));
      });
    final lead = f.clients.firstWhere(
      (c) => c.status == 'lead',
      orElse: () => const Client(name: ''),
    );

    if (_neg(q)) {
      return _pick([
        'Understood — nothing sent. If you want to come back to it later, '
            'the words will still be here: just ask again.',
        'Fair enough. Sometimes the best message is the one you write and '
            'do not send; give it an hour and see how it reads.',
      ], q);
    }

    // Declining, refusing extra work, or saying no.
    if (RegExp(r'\b(no|decline|turn down|pass|reject|cannot take|'
            r'cant take|not taking|turn it down)\b').hasMatch(q)) {
      return _pick([
        'Here is one you can send:\n\n'
            '"Hi Sam — thank you for thinking of me for this. I am going to '
            'pass, as the timing does not work with what I have already '
            'committed to. If it helps, [Name] does this kind of work well '
            'and I am happy to introduce you. Wishing you luck with it."\n\n'
            'Short, warm, no invented excuses. If they push, "it is not the '
            'right fit for me at the moment" is a complete reply.',

        'Try this:\n\n'
            '"Hi Sam — really appreciate you asking. I cannot take this on '
            'right now without letting down work I have already promised. '
            'If your timeline shifts, I would be glad to revisit it."\n\n'
            'It declines clearly, keeps the door open without promising '
            'anything, and does not apologise for having standards.',
      ], q);
    }

    // Chasing money.
    if (owing.isNotEmpty &&
        RegExp(r'\b(chase|remind|payment|invoice|owe|owed|money|paid|'
            r'follow.?up|nudge|overdue|late)\b').hasMatch(q)) {
      final c = owing.first;
      final bal = f.balanceOf(c);
      final days = c.daysUntilDue(f.today);
      final lateBy = days != null && days < 0 ? -days : 0;
      final tone = lateBy > 21
          ? 'firmer'
          : lateBy > 0
              ? 'polite but direct'
              : 'friendly';
      return 'Here is a $tone one, ready to send to ${c.name} '
          '(${_plain(bal)} outstanding'
          '${lateBy > 0 ? ', $lateBy days late' : ''}):\n\n'
          '"Hi ${c.name.split(' ').first}, hope you are well. Just a gentle '
          'reminder that invoice ${_plain(bal)} is still outstanding — could '
          'you let me know when I should expect payment? Happy to resend '
          'the invoice if that helps."\n\n'
          'Adjust as needed, but keep the three parts: warm opening, the '
          'number and what it is for, and one clear ask (a date). If this '
          'is the second or third chase, drop the "happy to resend" and add '
          '"could you confirm a payment date this week?".';
    }

    // Asking for a deposit, or for money up front.
    if (RegExp(r'\b(deposit|up front|upfront|half now|book the slot)\b')
        .hasMatch(q)) {
      return _pick([
        'Here you go:\n\n'
            '"Great — I am happy to get started. To book your slot in the '
            'diary I take a 50% deposit up front, with the balance due on '
            'delivery. I will send the invoice and a short scope note '
            'today, and we can start Monday."\n\n'
            'It is policy-shaped rather than distrust-shaped, which is the '
            'whole trick. Say the same sentence every time and it stops '
            'feeling like a negotiation.',

        'Try this:\n\n'
            '"Brilliant, let us do it. My usual way of working is a small '
            'deposit to confirm the booking — 50% of the project, with the '
            'rest on delivery. Shall I send that over now?"\n\n'
            '"Shall I send that over now" turns a money conversation into '
            'an admin one, which is exactly where it belongs.',
      ], q);
    }

    // Saying the price for the first time.
    if (RegExp(r'\b(price|quote|charge|cost|figure|number|how much)\b')
        .hasMatch(q)) {
      final anchor = lead.amount != null
          ? ' (for ${lead.name} you have ${_plain(lead.amount!)} noted — '
              'if that is the number, use it confidently)'
          : '';
      return 'A price is best delivered as a short paragraph with the number '
          'in the middle of it, not dangling alone at the end:\n\n'
          '"Thanks for the brief — excited about it. Having looked at '
          'everything, the project comes to [amount], covering [the three '
          'main deliverables], with two rounds of revisions included. That '
          'holds for 30 days. Happy to walk through the details if useful."'
          '$anchor\n\n'
          'What that does: warmth first, number second, scope third, and a '
          'validity date last. Never write "I was thinking maybe around '
          '..." — the client will hear the lowest number in the sentence '
          'and remember it as the real one.';
    }

    // Saying no to extra work mid-project.
    if (RegExp(r'\b(extra|more work|scope|change|added|another|revision)\b')
        .hasMatch(q)) {
      return _pick([
        'Here is the polite refusal that still gets paid:\n\n'
            '"Happy to do that — it sits outside what we agreed, so it '
            'would be an extra [amount] and about [time]. Shall I fold it '
            'into this phase, or quote it separately?"\n\n'
            'No accusation, a price, and a decision for them to make. Most '
            'of the time they say yes, because the thing they asked for is '
            'worth the money to them.',

        'Try this:\n\n'
            '"Good idea — that is a change to the original scope, so let me '
            'quote it properly rather than squeeze it in. I will send a '
            'quick number today."\n\n'
            'The phrase "quote it properly" is doing all the work: it '
            'frames the extra as normal process, not as you being awkward.',
      ], q);
    }

    // Nothing recognisable: a general-purpose opener with their data in it.
    final who = owing.isNotEmpty
        ? owing.first.name
        : lead.name.isNotEmpty
            ? lead.name
            : '';
    if (who.isEmpty) {
      return 'Tell me who it is for and roughly what you want to say — '
          'chasing a payment, naming a price, declining work, asking for a '
          'deadline — and I will draft the whole message for you to copy.\n\n'
          'Example: "draft a chase message" and I will write one, with your '
          'figures already in it.';
    }
    return 'Tell me what you want to say to $who and I will draft it. The '
        'ones I am best at:\n\n'
            '  - chasing what they owe\n'
            '  - naming a price without flinching\n'
            '  - asking for a deposit\n'
            '  - declining something politely\n'
            '  - explaining a charge\n\n'
            'Something like "draft a chase message for $who" and it is '
            'written, with the amount already filled in.';
  }

  // -- helpers -------------------------------------------------------------

  /// True when the question is telling us not to do the thing rather than
  /// asking about it. "Don't invoice yet" is a decision, not a question, and
  /// answering it with invoice advice reads like we were not listening.
  static bool negated(String q) => _neg(q);

  static bool _neg(String q) => RegExp(
        r"\b(dont|don't|do not|never|not yet|hold off|hold it|stop|wait|"
        r"shouldnt|shouldn't|no more|dont want|i dont|leave it|not sending|"
        r'not going to|not taking)\b',
      ).hasMatch(q);

  String _plain(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  /// Deterministic variation, same algorithm as the assistant's own: the same
  /// question always gets the same wording, which is what keeps all of this
  /// testable without a model.
  String _pick(List<String> options, String seed) {
    var hash = 0x811c9dc5;
    for (final unit in seed.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return options[hash % options.length];
  }
}
