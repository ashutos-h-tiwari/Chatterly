class ReplyRef {
  final String id;
  final String preview;
  const ReplyRef({required this.id, required this.preview});

  factory ReplyRef.fromMap(Map<String, dynamic> json) => ReplyRef(
    id: (json['id'] ?? json['_id'] ?? '').toString(),
    preview: (json['preview'] ?? json['text'] ?? '').toString(),
  );

  Map<String, dynamic> toJson() => {'id': id, 'preview': preview};
}
