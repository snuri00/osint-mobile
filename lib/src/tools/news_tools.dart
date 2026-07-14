import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'feeds.dart';

const _userAgent = 'osint-mcp-mobile/1.0';
const _maxFeeds = 45;
const _perFeedItems = 25;
const _maxResults = 25;
const _concurrency = 8;

class _Item {
  _Item(this.title, this.link, this.summary, this.source, this.epoch, this.category);
  final String title;
  final String link;
  final String summary;
  final String source;
  final int? epoch;
  final String category;
}

String _text(XmlElement e, String tag) {
  final els = e.findElements(tag);
  if (els.isEmpty) return '';
  return els.first.innerText.trim();
}

int? _parseDate(String s) {
  if (s.isEmpty) return null;
  final iso = DateTime.tryParse(s);
  if (iso != null) return iso.toUtc().millisecondsSinceEpoch ~/ 1000;
  final m = RegExp(
    r'(\d{1,2})\s+(\w{3})\s+(\d{4})\s+(\d{2}):(\d{2})(?::(\d{2}))?',
  ).firstMatch(s);
  if (m == null) return null;
  const months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };
  final mon = months[m.group(2)!.toLowerCase()];
  if (mon == null) return null;
  try {
    final dt = DateTime.utc(
      int.parse(m.group(3)!),
      mon,
      int.parse(m.group(1)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6) ?? '0'),
    );
    return dt.millisecondsSinceEpoch ~/ 1000;
  } catch (_) {
    return null;
  }
}

String _stripHtml(String s) =>
    s.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

List<_Item> _parseFeed(String body, String source, String category) {
  final items = <_Item>[];
  XmlDocument doc;
  try {
    doc = XmlDocument.parse(body);
  } catch (_) {
    return items;
  }
  for (final it in doc.findAllElements('item')) {
    final date = _text(it, 'pubDate').isNotEmpty
        ? _text(it, 'pubDate')
        : _text(it, 'dc:date');
    items.add(_Item(
      _stripHtml(_text(it, 'title')),
      _text(it, 'link'),
      _stripHtml(_text(it, 'description')),
      source,
      _parseDate(date),
      category,
    ));
    if (items.length >= _perFeedItems) break;
  }
  if (items.isNotEmpty) return items;
  for (final en in doc.findAllElements('entry')) {
    var link = '';
    for (final l in en.findElements('link')) {
      final href = l.getAttribute('href');
      if (href != null) {
        link = href;
        if (l.getAttribute('rel') == 'alternate' || l.getAttribute('rel') == null) break;
      }
    }
    final date = _text(en, 'updated').isNotEmpty
        ? _text(en, 'updated')
        : _text(en, 'published');
    items.add(_Item(
      _stripHtml(_text(en, 'title')),
      link,
      _stripHtml(_text(en, 'summary').isNotEmpty ? _text(en, 'summary') : _text(en, 'content')),
      source,
      _parseDate(date),
      category,
    ));
    if (items.length >= _perFeedItems) break;
  }
  return items;
}

class _CacheEntry {
  _CacheEntry(this.items, this.etag, this.lastModified, this.fetchedAt);
  List<_Item> items;
  String? etag;
  String? lastModified;
  DateTime fetchedAt;
}

final Map<String, _CacheEntry> _feedCache = {};
const _cacheTtl = Duration(minutes: 5);

Future<List<_Item>> _fetchFeed(Feed feed, Duration timeout) async {
  final now = DateTime.now();
  final cached = _feedCache[feed.url];
  if (cached != null && now.difference(cached.fetchedAt) < _cacheTtl) {
    return cached.items;
  }
  final headers = {'User-Agent': _userAgent};
  if (cached?.etag != null) headers['If-None-Match'] = cached!.etag!;
  if (cached?.lastModified != null) {
    headers['If-Modified-Since'] = cached!.lastModified!;
  }
  try {
    final resp =
        await http.get(Uri.parse(feed.url), headers: headers).timeout(timeout);
    if (resp.statusCode == 304 && cached != null) {
      cached.fetchedAt = now;
      return cached.items;
    }
    if (resp.statusCode != 200) return cached?.items ?? [];
    final items = _parseFeed(
        utf8.decode(resp.bodyBytes, allowMalformed: true), feed.name, feed.category);
    _feedCache[feed.url] = _CacheEntry(
        items, resp.headers['etag'], resp.headers['last-modified'], now);
    return items;
  } catch (_) {
    return cached?.items ?? [];
  }
}

Future<List<_Item>> _gather(List<Feed> feeds, Duration perFeed) async {
  final out = <_Item>[];
  var idx = 0;
  Future<void> worker() async {
    while (true) {
      final i = idx++;
      if (i >= feeds.length) break;
      out.addAll(await _fetchFeed(feeds[i], perFeed));
    }
  }
  await Future.wait(List.generate(_concurrency, (_) => worker()));
  return out;
}

const _stopWords = {
  'the', 'a', 'an', 'of', 'in', 'on', 'to', 'and', 'or', 'for', 'is', 'are',
  'was', 'were', 'be', 'with', 'at', 'by', 'from', 'as', 'what', 'whats',
  "what's", 'happening', 'happen', 'latest', 'news', 'update', 'updates',
  'about', 'any', 'right', 'now', 'today', 'recent', 'current', 'tell', 'me',
  'give', 'show', 'situation', 'situational', 'brief', 'report',
  // Turkish generic terms so an agenda-style query reduces to recency-ranked headlines
  've', 'ile', 'bir', 'için', 'icin', 'ne', 'mi', 'mu', 'mü', 'da', 'de',
  'gündem', 'gundem', 'gündemi', 'gundemi', 'haber', 'haberler', 'haberleri',
  'son', 'dakika', 'bugün', 'bugun', 'oluyor', 'nedir', 'hakkında', 'hakkinda',
  'güncel', 'guncel', 'nler', 'olan', 'var', 'gelişme', 'gelisme', 'gelişmeler',
};

class _Query {
  _Query(this.terms, this.phrases);
  final List<String> terms;
  final List<String> phrases;
  bool get isEmpty => terms.isEmpty && phrases.isEmpty;
}

_Query _parseQuery(String q) {
  final lower = q.toLowerCase();
  final phraseRe = RegExp(r'"([^"]+)"');
  final phrases = [
    for (final m in phraseRe.allMatches(lower)) m.group(1)!.trim()
  ].where((p) => p.isNotEmpty).toList();
  final rest = lower.replaceAll(phraseRe, ' ');
  final terms = rest
      .split(RegExp(r'[^a-z0-9]+'))
      .where((t) => t.length > 1 && !_stopWords.contains(t))
      .toSet()
      .toList();
  return _Query(terms, phrases);
}

int _count(String hay, String needle) {
  if (needle.isEmpty) return 0;
  var n = 0, i = 0;
  while ((i = hay.indexOf(needle, i)) != -1) {
    n++;
    i += needle.length;
  }
  return n;
}

double _recencyBoost(int? epoch, DateTime now) {
  if (epoch == null) return 0.3;
  final ageDays = now
          .difference(DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true))
          .inHours /
      24.0;
  if (ageDays < 0) return 1.0;
  return 1.0 / (1.0 + ageDays / 2.0);
}

/// Relevance score: term frequency (title weighted 3x over summary) plus a
/// strong phrase bonus, modulated by a recency-decay factor (~2-day half-life).
/// Returns 0 when a required phrase is absent or nothing matches.
double _score(_Item it, _Query q, DateTime now) {
  final title = it.title.toLowerCase();
  final summary = it.summary.toLowerCase();
  for (final ph in q.phrases) {
    if (!title.contains(ph) && !summary.contains(ph)) return 0;
  }
  if (q.isEmpty) return _recencyBoost(it.epoch, now);

  var rel = 0.0;
  for (final t in q.terms) {
    rel += _count(title, t) * 3.0 + _count(summary, t) * 1.0;
  }
  for (final ph in q.phrases) {
    if (title.contains(ph)) {
      rel += 6.0;
    } else if (summary.contains(ph)) {
      rel += 3.0;
    }
  }
  if (rel == 0) return q.phrases.isNotEmpty ? 1.0 : 0.0;
  return rel * (0.5 + _recencyBoost(it.epoch, now));
}

String _fmtWhen(int? epoch) {
  if (epoch == null) return 'date unknown';
  final dt = DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)} UTC';
}

String _relAge(int? epoch, DateTime now) {
  if (epoch == null) return '';
  final d =
      now.difference(DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true));
  if (d.isNegative) return '';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 48) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

Future<String> searchNews(String query, {String? category}) async {
  final reg = FeedRegistry.instance;
  final feeds = reg.select(category, _maxFeeds);
  final q = _parseQuery(query);
  final now = DateTime.now();
  final raw = await _gather(feeds, const Duration(seconds: 8));

  final scored = <(_Item, double)>[];
  for (final it in raw) {
    if (it.title.isEmpty) continue;
    final s = _score(it, q, now);
    if (s > 0) scored.add((it, s));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));

  final seen = <String>{};
  final ranked = <_Item>[];
  for (final (it, _) in scored) {
    if (seen.add(it.title.toLowerCase())) ranked.add(it);
  }

  final bool hasCategory = category != null && category.trim().isNotEmpty;
  if (ranked.isEmpty) {
    if (hasCategory && raw.isNotEmpty) {
      final recent = raw.where((it) => it.title.isNotEmpty).toList()
        ..sort((a, b) => (b.epoch ?? 0).compareTo(a.epoch ?? 0));
      final s2 = <String>{};
      for (final it in recent) {
        if (s2.add(it.title.toLowerCase())) ranked.add(it);
      }
    }
    if (ranked.isEmpty) {
      return "No recent headlines matching '$query' across ${feeds.length} curated feeds.";
    }
  }
  final label = hasCategory ? "'$category'" : 'curated';
  final String headline;
  if (query.trim().isEmpty) {
    headline =
        "Latest $label headlines across ${feeds.length} feeds (most recent first):\n";
  } else if (scored.isEmpty) {
    headline =
        "Latest $label headlines (no term match for '$query', most recent first):\n";
  } else {
    headline =
        "News results for '$query' (${ranked.length} match(es) across ${feeds.length} curated feeds, most relevant first):\n";
  }
  final lines = <String>[headline];
  for (final it in ranked.take(_maxResults)) {
    final age = _relAge(it.epoch, now);
    final when = age.isEmpty ? _fmtWhen(it.epoch) : '${_fmtWhen(it.epoch)} ($age)';
    lines.add('[+] ${it.title}');
    lines.add('    ${it.source} (${reg.sourceFlags(it.source)}) · $when');
    if (it.link.isNotEmpty) lines.add('    ${it.link}');
  }
  return lines.join('\n');
}

Future<String> searchReliefweb(String query) async {
  final url = Uri.parse(
      'https://reliefweb.int/updates/rss.xml?search=${Uri.encodeQueryComponent(query)}');
  final items = await _fetchFeed(
      Feed('ReliefWeb', url.toString(), 'en', 'crisis', 'world'),
      const Duration(seconds: 12));
  if (items.isEmpty) {
    return "No ReliefWeb situation reports found for '$query'.";
  }
  final lines = <String>["ReliefWeb (UN OCHA) — latest for '$query':\n"];
  for (final it in items.take(_maxResults)) {
    lines.add('[+] ${it.title}');
    lines.add('    ${_fmtWhen(it.epoch)}');
    if (it.link.isNotEmpty) lines.add('    ${it.link}');
  }
  return lines.join('\n');
}

Future<String> searchDisasters({String? region}) async {
  final filter = region?.toLowerCase().trim();
  final lines = <String>[];

  try {
    final r = await http
        .get(Uri.parse(
            'https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/2.5_day.geojson'))
        .timeout(const Duration(seconds: 12));
    if (r.statusCode == 200) {
      final data = json.decode(r.body) as Map<String, dynamic>;
      final feats = (data['features'] as List).cast<Map<String, dynamic>>();
      final quakes = <String>[];
      for (final f in feats) {
        final props = f['properties'] as Map<String, dynamic>;
        final place = '${props['place'] ?? ''}';
        if (filter != null && filter.isNotEmpty && !place.toLowerCase().contains(filter)) {
          continue;
        }
        final mag = props['mag'];
        final t = props['time'];
        final when = t is int ? _fmtWhen(t ~/ 1000) : 'date unknown';
        quakes.add('[+] M$mag — $place · $when');
        if (quakes.length >= 12) break;
      }
      if (quakes.isNotEmpty) {
        lines.add('EARTHQUAKES (USGS, past 24h, M2.5+):');
        lines.addAll(quakes);
        lines.add('');
      }
    }
  } catch (_) {}

  try {
    final r = await http
        .get(Uri.parse('https://eonet.gsfc.nasa.gov/api/v3/events?status=open&limit=40'))
        .timeout(const Duration(seconds: 12));
    if (r.statusCode == 200) {
      final data = json.decode(r.body) as Map<String, dynamic>;
      final events = (data['events'] as List).cast<Map<String, dynamic>>();
      final out = <String>[];
      for (final e in events) {
        final title = '${e['title'] ?? ''}';
        if (filter != null && filter.isNotEmpty && !title.toLowerCase().contains(filter)) {
          continue;
        }
        final cats = (e['categories'] as List?)
                ?.map((c) => '${(c as Map)['title']}')
                .join(', ') ??
            '';
        out.add('[+] $title  ($cats)');
        if (out.length >= 15) break;
      }
      if (out.isNotEmpty) {
        lines.add('NATURAL EVENTS (NASA EONET, active):');
        lines.addAll(out);
        lines.add('');
      }
    }
  } catch (_) {}

  try {
    final items = await _fetchFeed(
        Feed('GDACS', 'https://www.gdacs.org/xml/rss.xml', 'en', 'crisis', 'world'),
        const Duration(seconds: 12));
    final out = <String>[];
    for (final it in items) {
      if (filter != null && filter.isNotEmpty && !it.title.toLowerCase().contains(filter)) {
        continue;
      }
      out.add('[+] ${it.title} · ${_fmtWhen(it.epoch)}');
      if (out.length >= 12) break;
    }
    if (out.isNotEmpty) {
      lines.add('GDACS ALERTS:');
      lines.addAll(out);
    }
  } catch (_) {}

  if (lines.isEmpty) {
    return region == null
        ? 'No recent disaster events retrieved.'
        : "No recent disaster events matching '$region'.";
  }
  return lines.join('\n').trim();
}

Future<String> searchEvents(String query, {String timespan = '7d'}) async {
  final ts = _gdeltTimespan(timespan);
  final url = Uri.parse(
      'https://api.gdeltproject.org/api/v2/doc/doc?query=${Uri.encodeQueryComponent(query)}'
      '&mode=ArtList&maxrecords=30&timespan=$ts&format=json&sort=DateDesc');
  try {
    final r = await http
        .get(url, headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      return 'GDELT returned HTTP ${r.statusCode} for "$query".';
    }
    final data = json.decode(r.body) as Map<String, dynamic>;
    final arts = (data['articles'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (arts.isEmpty) return "No GDELT coverage for '$query' in the last $timespan.";
    final byCountry = <String, int>{};
    final lines = <String>["GDELT coverage for '$query' (last $timespan):\n"];
    for (final a in arts.take(_maxResults)) {
      final title = '${a['title'] ?? ''}';
      final domain = '${a['domain'] ?? ''}';
      final country = '${a['sourcecountry'] ?? ''}';
      if (country.isNotEmpty) byCountry[country] = (byCountry[country] ?? 0) + 1;
      lines.add('[+] $title');
      lines.add('    $domain · $country · ${a['seendate'] ?? ''}');
      if ('${a['url'] ?? ''}'.isNotEmpty) lines.add('    ${a['url']}');
    }
    if (byCountry.isNotEmpty) {
      final top = byCountry.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      lines.add('\nReporting countries: ${top.take(8).map((e) => '${e.key}(${e.value})').join(', ')}');
    }
    return lines.join('\n');
  } catch (e) {
    return 'Network error reaching GDELT: $e';
  }
}

String _gdeltTimespan(String s) {
  final m = RegExp(r'(\d+)\s*([hdwm])').firstMatch(s.toLowerCase());
  if (m == null) return '7d';
  final n = m.group(1)!;
  return switch (m.group(2)) {
    'h' => '${n}h',
    'd' => '${n}d',
    'w' => '${int.parse(n) * 7}d',
    'm' => '${int.parse(n) * 30}d',
    _ => '7d',
  };
}

Future<String> monitorCountry(String country) async {
  final results = await Future.wait([
    searchNews(country).catchError((_) => ''),
    searchEvents(country, timespan: '3d').catchError((_) => ''),
    searchDisasters(region: country).catchError((_) => ''),
    searchReliefweb(country).catchError((_) => ''),
  ]);
  final sections = <String>[
    '═══ SITUATIONAL BRIEF — ${country.toUpperCase()} ═══\n',
    '── CURATED NEWS ──\n${results[0]}\n',
    '── GLOBAL EVENT COVERAGE (GDELT) ──\n${results[1]}\n',
    '── NATURAL-DISASTER ALERTS ──\n${results[2]}\n',
    '── HUMANITARIAN (ReliefWeb) ──\n${results[3]}',
  ];
  return sections.join('\n');
}

Future<String> runTool(String name, Map<String, dynamic> input) async {
  String s(String k) => '${input[k] ?? ''}'.trim();
  switch (name) {
    case 'search_news':
      final cat = s('category');
      return searchNews(s('query'), category: cat.isEmpty ? null : cat);
    case 'search_events':
      final tsp = s('timespan');
      return searchEvents(s('query'), timespan: tsp.isEmpty ? '7d' : tsp);
    case 'search_disasters':
      final reg = s('region');
      return searchDisasters(region: reg.isEmpty ? null : reg);
    case 'search_reliefweb':
      return searchReliefweb(s('query'));
    case 'monitor_country':
      return monitorCountry(s('country'));
    default:
      return 'Unknown tool: $name';
  }
}
