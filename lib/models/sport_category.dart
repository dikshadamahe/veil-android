/// A sport category from `GET {SPORTS_URL}/v1/sports` (streamed.pk `/api/sports`).
///
/// Shape: `{ "id": "football", "name": "Football" }`.
class SportCategory {
  const SportCategory({required this.id, required this.name});

  /// Sport id used as the `:sport` path segment for match queries.
  final String id;

  /// Human-readable display name.
  final String name;

  factory SportCategory.fromJson(Map<String, dynamic> json) => SportCategory(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
      );
}
