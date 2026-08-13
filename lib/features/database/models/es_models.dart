/// Elasticsearch 索引，对应源码 `pkg/db/elasticsearch.go` 的 `ESIndex`。
class EsIndex {
  const EsIndex({
    required this.name,
    required this.health,
    required this.status,
    required this.docsCount,
    required this.storeSize,
  });

  final String name;

  /// green / yellow / red
  final String health;

  /// open / close
  final String status;
  final String docsCount;
  final String storeSize;

  factory EsIndex.fromJson(Map<String, dynamic> json) => EsIndex(
    name: json['name'] as String? ?? '',
    health: json['health'] as String? ?? '',
    status: json['status'] as String? ?? '',
    docsCount: json['docs_count'] as String? ?? '',
    storeSize: json['store_size'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'health': health,
    'status': status,
    'docs_count': docsCount,
    'store_size': storeSize,
  };
}

/// Elasticsearch 文档，对应源码 `pkg/db/elasticsearch.go` 的 `ESDocument`。
class EsDocument {
  const EsDocument({
    required this.id,
    required this.index,
    required this.source,
  });

  final String id;
  final String index;

  /// 文档内容（JSON 字符串）。
  final String source;

  factory EsDocument.fromJson(Map<String, dynamic> json) => EsDocument(
    id: json['id'] as String? ?? '',
    index: json['index'] as String? ?? '',
    source: json['source'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {'id': id, 'index': index, 'source': source};
}
