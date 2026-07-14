import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

class Spinner extends StatefulWidget {
  const Spinner({super.key, required this.palette, this.label});
  final OsintPalette palette;
  final String? label;

  @override
  State<Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<Spinner> {
  static final _rng = Random();
  int _tick = 0;
  int _verb = 0;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _verb = _rng.nextInt(kSpinnerVerbs.length);
    _t = Timer.periodic(const Duration(milliseconds: 120), (t) {
      if (!mounted) return;
      setState(() {
        _tick++;
        if (_tick % 33 == 0) _verb = _rng.nextInt(kSpinnerVerbs.length);
      });
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(kSpinnerFrames[_tick % kSpinnerFrames.length],
            style: mono(color: p.accent, size: 14)),
        const SizedBox(width: 8),
        Text('${widget.label ?? kSpinnerVerbs[_verb]}…',
            style: mono(color: p.muted, size: 13)),
      ],
    );
  }
}

const Map<String, String> kToolIcons = {
  'search_news': '📰',
  'search_events': '🌐',
  'search_disasters': '🌋',
  'search_reliefweb': '🕊',
  'monitor_country': '🛰',
};

class ToolCard extends StatefulWidget {
  const ToolCard({super.key, required this.call, required this.palette});
  final ToolCall call;
  final OsintPalette palette;

  @override
  State<ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<ToolCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final c = widget.call;
    final icon = kToolIcons[c.name] ?? '🔧';
    final statusColor = switch (c.status) {
      ToolStatus.running => p.accent,
      ToolStatus.ok => p.ok,
      ToolStatus.error => p.warn,
    };

    Widget statusWidget;
    switch (c.status) {
      case ToolStatus.running:
        statusWidget = Spinner(palette: p, label: 'running');
      case ToolStatus.ok:
        statusWidget = Text('✓ ${((c.elapsedMs ?? 0) / 1000).toStringAsFixed(1)}s',
            style: mono(color: p.ok, size: 12));
      case ToolStatus.error:
        statusWidget = Text('✗ error', style: mono(color: p.warn, size: 12));
    }

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 2),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: statusColor.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: c.output == null ? null : () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Text(icon, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.name, style: mono(color: p.accent, size: 13, weight: FontWeight.w600)),
                        if (c.inputSummary.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(c.inputSummary,
                                style: mono(color: p.muted, size: 11),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  statusWidget,
                  if (c.output != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Icon(_open ? Icons.expand_less : Icons.expand_more,
                          size: 16, color: p.muted),
                    ),
                ],
              ),
            ),
          ),
          if (_open && c.output != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: p.line.withValues(alpha: 0.5))),
              ),
              child: SelectableText(c.output!,
                  style: mono(color: p.muted, size: 11, height: 1.5)),
            ),
        ],
      ),
    );
  }
}
