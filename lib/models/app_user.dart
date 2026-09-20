/// The locally known user. Created once by `POST /api/users`, then stored.
class AppUser {
  final String id;
  final String username;

  const AppUser({required this.id, required this.username});

  /// `POST /api/users` answers with a bare `{ "id": ..., "name": ... }`.
  factory AppUser.fromCreateJson(Map<String, dynamic> json) =>
      AppUser(id: json['id'] as String, username: json['name'] as String);

  /// `GET /api/users/:id` answers with the full Mongo document.
  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['_id'] as String,
        username: json['username'] as String,
      );
}
