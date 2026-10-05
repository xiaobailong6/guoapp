enum LiveProtocol { pingtai, list }

class LiveSource {
  const LiveSource({
    required this.id,
    required this.name,
    required this.description,
    required this.protocol,
    this.endpoints = const [],
    this.script = '',
    this.headers = const {},
    this.epg = '',
    this.builtin = true,
    this.enabled = true,
  });

  final String id;
  final String name;
  final String description;
  final LiveProtocol protocol;

  /// 同一面板的多个镜像。它们共享内容但各自维护分类子集，合并后按分类路由。
  final List<String> endpoints;
  final String script;

  String get endpoint => endpoints.isEmpty ? '' : endpoints.first;
  final Map<String, String> headers;
  final String epg;
  final bool builtin;
  final bool enabled;

  /// 是否支持按页续载。整类一次返回的源不参与滚动加载。
  bool get paginated => protocol == LiveProtocol.list;

  static const values = <LiveSource>[
    LiveSource(
      id: 'xiuguo',
      name: '秀果',
      description: '主播直播 · 实时开播',
      protocol: LiveProtocol.pingtai,
      endpoints: [
        'http://api.vipmisss.com:81/xcdsw',
        'http://api.hclyz.com:81/mf',
      ],
    ),
  ];

  static LiveSource? byId(String id) =>
      values.where((source) => source.id == id).firstOrNull;

  static bool isBuiltin(String id) => values.any((source) => source.id == id);

  LiveSource copyWith({bool? enabled}) => LiveSource(
    id: id,
    name: name,
    description: description,
    protocol: protocol,
    endpoints: endpoints,
    script: script,
    headers: headers,
    epg: epg,
    builtin: builtin,
    enabled: enabled ?? this.enabled,
  );
}
