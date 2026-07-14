import 'package:flutter/material.dart';

import '../agent/agent.dart';
import '../models.dart';
import '../settings.dart';
import '../theme.dart';
import 'markdown_view.dart';
import 'settings_screen.dart';
import 'widgets.dart';

class ChatSession {
  ChatSession(this.id);
  final int id;
  final List<ChatMessage> messages = [];
  final ScrollController scroll = ScrollController();
  final TextEditingController input = TextEditingController();
  OsintAgent? agent;
  bool busy = false;

  String get title {
    final firstUser = messages.where((m) => m.role == Role.user);
    if (firstUser.isEmpty) return 'new chat';
    final t = firstUser.first.text.trim().replaceAll('\n', ' ');
    return t.length > 22 ? '${t.substring(0, 22)}…' : t;
  }

  void dispose() {
    scroll.dispose();
    input.dispose();
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.settings});
  final AppSettings settings;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _focus = FocusNode();
  final List<ChatSession> _sessions = [];
  int _activeIdx = 0;
  int _nextId = 1;

  ChatSession get _s => _sessions[_activeIdx];
  OsintPalette get _p => OsintPalette.of(widget.settings.theme);

  @override
  void initState() {
    super.initState();
    _sessions.add(ChatSession(_nextId++));
    widget.settings.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    for (final s in _sessions) {
      if (!s.busy) s.agent = null;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettingsChanged);
    for (final s in _sessions) {
      s.dispose();
    }
    _focus.dispose();
    super.dispose();
  }

  void _scrollToEnd(ChatSession s) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (s.scroll.hasClients) {
        s.scroll.animateTo(s.scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _newTab() {
    setState(() {
      _sessions.add(ChatSession(_nextId++));
      _activeIdx = _sessions.length - 1;
    });
    _focus.requestFocus();
  }

  void _closeTab(int index) {
    final s = _sessions[index];
    setState(() {
      _sessions.removeAt(index);
      if (_sessions.isEmpty) _sessions.add(ChatSession(_nextId++));
      _activeIdx = _activeIdx.clamp(0, _sessions.length - 1);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => s.dispose());
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SettingsScreen(settings: widget.settings),
    ));
  }

  Future<void> _submit() async {
    final session = _s;
    final text = session.input.text.trim();
    if (text.isEmpty || session.busy) return;

    if (!widget.settings.hasKey) {
      await _openSettings();
      return;
    }

    session.input.clear();
    final assistant = ChatMessage(role: Role.assistant);
    setState(() {
      session.messages.add(ChatMessage(role: Role.user, text: text));
      session.messages.add(assistant);
      session.busy = true;
    });
    _scrollToEnd(session);

    session.agent ??= OsintAgent(
      widget.settings.provider,
      widget.settings.apiKey,
      widget.settings.model,
    );
    final agent = session.agent!;

    try {
      await for (final ev in agent.send(text)) {
        setState(() {
          switch (ev) {
            case TextEvent(:final text):
              assistant.text =
                  assistant.text.isEmpty ? text : '${assistant.text}\n\n$text';
            case ToolStartEvent(:final name, :final input):
              assistant.tools.add(ToolCall(name: name, input: input));
            case ToolEndEvent(:final output, :final elapsedMs, :final isError):
              final tc = assistant.tools.lastWhere(
                  (t) => t.status == ToolStatus.running,
                  orElse: () => assistant.tools.last);
              tc.output = output;
              tc.elapsedMs = elapsedMs;
              tc.status = isError ? ToolStatus.error : ToolStatus.ok;
            case ErrorEvent(:final message):
              assistant.text = message;
              assistant.isError = true;
          }
        });
        if (session == _s) _scrollToEnd(session);
      }
    } finally {
      setState(() => session.busy = false);
      if (session == _s) {
        _scrollToEnd(session);
        _focus.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            _header(p),
            _tabStrip(p),
            Expanded(
              child: _s.messages.isEmpty
                  ? _emptyState(p)
                  : ListView.builder(
                      controller: _s.scroll,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      itemCount: _s.messages.length,
                      itemBuilder: (_, i) => _messageWidget(_s.messages[i], p),
                    ),
            ),
            _statusBar(p),
            _composer(p),
            _footer(p),
          ],
        ),
      ),
    );
  }

  Widget _header(OsintPalette p) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
      child: Row(
        children: [
          Text('●', style: TextStyle(color: p.accent, fontSize: 12)),
          const SizedBox(width: 8),
          Text('osint-mcp', style: mono(color: p.text, size: 15, weight: FontWeight.w700)),
          const SizedBox(width: 8),
          Text('mobile', style: mono(color: p.cloud, size: 11)),
          const Spacer(),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.tune, color: p.muted, size: 20),
            onPressed: _openSettings,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.add, color: p.accent, size: 22),
            tooltip: 'New tab',
            onPressed: _newTab,
          ),
        ],
      ),
    );
  }

  Widget _tabStrip(OsintPalette p) {
    return Container(
      height: 38,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        itemCount: _sessions.length,
        itemBuilder: (_, i) => _tab(p, i),
      ),
    );
  }

  Widget _tab(OsintPalette p, int i) {
    final s = _sessions[i];
    final active = i == _activeIdx;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: () => setState(() => _activeIdx = i),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.only(left: 10, right: 4),
          decoration: BoxDecoration(
            color: active ? p.accent.withValues(alpha: 0.12) : p.surface,
            border: Border.all(color: active ? p.accent : p.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (s.busy)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text('●', style: TextStyle(color: p.cloud, fontSize: 8)),
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(
                        color: active ? p.accent : p.muted,
                        size: 12,
                        weight: active ? FontWeight.w600 : FontWeight.w400)),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: Icon(Icons.close, size: 14, color: p.muted),
                onPressed: () => _closeTab(i),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState(OsintPalette p) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              child: Text(kAsciiBanner,
                  style: mono(color: p.accent, size: 11, height: 1.05, letterSpacing: 0)),
            ),
            const SizedBox(height: 20),
            Text('agent-driven OSINT news console', style: mono(color: p.muted, size: 13)),
            const SizedBox(height: 4),
            Text('by SN', style: mono(color: p.cloud, size: 12)),
            if (!widget.settings.hasKey) ...[
              const SizedBox(height: 20),
              _keyPrompt(p),
            ],
          ],
        ),
      ),
    );
  }

  Widget _keyPrompt(OsintPalette p) {
    return TextButton.icon(
      onPressed: _openSettings,
      icon: Icon(Icons.key, color: p.warn, size: 16),
      label: Text('Add your ${widget.settings.provider.label} API key to begin',
          style: mono(color: p.warn, size: 12)),
    );
  }

  Widget _messageWidget(ChatMessage m, OsintPalette p) {
    if (m.role == Role.user) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('› ', style: mono(color: p.accent, size: 14, weight: FontWeight.w700)),
            Expanded(
              child: SelectableText(m.text,
                  style: mono(color: p.text, size: 14, weight: FontWeight.w600)),
            ),
          ],
        ),
      );
    }
    final showThinking = m.text.isEmpty && m.tools.isEmpty && _s.busy;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final t in m.tools) ToolCard(call: t, palette: p),
          if (m.text.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: m.tools.isEmpty ? 0 : 10),
              child: MarkdownView(data: m.text, palette: p, isError: m.isError),
            ),
          if (showThinking)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Spinner(palette: p),
            ),
        ],
      ),
    );
  }

  Widget _statusBar(OsintPalette p) {
    final state = _s.busy ? 'working' : 'ready';
    final dot = _s.busy ? p.cloud : p.ok;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text('●', style: TextStyle(color: dot, fontSize: 9)),
          const SizedBox(width: 6),
          Text(state, style: mono(color: p.muted, size: 11)),
          const SizedBox(width: 12),
          Expanded(
            child: Text('${widget.settings.provider.label} · ${widget.settings.model}',
                textAlign: TextAlign.right,
                style: mono(color: p.muted, size: 11),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _composer(OsintPalette p) {
    final busy = _s.busy;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: p.accent, width: 1.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('›', style: mono(color: p.accent, size: 16, weight: FontWeight.w700)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _s.input,
              focusNode: _focus,
              enabled: !busy,
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              style: mono(color: p.text, size: 14),
              cursorColor: p.accent,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: busy ? 'investigating…' : 'ask about any event, place, or situation',
                hintStyle: mono(color: p.muted, size: 13),
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(busy ? Icons.hourglass_empty : Icons.arrow_upward,
                color: busy ? p.muted : p.accent, size: 20),
            onPressed: busy ? null : _submit,
          ),
        ],
      ),
    );
  }

  Widget _footer(OsintPalette p) {
    final cloud = mono(color: p.cloud, size: 10);
    final muted = mono(color: p.muted, size: 10);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: 'enter', style: cloud),
                TextSpan(text: ' send   ', style: muted),
                TextSpan(text: 'tap link', style: cloud),
                TextSpan(text: ' web view', style: muted),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text('byo-key llm', style: muted),
        ],
      ),
    );
  }
}
