import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

/// About Koru, and the three documents that go with it.
///
/// All four live in one file because they are one set: same frame, same
/// typography, read in the same visit from the last group on the Settings
/// index. None of them needs state, a provider or a controller, so each is a
/// plain widget over the same [_DocScaffold] rather than four screens that
/// drift apart in style.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _DocScaffold(
      title: 'About Koru',
      lead: 'Koru is a local-first assistant for people who run their own work. '
          'It knows your clients, what they owe you and what is due, and it runs '
          'on your phone.',
      sections: [
        _DocSection(
          'What it is',
          paragraphs: [
            'An Android app for freelancers and one-person businesses. You say '
                'things like "Bilal paid 500" and ask questions about your work, '
                'and Koru keeps the records, the balances and the deadlines in '
                'one place.',
            'The loop it exists for is deliberately small: clients, what is owed, '
            'what is due, and money received. Features that did not serve that '
            'loop were cut rather than left half working.',
          ],
        ),
        _DocSection(
          'Who it is for',
          paragraphs: [
            'Somebody carrying a handful of clients who wants one place that knows '
            'the whole picture, without signing up for a CRM, creating an account '
            'or taking out a subscription.',
            'It keeps working with no internet connection. The local model '
            'reads your own records and answers from them, and the calendar, '
            'the capacity meter, projects and backups all run here too. If that '
            'model is not running, Koru says so rather than answering from its '
            'own rules.',
          ],
        ),
        _DocSection(
          'Local first, on purpose',
          paragraphs: [
            'Everything Koru knows lives in a database on this device. There is no '
            'Koru server, no account system and no analytics. The rule the app is '
            'built around: your clients and your money are not training data for '
            'anyone else.',
            'Only questions that genuinely need a frontier model can go onward, only '
            'if you have set up a cloud provider yourself, and only a pseudonymous '
            'summary of your context travels with them: never your nickname, your '
            'name, your client names or your amounts. Settings shows the exact text '
            'before anything is sent.',
          ],
        ),
        _DocSection(
          'The name and the character',
          paragraphs: [
            'A koru is the unfurling frond of a New Zealand fern, a Māori symbol of '
            'new growth. Koru is also the small character in the chat bar who '
            'blinks, thinks and waves when you tap him.',
          ],
        ),
        _DocSection(
          'Licence',
          paragraphs: [
            'The code is released under the MIT licence; see the LICENSE file that '
            'ships with the source. Koru is an independent project with no company '
            'behind it, so these pages, the README and the app itself are the whole '
            'of what is on offer.',
          ],
        ),
      ],
    );
  }
}

/// What is stored, where it sits, and what is sent when.
///
/// Written to be checkable rather than reassuring. Every claim here is a
/// property of the code: no analytics packages in pubspec.yaml, the database in
/// the app's own directory, and the nickname stripped out of the packet before
/// a cloud prompt is ever built.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _DocScaffold(
      title: 'Privacy Policy',
      lead: 'The short version: everything Koru knows stays on this device, and '
          'nothing in this app reports anything about you to anyone.',
      sections: [
        _DocSection(
          'The short version',
          bullets: [
            'Your data is stored on this phone, in a database only this app can '
                'open.',
            'There are no analytics, no advertising, no crash reporting and no '
                'tracking of any kind. None of those exist in the app, and there '
                'is no account, so there is nothing to identify you by.',
            'Nothing is uploaded unless you turn on the cloud model and ask a '
                'question that is routed to it.',
            'Everything, including your provider keys, can be deleted from Settings '
            '> Data.',
          ],
        ),
        _DocSection(
          'What is stored, and where',
          paragraphs: [
            'Koru keeps one SQLite database in this app\'s private storage on your '
            'Android device. It holds your context (nickname, stage, work, goals, '
            'focus), your clients, payments, deadlines, projects, in-app calendar '
            'entries, help topics, the conversation, and your settings.',
            'Cloud API keys are handled differently. Each one is encrypted with a '
            'key held in the Android Keystore, which never leaves the device; only '
            'ciphertext is written to the app\'s own preferences. The key is used '
            'as the authentication header on requests to the provider it belongs '
            'to, and nowhere else.',
            'There is no Koru server. Nothing is stored on our side, because there '
            'is no our side to store it on.',
          ],
        ),
        _DocSection(
          'What never leaves the phone',
          bullets: [
            'Your nickname, and any real name you give it. The cloud rendering of '
                'your context deliberately leaves the name out.',
            'Your client list, amounts, payments and deadlines. They are read on '
            'the device. A client\'s name can only reach the cloud model if you type '
            'it into a question yourself.',
            'Any telemetry of any kind. There is none to send.',
          ],
        ),
        _DocSection(
          'When the cloud model is switched on',
          paragraphs: [
            'The cloud model is off until you choose a provider, paste your '
            'own key and test it in Settings > Cloud provider. Questions about faith, '
            'health, medicine or law are then routed to it, everything else is answered '
            'on the device, and anything that reads like a crisis, a diagnosis or a '
            'court date is handed to a person instead of being answered by a model.',
            'When a question is routed, your phone contacts that provider directly '
            'and sends: the question exactly as you typed it; the context packet '
            'shown in Settings > What leaves this phone (stage, work, goals, focus '
            'and up to four project lines, with no nickname); up to about 1,200 '
            'characters of recent conversation, so a follow-up is not asked from '
            'nothing; and your API key as the authentication header.',
            'It goes to the provider you chose and to nobody else. That provider '
            'handles it under its own terms and privacy policy, which Koru does not '
            'control and cannot speak for. Read them before you paste a key.',
            'To OpenRouter specifically, a Referer header naming this project and '
            'the title "Koru" are also sent, because that provider asks for them. '
            'They identify the app, not you.',
          ],
        ),
        _DocSection(
          'The local model',
          paragraphs: [
            'Requests for the local model go to the server address in Settings '
            '> Who answers, which is 127.0.0.1 unless you change it. That is '
            'traffic inside your phone, to a process the app itself started. If '
            'you point it at another machine, that machine receives the same '
            'prompt the cloud model would.',
          ],
        ),
        _DocSection(
          'Permissions',
          bullets: [
            'Internet, only for the cloud model and the provider you configured, '
                'and for the local model address you set.',
            'Notifications, so what is due can remind you.',
            'Calendar, only if you switch on copying entries to your phone\'s own '
                'calendar. Refused, the in-app calendar still works exactly as it '
                'did.',
            'Boot and a background service, so reminders still fire after the phone '
            'restarts.',
          ],
        ),
        _DocSection(
          'Backups, links and the calendar',
          paragraphs: [
            'A backup is written only when you tap it, and it is handed to '
            'Android\'s share sheet. Koru never uploads a backup or sends it '
            'anywhere by itself; where you put it is your choice.',
            'Tapping a WhatsApp follow-up or a phone number opens that app with the '
            'text typed out. Sending it is your tap, not Koru\'s.',
            'When calendar copying is on, an approved entry is written once into '
            'the calendar your phone already uses. How that calendar syncs onward, '
            'to your own account for instance, is between you, your calendar app '
            'and your account.',
          ],
        ),
        _DocSection(
          'If this changes',
          paragraphs: [
            'This policy ships inside the app, so the version you are reading is '
            'the one that applies to this build. If the way Koru handles data '
            'changes, this page changes with the update that brings it.',
          ],
        ),
      ],
    );
  }
}

/// What the user is agreeing to, said in a way that can be read once.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _DocScaffold(
      title: 'Terms & Conditions',
      lead: 'Plain English, no legalese. Read it once and you have read all of it.',
      sections: [
        _DocSection(
          'What you are agreeing to',
          paragraphs: [
            'Using Koru means accepting these terms. If you do not accept them, '
            'delete the app; Settings > Data will remove everything it stored '
            'before you do.',
          ],
        ),
        _DocSection(
          'The app is provided as is',
          paragraphs: [
            'Koru is offered as-is, with no promise that it is complete, accurate, '
            'error-free or always available. It may have bugs, an update may change '
            'or remove something, and a version that worked yesterday may not work '
            'today.',
            'To the extent the law allows, the people who make Koru are not '
            'responsible for losses that come from using it, including lost or '
            'corrupted data. Keep a backup: that is what Settings > Data > Back up '
            'is for.',
          ],
        ),
        _DocSection(
          'This is not advice',
          paragraphs: [
            'Koru is not financial, tax, legal or medical advice, and it is not a '
            'replacement for a professional who knows your situation.',
            'It organises and summarises what you give it. You decide what is true, '
            'what to invoice, what to chase and what to file. You are responsible '
            'for your own records, your own tax and every financial decision you '
            'make with this app in front of you. If a number matters, check it.',
            'The assistant hands questions about a crisis, a diagnosis or a legal '
            'ruling to a person rather than answering them. That is a limit, not a '
            'glitch, and it is a signal to talk to somebody qualified.',
          ],
        ),
        _DocSection(
          'Your data, and your responsibility for it',
          paragraphs: [
            'Everything lives on this device. A lost or broken phone with no backup '
            'means the data is gone, because Koru keeps no copy of it anywhere.',
            'Restoring a backup merges it into what is already here rather than '
            'replacing it. Look at what came back before you build on it.',
          ],
        ),
        _DocSection(
          'Cloud providers',
          paragraphs: [
            'If you add a cloud provider, your arrangement with them, payment, '
            'rate limits, what they do with what you send, and their own terms, is '
            'between you and them. Koru passes your question on and stops there.',
            'Koru itself charges nothing and creates no account. A provider you '
            'choose may charge you for their service.',
          ],
        ),
        _DocSection(
          'Other people\'s information',
          paragraphs: [
            'If you keep records about clients, you are responsible for having the '
            'right to keep them and for whatever you owe those people. Koru stores '
            'what you enter; deciding what belongs in it is yours.',
          ],
        ),
        _DocSection(
          'Stopping, and changes to this',
          paragraphs: [
            'Stop whenever you like. There is no subscription to cancel and no '
            'account to close; delete everything from Settings > Data.',
            'A later version may change these terms. The ones that apply are the '
            'ones shipped inside the copy of the app you are running.',
          ],
        ),
        _DocSection(
          'Licence',
          paragraphs: [
            'The source code is released under the MIT licence. That licence covers '
            'the code as it is distributed; these terms cover your use of the app.',
          ],
        ),
      ],
    );
  }
}

/// The short "what leaves this phone" summary, as its own page.
///
/// Separate from Settings > What leaves this phone, which prints the packet as
/// it would actually be sent. This one is the list of everything that can and
/// cannot move, for somebody who wants the whole answer in one screen.
class DataPolicyScreen extends StatelessWidget {
  const DataPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _DocScaffold(
      title: 'Data policy',
      lead: 'One page: what can leave this phone, what cannot, and what never '
          'will.',
      sections: [
        _DocSection(
          'Nothing leaves until you ask for it',
          paragraphs: [
            'Koru works offline. Your clients, your money, your calendar and your '
            'conversation sit on this device, and no part of the app sends them '
            'anywhere on its own.',
          ],
        ),
        _DocSection(
          'What can leave',
          bullets: [
            'A routed question. Only one about faith, health, medicine or law, only '
                'with the cloud model and a provider you configured yourself, and '
                'only with the pseudonymous context packet shown in Settings > What '
                'leaves this phone: no nickname, no client names, no amounts.',
            'Your API key, to the provider it belongs to, as the header that '
            'authenticates the request. Nowhere else.',
            'A local model request, to the address you set in Settings > Who '
                'answers. That is 127.0.0.1 unless you change it.',
            'An approved calendar entry, into your phone\'s own calendar, and only '
                'if you switch the copy on.',
            'A backup file, only when you tap Back up and choose where to share it.',
            'A link you tap. A WhatsApp follow-up or a phone number opens that app '
                'with the message typed out.',
          ],
        ),
        _DocSection(
          'What never leaves',
          bullets: [
            'Your nickname, and any real name you give it.',
            'Your clients, amounts, payments and deadlines, unless you type them '
                'into a question yourself.',
            'Analytics, advertising identifiers or crash reports. None of those '
                'exist in this app, so none of them can leave.',
          ],
        ),
        _DocSection(
          'If you would rather check than trust',
          paragraphs: [
            'Settings > What leaves this phone prints the exact packet as it would '
            'be sent, before you send anything. The longer version, including the '
            'keystore, permissions and the calendar, is in the Privacy Policy.',
          ],
        ),
      ],
    );
  }
}

/// The frame every document here sits in: a lead sentence, then the sections as
/// SectionLabel-over-Card, which is the shape Settings has used all along.
class _DocScaffold extends StatelessWidget {
  const _DocScaffold({required this.title, required this.lead, required this.sections});

  final String title;
  final String lead;
  final List<_DocSection> sections;

  @override
  Widget build(BuildContext context) {
    // Read from Koru's scale rather than from Theme.of, which is how the
    // paragraphs below were still picking up Material's bodyMedium. One
    // document that reads at 14.5 and the next at 14 is the reason these pages
    // look assembled rather than designed.
    final leadStyle = KoruType.bodyCompact.copyWith(height: 1.5);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: KoruPagePadding(
        bottom: KoruSpace.xxl,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: KoruSpace.xxs,
                bottom: KoruSpace.lg,
              ),
              child: Text(lead, style: leadStyle),
            ),
            for (var i = 0; i < sections.length; i++) ...[
              sections[i],
              if (i != sections.length - 1)
                const SizedBox(height: KoruSpace.section),
            ],
          ],
        ),
      ),
    );
  }
}

/// One heading with its prose under it.
class _DocSection extends StatelessWidget {
  const _DocSection(
    this.heading, {
    this.paragraphs = const [],
    this.bullets = const [],
  });

  final String heading;
  final List<String> paragraphs;
  final List<String> bullets;

  @override
  Widget build(BuildContext context) {
    final style = KoruType.bodyCompact.copyWith(height: 1.5);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(heading),
        KoruCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < paragraphs.length; i++) ...[
                Text(paragraphs[i], style: style),
                if (i != paragraphs.length - 1 || bullets.isNotEmpty)
                  const SizedBox(height: KoruSpace.sml),
              ],
              for (final bullet in bullets)
                Padding(
                  padding: const EdgeInsets.only(bottom: KoruSpace.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(
                          top: KoruSpace.sm,
                          right: KoruSpace.sml,
                        ),
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: KoruColors.leaf,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(child: Text(bullet, style: style)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
