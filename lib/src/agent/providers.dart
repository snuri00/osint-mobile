import 'dart:convert';
import 'package:http/http.dart' as http;

import '../settings.dart';
import '../tools/tool_defs.dart';

class ToolUse {
  ToolUse(this.id, this.name, this.input);
  final String id;
  final String name;
  final Map<String, dynamic> input;
}

class AssistantTurn {
  AssistantTurn(this.text, this.toolUses, this.canonicalBlocks);
  final String text;
  final List<ToolUse> toolUses;
  final List<Map<String, dynamic>> canonicalBlocks;
  bool get wantsTools => toolUses.isNotEmpty;
}

class LlmException implements Exception {
  LlmException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class LlmClient {
  factory LlmClient(LlmProvider provider, String apiKey, String model) {
    switch (provider) {
      case LlmProvider.anthropic:
        return AnthropicClient(apiKey, model, 'https://api.anthropic.com');
      case LlmProvider.deepseek:
        return AnthropicClient(apiKey, model, 'https://api.deepseek.com/anthropic');
      case LlmProvider.openai:
        return OpenAiClient(apiKey, model, 'https://api.openai.com');
    }
  }

  Future<AssistantTurn> next(String system, List<Map<String, dynamic>> history);
}

const _systemBase =
    'You are osint-mcp, an OSINT news and situational-awareness agent. You have '
    'tools that query curated RSS feeds, GDELT global coverage, natural-disaster '
    'sources, and UN humanitarian reporting. When a question is about current '
    'events, a place, or an unfolding situation, call the relevant tool(s) before '
    'answering, then synthesize a concise, sourced brief in Markdown.\n\n'
    'CITATIONS — this is critical:\n'
    '- Every tool result lists each headline with its article URL on the following '
    'line. When you attribute a claim to an outlet, you MUST write it as a Markdown '
    'link to that exact URL: `[Reuters](https://actual-url-from-tool)`, never the '
    'bare outlet name.\n'
    '- If several outlets back one point, link each one separately: '
    '`[Axios](url1), [NPR](url2), [Reuters](url3)`.\n'
    '- Only ever use URLs that appear verbatim in the tool output. Never invent, '
    'guess, or shorten a URL. If a claim has no URL in the tool output, state the '
    'outlet in plain text and do not fabricate a link.\n'
    '- Flag source tier / propaganda risk when the tool provides it.\n'
    '- End the brief with a `## Sources` section: a bullet list of the key articles '
    'you used, each as `[Outlet — headline](url)`.';

String buildSystem() => _systemBase;

class AnthropicClient implements LlmClient {
  AnthropicClient(this.apiKey, this.model, this.baseUrl);
  final String apiKey;
  final String model;
  final String baseUrl;

  @override
  Future<AssistantTurn> next(String system, List<Map<String, dynamic>> history) async {
    final body = {
      'model': model,
      'max_tokens': 2048,
      'system': system,
      'tools': kToolDefs,
      'messages': history,
    };
    http.Response resp;
    try {
      resp = await http
          .post(
            Uri.parse('$baseUrl/v1/messages'),
            headers: {
              'content-type': 'application/json',
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
            },
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 90));
    } catch (e) {
      throw LlmException('Cannot reach the API. Check your connection.\n$e');
    }
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw LlmException('Authentication failed — check your API key in Settings.');
    }
    if (resp.statusCode != 200) {
      throw LlmException('API error ${resp.statusCode}: ${_briefBody(resp.body)}');
    }
    final data = json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final content = (data['content'] as List).cast<Map<String, dynamic>>();
    final buf = StringBuffer();
    final tools = <ToolUse>[];
    for (final block in content) {
      if (block['type'] == 'text') {
        buf.write(block['text'] ?? '');
      } else if (block['type'] == 'tool_use') {
        tools.add(ToolUse(
          '${block['id']}',
          '${block['name']}',
          Map<String, dynamic>.from(block['input'] as Map? ?? {}),
        ));
      }
    }
    return AssistantTurn(buf.toString(), tools, content);
  }
}

class OpenAiClient implements LlmClient {
  OpenAiClient(this.apiKey, this.model, this.baseUrl);
  final String apiKey;
  final String model;
  final String baseUrl;

  List<Map<String, dynamic>> get _functions => kToolDefs
      .map((t) => {
            'type': 'function',
            'function': {
              'name': t['name'],
              'description': t['description'],
              'parameters': t['input_schema'],
            },
          })
      .toList();

  List<Map<String, dynamic>> _toOpenAi(String system, List<Map<String, dynamic>> history) {
    final out = <Map<String, dynamic>>[
      {'role': 'system', 'content': system},
    ];
    for (final msg in history) {
      final role = msg['role'];
      final content = msg['content'];
      if (content is String) {
        out.add({'role': role, 'content': content});
        continue;
      }
      final blocks = (content as List).cast<Map<String, dynamic>>();
      if (role == 'user') {
        final toolResults = blocks.where((b) => b['type'] == 'tool_result').toList();
        if (toolResults.isNotEmpty) {
          for (final tr in toolResults) {
            out.add({
              'role': 'tool',
              'tool_call_id': tr['tool_use_id'],
              'content': _blockText(tr['content']),
            });
          }
        } else {
          out.add({'role': 'user', 'content': _blockText(blocks)});
        }
      } else if (role == 'assistant') {
        final text = blocks
            .where((b) => b['type'] == 'text')
            .map((b) => b['text'])
            .join();
        final calls = blocks.where((b) => b['type'] == 'tool_use').map((b) {
          return {
            'id': b['id'],
            'type': 'function',
            'function': {
              'name': b['name'],
              'arguments': json.encode(b['input'] ?? {}),
            },
          };
        }).toList();
        out.add({
          'role': 'assistant',
          'content': text.isEmpty ? null : text,
          if (calls.isNotEmpty) 'tool_calls': calls,
        });
      }
    }
    return out;
  }

  @override
  Future<AssistantTurn> next(String system, List<Map<String, dynamic>> history) async {
    final body = {
      'model': model,
      'messages': _toOpenAi(system, history),
      'tools': _functions,
      'tool_choice': 'auto',
    };
    http.Response resp;
    try {
      resp = await http
          .post(
            Uri.parse('$baseUrl/v1/chat/completions'),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $apiKey',
            },
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 90));
    } catch (e) {
      throw LlmException('Cannot reach OpenAI. Check your connection.\n$e');
    }
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw LlmException('Authentication failed — check your API key in Settings.');
    }
    if (resp.statusCode != 200) {
      throw LlmException('OpenAI error ${resp.statusCode}: ${_briefBody(resp.body)}');
    }
    final data = json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final msg = (data['choices'] as List).first['message'] as Map<String, dynamic>;
    final text = '${msg['content'] ?? ''}';
    final tools = <ToolUse>[];
    final canonical = <Map<String, dynamic>>[];
    if (text.isNotEmpty) canonical.add({'type': 'text', 'text': text});
    final calls = (msg['tool_calls'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final c in calls) {
      final fn = c['function'] as Map<String, dynamic>;
      Map<String, dynamic> args;
      try {
        args = Map<String, dynamic>.from(json.decode('${fn['arguments']}') as Map);
      } catch (_) {
        args = {};
      }
      final id = '${c['id']}';
      tools.add(ToolUse(id, '${fn['name']}', args));
      canonical.add({'type': 'tool_use', 'id': id, 'name': fn['name'], 'input': args});
    }
    return AssistantTurn(text, tools, canonical);
  }
}

String _blockText(dynamic content) {
  if (content is String) return content;
  if (content is List) {
    return content
        .whereType<Map>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'])
        .join('\n');
  }
  return '$content';
}

String _briefBody(String body) {
  try {
    final data = json.decode(body);
    if (data is Map && data['error'] != null) {
      final err = data['error'];
      return err is Map ? '${err['message'] ?? err}' : '$err';
    }
  } catch (_) {}
  return body.length > 200 ? '${body.substring(0, 200)}…' : body;
}
