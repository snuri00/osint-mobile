import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class Feed {
  Feed(this.name, this.url, this.lang, this.category, this.variant);
  final String name;
  final String url;
  final String lang;
  final String category;
  final String variant;
}

class FeedRegistry {
  FeedRegistry(this.feeds, this.sourceTypes, this.propagandaRisk);

  final List<Feed> feeds;
  final Map<String, String> sourceTypes;
  final Map<String, Map<String, dynamic>> propagandaRisk;

  static FeedRegistry? _instance;
  static FeedRegistry get instance => _instance!;

  static Future<FeedRegistry> load() async {
    if (_instance != null) return _instance!;
    final raw = await rootBundle.loadString('assets/feeds.json');
    final data = json.decode(raw) as Map<String, dynamic>;
    final feeds = (data['feeds'] as List)
        .map((f) => Feed(
              f['name'] as String,
              f['url'] as String,
              (f['lang'] ?? '') as String,
              (f['category'] ?? '') as String,
              (f['variant'] ?? '') as String,
            ))
        .toList();
    final types = <String, String>{};
    (data['source_types'] as Map).forEach((k, v) => types[k as String] = v as String);
    final risk = <String, Map<String, dynamic>>{};
    (data['propaganda_risk'] as Map)
        .forEach((k, v) => risk[k as String] = Map<String, dynamic>.from(v as Map));
    _instance = FeedRegistry(feeds, types, risk);
    return _instance!;
  }

  static const Map<String, int> tierPriority = {
    'wire': 0,
    'gov': 1,
    'intel': 2,
    'mainstream': 3,
    'market': 4,
    'tech': 5,
    'other': 6,
  };

  List<Feed> select(String? category, int maxFeeds) {
    List<Feed> selected = [];
    if (category != null && category.trim().isNotEmpty) {
      final key = category.toLowerCase();
      selected = feeds.where((f) => f.category.toLowerCase() == key).toList();
      if (selected.isEmpty) {
        selected = feeds.where((f) => f.variant.toLowerCase() == key).toList();
      }
    }
    if (selected.isEmpty) {
      selected = feeds.where((f) => f.variant == 'world').toList();
    }
    selected.sort((a, b) {
      final pa = tierPriority[sourceTypes[a.name] ?? 'other'] ?? 6;
      final pb = tierPriority[sourceTypes[b.name] ?? 'other'] ?? 6;
      return pa.compareTo(pb);
    });
    return selected.take(maxFeeds).toList();
  }

  String sourceFlags(String name) {
    final tier = sourceTypes[name] ?? 'other';
    final parts = <String>[tier];
    final risk = propagandaRisk[name];
    if (risk != null) {
      final state = risk['stateAffiliated'];
      if (state != null && '$state'.isNotEmpty) {
        parts.add('state-affiliated: $state');
      }
      final level = risk['risk'];
      if (level == 'high' || level == 'medium') {
        parts.add('propaganda risk: $level');
      }
    }
    return parts.join(', ');
  }
}
