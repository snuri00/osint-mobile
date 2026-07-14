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

Future<List<_Item>> _fetchFeed(Feed feed, Duration timeout) async {
  try {
    final resp = await http
        .get(Uri.parse(feed.url), headers: {'User-Agent': _userAgent})
        .timeout(timeout);
    if (resp.statusCode != 200) return [];
    return _parseFeed(utf8.decode(resp.bodyBytes, allowMalformed: true),
        feed.name, feed.category);
  } catch (_) {
    return [];
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

bool _matches(_Item it, List<String> terms) {
  if (terms.isEmpty) return true;
  final hay = '${it.title} ${it.summary}'.toLowerCase();
  return terms.every(hay.contains);
}

String _fmtWhen(int? epoch) {
  if (epoch == null) return 'date unknown';
  final dt = DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)} UTC';
}

Future<String> searchNews(String query, {String? category}) async {
  final reg = FeedRegistry.instance;
  final feeds = reg.select(category, _maxFeeds);
  final terms = query.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  final raw = await _gather(feeds, const Duration(seconds: 8));

  final matched = raw.where((it) => it.title.isNotEmpty && _matches(it, terms)).toList();
  final seen = <String>{};
  final deduped = <_Item>[];
  for (final it in matched) {
    final key = it.title.toLowerCase();
    if (seen.add(key)) deduped.add(it);
  }
  deduped.sort((a, b) => (b.epoch ?? 0).compareTo(a.epoch ?? 0));

  if (deduped.isEmpty) {
    return "No recent headlines matching '$query' across ${feeds.length} curated feeds.";
  }
  final lines = <String>[
    "News results for '$query' (${deduped.length} match(es) across ${feeds.length} curated feeds, most recent first):\n",
  ];
  for (final it in deduped.take(_maxResults)) {
    lines.add('[+] ${it.title}');
    lines.add('    ${it.source} (${reg.sourceFlags(it.source)}) · ${_fmtWhen(it.epoch)}');
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
