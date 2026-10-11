import 'attention.dart';

/// Carries "open this" across the process boundary.
///
/// A notification is posted by a service that may outlive the app. When it is
/// tapped, Android usually starts a fresh process, so nothing in memory
/// survives. That rules out handing a callback or an object to whatever is
/// listening: it has to be something that can be written into an Intent, read
/// back after a cold start, and mean the same thing.
///
/// So the target is encoded as a small URI and decoded on the other side. The
/// alternative, keeping a pending request in a field, works right up until the
/// process is killed between the tap and the read, which is exactly when the
/// user is most likely to be looking.
class KoruDeepLink {
  final AttentionKind kind;
  final AttentionTarget target;
  final int? id;

  const KoruDeepLink({required this.kind, required this.target, this.id});

  /// Encoded so it survives an Intent as a string.
  ///
  /// Deliberately not [Uri] with a host: this is an internal hop between our own
  /// notification and our own app, and an explicit scheme makes it obvious in a
  /// log that nothing here is being handed to the web.
  String encode() => 'koru://attention/${kind.name}/${target.name}'
      '${id == null ? '' : '/$id'}';

  /// Reads a link back, or null when it is not one of ours.
  ///
  /// Null rather than throwing: this is fed a string from outside the app, and
  /// a malformed link should leave the user on the home screen rather than crash
  /// the launch.
  static KoruDeepLink? decode(String? raw) {
    if (raw == null) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'koru' || uri.host != 'attention') return null;
    final parts = uri.pathSegments;
    if (parts.length < 2) return null;
    final kind = AttentionKind.values.where((k) => k.name == parts[0]).firstOrNull;
    final target =
        AttentionTarget.values.where((t) => t.name == parts[1]).firstOrNull;
    if (kind == null || target == null) return null;
    return KoruDeepLink(
      kind: kind,
      target: target,
      id: parts.length > 2 ? int.tryParse(parts[2]) : null,
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}