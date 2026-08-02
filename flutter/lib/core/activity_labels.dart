/// Turns an activity_feed row into the text a feed card shows.
///
/// Shared by the friend feed and the notifications screen so the wording for a
/// given activity type is defined once. Row shape from GET /friends/feed:
///   { type, payload, created_at, username, avatar_url, game_name, cover_image }
library;

/// One rendered feed line, split so the card can style the parts differently:
/// muted verb, white subject, small grey detail underneath.
class ActivityLine {
  /// What they did — "logged", "rated", "added to a list".
  final String verb;

  /// The thing it happened to, usually a game name. Null for list-only rows.
  final String? subject;

  /// Optional third line: review text, list name, hours played.
  final String? detail;

  /// 1–5 when the activity carries a rating, otherwise null.
  final int? rating;

  /// Leading glyph for rows with no cover art to show.
  final String emoji;

  const ActivityLine({
    required this.verb,
    this.subject,
    this.detail,
    this.rating,
    this.emoji = '🎮',
  });
}

ActivityLine describeActivity(Map<String, dynamic> activity) {
  final type = activity['type'] as String? ?? '';
  final payload = _payload(activity);
  final gameName = activity['game_name'] as String?;

  switch (type) {
    case 'game_logged':
      final status = payload['status'] as String?;
      final hours = payload['hours_played'];
      final comment = (payload['comment'] as String?)?.trim();
      return ActivityLine(
        verb: switch (status) {
          'completed' => 'finished',
          'paused' => 'paused',
          _ => 'is playing',
        },
        subject: gameName,
        // The comment is the interesting part when there is one; hours are a
        // reasonable fallback so the card isn't just a title.
        detail: comment != null && comment.isNotEmpty
            ? comment
            : (hours != null ? '$hours hours played' : null),
        emoji: status == 'completed' ? '🏆' : '🎮',
      );

    case 'game_rated':
      return ActivityLine(
        verb: 'rated',
        subject: gameName,
        rating: _asInt(payload['rating']),
        emoji: '⭐',
      );

    case 'game_reviewed':
      final text = (payload['review_text'] as String?)?.trim();
      return ActivityLine(
        verb: 'reviewed',
        subject: gameName,
        detail: text != null && text.isNotEmpty ? text : null,
        rating: _asInt(payload['rating']),
        emoji: '📝',
      );

    case 'list_created':
      return ActivityLine(
        verb: 'made a new list',
        subject: payload['list_name'] as String?,
        emoji: payload['emoji'] as String? ?? '📋',
      );

    case 'list_game_added':
      return ActivityLine(
        verb: 'added',
        subject: gameName,
        detail: payload['list_name'] != null ? 'to ${payload['list_name']}' : null,
        emoji: payload['emoji'] as String? ?? '📋',
      );

    // Types the older schema wrote. Kept so backfilled or legacy rows still
    // render as something readable rather than a blank card.
    case 'game_added':
      return ActivityLine(verb: 'added to their library', subject: gameName);

    case 'status_changed':
      final status = payload['new_status'] as String?;
      return ActivityLine(
        verb: switch (status) {
          'completed' => 'finished',
          'playing' => 'started playing',
          'paused' => 'paused',
          'plan_to_play' => 'wants to play',
          _ => 'updated',
        },
        subject: gameName,
      );

    case 'achievement_unlocked':
      return ActivityLine(
        verb: 'unlocked an achievement in',
        subject: gameName,
        detail: payload['achievement_name'] as String?,
        emoji: '🏅',
      );

    default:
      return ActivityLine(verb: 'updated', subject: gameName);
  }
}

/// "2m ago" / "5h ago" / "3d ago" / "2w ago".
String timeAgo(String? timestamp) {
  if (timestamp == null) return '';
  try {
    final diff = DateTime.now().difference(DateTime.parse(timestamp).toLocal());
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 365) return '${(diff.inDays / 7).floor()}w ago';
    return '${(diff.inDays / 365).floor()}y ago';
  } catch (_) {
    return '';
  }
}

/// payload arrives as a JSON object from Postgres, but a legacy row could hold
/// a string or null — normalise so callers can index it without a type check.
Map<String, dynamic> _payload(Map<String, dynamic> activity) {
  final raw = activity['payload'];
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return const {};
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
