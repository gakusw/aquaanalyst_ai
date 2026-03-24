class MyMenu {
  final String id;
  final String name;
  final String content;
  final DateTime createdAt;

  MyMenu({
    required this.id,
    required this.name,
    required this.content,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory MyMenu.fromMap(String id, Map<String, dynamic> map) {
    return MyMenu(
      id: id,
      name: map['name'] ?? '',
      content: map['content'] ?? '',
      createdAt: DateTime.parse(map['createdAt'] ?? DateTime.now().toIso8601String()),
    );
  }
}
