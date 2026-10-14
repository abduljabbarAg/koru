import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koru/screens/chat.dart';

/// Replies used to arrive with their markdown still showing.
///
/// A cloud answer comes back with **bold, bullets and numbered steps in it, and
/// printing the asterisks and hashes is printing the plumbing. These check the
/// shapes that actually arrive rather than the general markdown grammar.
void main() {
  // The renderer is private to the chat screen, so it is driven through the
  // public widget it produces. `_RichReply` is what a bubble builds.
  Finder findRich(WidgetTester tester) => find.byType(RichText);

  Future<List<String>> render(WidgetTester tester, String text) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: RichReply(text: text, muted: false)),
    ));
    return tester
        .widgetList<RichText>(findRich(tester))
        .map((r) => r.text.toPlainText())
        .toList();
  }

  testWidgets('bold is applied and the asterisks are gone', (tester) async {
    final out = await render(tester, 'Bilal **owes** you 2000.');
    expect(out.join(' '), contains('owes'));
    expect(out.join(' '), isNot(contains('**')));
  });

  testWidgets('an unclosed bold run is left alone while it streams',
      (tester) async {
    // This is the whole reason the pattern is not a general one: restyling an
    // unterminated run would change the rest of the paragraph on every token.
    final out = await render(tester, 'Bilal **owes you');
    expect(out.join(' '), contains('**'));
  });

  testWidgets('a bullet loses its dash and gains a marker', (tester) async {
    final out = await render(tester, '- one client\n- two clients');
    final joined = out.join('\n');
    expect(joined, isNot(contains('- one client')));
    expect(joined, contains('one client'));
    expect(joined, contains('two clients'));
  });

  testWidgets('a numbered step keeps its number', (tester) async {
    final out = await render(tester, '1. add the client\n2. send the invoice');
    final joined = out.join('\n');
    expect(joined, contains('1.'));
    expect(joined, contains('add the client'));
  });

  testWidgets('a heading loses its hashes', (tester) async {
    final out = await render(tester, '## What is due');
    expect(out.join(' '), isNot(contains('##')));
    expect(out.join(' '), contains('What is due'));
  });

  testWidgets('plain text is untouched', (tester) async {
    final out = await render(tester, 'Bilal owes you 2000.');
    expect(out.join(' '), 'Bilal owes you 2000.');
  });

  testWidgets('a price is not mistaken for emphasis', (tester) async {
    // The reason this is not a full markdown parser: a stray asterisk from a
    // price is not italics, and rendering it as such invents emphasis nobody
    // asked for.
    final out = await render(tester, 'It cost *5 and *6 in total');
    expect(out.join(' '), contains('*5'));
  });
}

