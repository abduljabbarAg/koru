import 'package:flutter_test/flutter_test.dart';
import 'package:koru/models.dart';

Client _c(String? phone) => Client(name: 'Acme', created: '', phone: phone);

void main() {
  group('Client.whatsappLink', () {
    test('builds a wa.me link with the message encoded', () {
      final link = _c('07700900123')
          .whatsappLink(message: 'Hi Alex, invoice 12 is still outstanding.');
      expect(link, isNotNull);
      expect(link, startsWith('https://wa.me/07700900123?text='));
      expect(link, contains('invoice%2012'));
      // A raw space in a query string is the kind of thing that works on one
      // phone and opens a blank message on another.
      expect(link, isNot(contains(' ')));
    });

    test('strips formatting a human would type', () {
      // People paste numbers in every shape, and WhatsApp wants digits only.
      for (final raw in [
        '(07700) 900-123',
        '07700900123',
        '07700-900-123',
        '07700 900 123',
      ]) {
        final link = _c(raw).whatsappLink(message: 'Hello');
        expect(link, contains('/07700900123'), reason: raw);
      }
    });

    test('keeps the country code, because wa.me needs one', () {
      // A leading +44 is the country code, not decoration to strip. Dropping it
      // produces a link to the wrong person, which is the one failure mode here
      // that cannot be undone after the message has gone out.
      expect(_c('+44 7700 900123').whatsappLink(message: 'Hi'),
          contains('/447700900123'));
    });

    test('returns null with no number rather than a dead link', () {
      // A button that opens WhatsApp and then goes nowhere is worse than no
      // button: the user thinks they have sent the message.
      expect(_c(null).whatsappLink(message: 'Hi'), isNull);
      expect(_c('').whatsappLink(message: 'Hi'), isNull);
    });

    test('rejects numbers too short or too long to be real', () {
      expect(_c('12345').whatsappLink(message: 'Hi'), isNull);
      expect(_c('1234567890123456').whatsappLink(message: 'Hi'), isNull);
      expect(_c('07700900123').whatsappLink(message: 'Hi'), isNotNull);
    });

    test('handles unicode in the message', () {
      final link = _c('07700900123')
          .whatsappLink(message: 'Café — êtes-vous disponible ? 😀');
      expect(link, isNotNull);
      expect(link, contains('%C3%A9'), reason: 'é must be percent-encoded');
      expect(link, contains('%E2%80%94'), reason: 'em dash');
      // An emoji is four bytes and survives as a surrogate pair only if the
      // whole string was encoded at once, not piecemeal.
      expect(link, contains('%F0%9F'));
    });

    test('an empty message still produces a valid link', () {
      expect(_c('07700900123').whatsappLink(message: ''),
          'https://wa.me/07700900123?text=');
    });
  });

  group('Client round trip', () {
    test('phone survives toMap and fromMap', () {
      final c = _c('07700900123');
      final back = Client.fromMap(c.toMap());
      expect(back.phone, '07700900123');
    });

    test('a client with no phone still maps cleanly', () {
      final back = Client.fromMap(_c(null).toMap());
      expect(back.phone, isNull);
      expect(back.name, 'Acme');
    });
  });
}