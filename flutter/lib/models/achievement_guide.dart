// Typed view of GET /games/:id/achievement-guide.
//
// Ordering, phases and ladders are computed by the backend; the app only
// renders them. Parsing is defensive: a missing or oddly-typed field degrades
// to a sensible default instead of throwing.

double? _num(dynamic v) => v == null ? null : double.tryParse(v.toString());

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

List<String> _strings(dynamic v) =>
    v is List ? v.whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty).toList() : const [];

// Word set with a crude tense/plural tolerance, only used to spot restatements
// ("Reached 10th level." ~ "Reach 10th level."). Never used for ordering.
Set<String> _words(String s) => RegExp(r'[a-z0-9]+')
    .allMatches(s.toLowerCase())
    .map((m) {
      var w = m.group(0)!;
      for (final suffix in const ['ing', 'ed', 'es', 's', 'd']) {
        if (w.length > 4 && w.endsWith(suffix)) {
          w = w.substring(0, w.length - suffix.length);
          break;
        }
      }
      return w;
    })
    .toSet();

bool _restates(String step, String? text) {
  if (text == null || text.isEmpty) return false;
  final a = _words(step);
  final b = _words(text);
  if (a.isEmpty || b.isEmpty) return false;
  return a.intersection(b).length / a.union(b).length >= 0.8;
}

/// LLM "steps" are hints, not facts. They are hidden when the model itself was
/// not confident, and when a step adds nothing: it just restates the trophy's
/// name or description.
List<String> visibleSteps({
  required String name,
  String? description,
  required List<String> steps,
  required String? confidence,
}) {
  if (confidence == 'low') return const [];
  final n = _norm(name);
  return steps.where((s) {
    final t = _norm(s);
    if (t == n || t == 'complete$n' || t == 'earn$n' || t == 'unlock$n') return false;
    return !_restates(s, description) && !_restates(s, name);
  }).toList();
}

class GuideTrophy {
  final String id;
  final String name;
  final String? description;
  final String? image;
  final double? rarity;
  final bool hidden;
  final List<String> steps;

  const GuideTrophy({
    required this.id,
    required this.name,
    this.description,
    this.image,
    this.rarity,
    this.hidden = false,
    this.steps = const [],
  });

  factory GuideTrophy.fromJson(Map<String, dynamic> j) {
    final name = (j['name'] ?? '').toString();
    return GuideTrophy(
      id: (j['id'] ?? '').toString(),
      name: name,
      description: (j['description'] as String?)?.isNotEmpty == true ? j['description'] as String : null,
      image: (j['image'] as String?)?.isNotEmpty == true ? j['image'] as String : null,
      rarity: _num(j['rarity'] ?? j['percent']),
      hidden: j['hidden'] == true,
      steps: visibleSteps(
        name: name,
        description: j['description'] as String?,
        steps: _strings(j['steps']),
        confidence: j['confidence'] as String?,
      ),
    );
  }
}

/// One rung of a threshold ladder ("10" -> "50" -> "100", "bronze" -> "gold").
class GuideTier {
  final String label;
  final List<GuideTrophy> trophies;
  const GuideTier({required this.label, required this.trophies});

  factory GuideTier.fromJson(Map<String, dynamic> j) => GuideTier(
        label: (j['label'] ?? j['value'] ?? '').toString(),
        trophies: (j['trophies'] as List? ?? const [])
            .whereType<Map>()
            .map((t) => GuideTrophy.fromJson(Map<String, dynamic>.from(t)))
            .toList(),
      );
}

class GuidePhase {
  final String key;
  final String name;
  final int count;
  const GuidePhase({required this.key, required this.name, required this.count});

  factory GuidePhase.fromJson(Map<String, dynamic> j) => GuidePhase(
        key: (j['key'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        count: (j['count'] as num?)?.toInt() ?? 0,
      );
}

/// One stop on the map: either a single trophy or a collapsed ladder.
class GuideNode {
  final int order;
  final String id;
  final String name;
  final String? description;
  final String? image;
  final double? percent;
  final String reason;
  final String phase; // base | online | dlc
  final String phaseName;
  final bool isLadder;
  final bool hidden;
  final List<String> steps;
  final String? suspectedCategory;
  final List<GuideTier> tiers;

  const GuideNode({
    required this.order,
    required this.id,
    required this.name,
    this.description,
    this.image,
    this.percent,
    this.reason = '',
    this.phase = 'base',
    this.phaseName = '',
    this.isLadder = false,
    this.hidden = false,
    this.steps = const [],
    this.suspectedCategory,
    this.tiers = const [],
  });

  factory GuideNode.fromJson(Map<String, dynamic> j) {
    final name = (j['name'] ?? '').toString();
    final tiers = (j['tiers'] as List? ?? const [])
        .whereType<Map>()
        .map((t) => GuideTier.fromJson(Map<String, dynamic>.from(t)))
        .toList();
    final suspected = j['suspectedCategory'] as String?;
    return GuideNode(
      order: (j['order'] as num?)?.toInt() ?? 0,
      id: (j['id'] ?? '').toString(),
      name: name,
      description: (j['description'] as String?)?.isNotEmpty == true ? j['description'] as String : null,
      image: (j['image'] as String?)?.isNotEmpty == true ? j['image'] as String : null,
      percent: _num(j['percent'] ?? j['rarity']),
      reason: (j['reason'] ?? '').toString(),
      phase: (j['phase'] ?? 'base').toString(),
      phaseName: (j['phaseName'] ?? '').toString(),
      isLadder: j['kind'] == 'ladder' && tiers.isNotEmpty,
      hidden: j['hidden'] == true,
      steps: visibleSteps(
        name: name,
        description: j['description'] as String?,
        steps: _strings(j['steps']),
        confidence: j['confidence'] as String?,
      ),
      suspectedCategory: (suspected == 'dlc' || suspected == 'online') ? suspected : null,
      tiers: tiers,
    );
  }
}

class AchievementGuide {
  final List<GuideNode> nodes;
  final List<GuidePhase> phases;
  const AchievementGuide({required this.nodes, required this.phases});

  factory AchievementGuide.fromJson(Map<String, dynamic> j) {
    final nodes = (j['nodes'] as List? ?? const [])
        .whereType<Map>()
        .map((n) => GuideNode.fromJson(Map<String, dynamic>.from(n)))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final phases = (j['phases'] as List? ?? const [])
        .whereType<Map>()
        .map((p) => GuidePhase.fromJson(Map<String, dynamic>.from(p)))
        .toList();
    return AchievementGuide(nodes: nodes, phases: phases);
  }

  bool get hasMultiplePhases => phases.length > 1;
}
