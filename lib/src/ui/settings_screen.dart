import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../settings.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings});
  final AppSettings settings;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _keyCtrl;
  late final TextEditingController _modelCtrl;
  bool _obscure = true;

  AppSettings get s => widget.settings;
  OsintPalette get _p => OsintPalette.of(s.theme);

  @override
  void initState() {
    super.initState();
    _keyCtrl = TextEditingController(text: s.apiKey);
    _modelCtrl = TextEditingController(text: s.model);
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  void _syncFieldsToProvider() {
    _keyCtrl.text = s.apiKey;
    _modelCtrl.text = s.model;
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final txt = data?.text?.trim();
    if (txt != null && txt.isNotEmpty) {
      _keyCtrl.text = txt;
      await s.setApiKey(txt);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pasted ${txt.length} chars', style: mono(color: _p.bg, size: 12)),
              backgroundColor: _p.accent, duration: const Duration(seconds: 1)),
        );
      }
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        elevation: 0,
        title: Text('settings', style: mono(color: p.text, size: 15, weight: FontWeight.w700)),
        iconTheme: IconThemeData(color: p.muted),
        shape: Border(bottom: BorderSide(color: p.line)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionLabel('LLM PROVIDER', p),
          const SizedBox(height: 8),
          Row(
            children: LlmProvider.values.map((prov) {
              final active = s.provider == prov;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () async {
                      await s.setProvider(prov);
                      _syncFieldsToProvider();
                      setState(() {});
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: active ? p.accent.withValues(alpha: 0.12) : p.surface,
                        border: Border.all(color: active ? p.accent : p.line),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(prov.label,
                            style: mono(
                                color: active ? p.accent : p.muted,
                                size: 12,
                                weight: active ? FontWeight.w700 : FontWeight.w400)),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          _sectionLabel('API KEY', p),
          const SizedBox(height: 4),
          Text('Stored encrypted on this device only. Never leaves your phone except '
              'in requests to ${s.provider.consoleUrl}.',
              style: mono(color: p.muted, size: 11, height: 1.4)),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: p.line),
              borderRadius: BorderRadius.circular(10),
              color: p.surface,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _keyCtrl,
                    obscureText: _obscure,
                    style: mono(color: p.text, size: 13),
                    cursorColor: p.accent,
                    onChanged: (v) => s.setApiKey(v.trim()),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: s.provider.keyHint,
                      hintStyle: mono(color: p.muted, size: 13),
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                      color: p.muted, size: 18),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.content_paste, color: p.accent, size: 18),
                  tooltip: 'Paste',
                  onPressed: _paste,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _paste,
            icon: Icon(Icons.content_paste_go, size: 16, color: p.accent),
            label: Text('Paste from clipboard', style: mono(color: p.accent, size: 12)),
          ),
          const SizedBox(height: 24),
          _sectionLabel('MODEL', p),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: p.line),
              borderRadius: BorderRadius.circular(10),
              color: p.surface,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _modelCtrl,
              style: mono(color: p.text, size: 13),
              cursorColor: p.accent,
              onChanged: (v) => s.setModel(v.trim()),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: s.provider.defaultModel,
                hintStyle: mono(color: p.muted, size: 13),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text('Default: ${s.provider.defaultModel}', style: mono(color: p.muted, size: 11)),
          const SizedBox(height: 24),
          _sectionLabel('APPEARANCE', p),
          const SizedBox(height: 8),
          Row(
            children: [
              _themeChip('dark', OsintThemeMode.dark, p),
              const SizedBox(width: 8),
              _themeChip('light', OsintThemeMode.light, p),
            ],
          ),
          const SizedBox(height: 28),
          Center(
            child: Text('osint-mcp mobile · keyless news tools · byo-key llm',
                style: mono(color: p.muted, size: 10)),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String t, OsintPalette p) =>
      Text(t, style: mono(color: p.cloud, size: 11, weight: FontWeight.w700, letterSpacing: 1.5));

  Widget _themeChip(String label, OsintThemeMode mode, OsintPalette p) {
    final active = s.theme == mode;
    return Expanded(
      child: InkWell(
        onTap: () async {
          await s.setTheme(mode);
          setState(() {});
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: active ? p.accent.withValues(alpha: 0.12) : p.surface,
            border: Border.all(color: active ? p.accent : p.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(label,
                style: mono(color: active ? p.accent : p.muted, size: 12)),
          ),
        ),
      ),
    );
  }
}
