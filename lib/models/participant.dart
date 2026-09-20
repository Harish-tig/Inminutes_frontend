/// Someone who joined a group session. The host is never in this list and
/// therefore has no ready flag.
class Participant {
  final String userId;
  final String username;
  final String displayName;
  final bool ready;

  const Participant({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.ready,
  });

  factory Participant.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    return Participant(
      userId: user?['_id'] as String? ?? '',
      username: user?['username'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      ready: json['ready'] as bool? ?? false,
    );
  }
}
