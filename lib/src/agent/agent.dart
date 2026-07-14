import '../settings.dart';
import '../tools/news_tools.dart';
import 'providers.dart';

sealed class AgentEvent {}

class TextEvent extends AgentEvent {
  TextEvent(this.text);
  final String text;
}

class ToolStartEvent extends AgentEvent {
  ToolStartEvent(this.name, this.input);
  final String name;
  final Map<String, dynamic> input;
}

class ToolEndEvent extends AgentEvent {
  ToolEndEvent(this.name, this.output, this.elapsedMs, this.isError);
  final String name;
  final String output;
  final int elapsedMs;
  final bool isError;
}

class ErrorEvent extends AgentEvent {
  ErrorEvent(this.message);
  final String message;
}

const _maxToolRounds = 6;

class OsintAgent {
  OsintAgent(this.provider, String apiKey, String model)
      : _client = LlmClient(provider, apiKey, model);

  final LlmProvider provider;
  final LlmClient _client;
  final List<Map<String, dynamic>> _history = [];

  void reset() => _history.clear();

  Stream<AgentEvent> send(String userText) async* {
    _history.add({
      'role': 'user',
      'content': [
        {'type': 'text', 'text': userText}
      ],
    });

    final system = buildSystem();
    for (var round = 0; round < _maxToolRounds; round++) {
      final AssistantTurn turn;
      try {
        turn = await _client.next(system, _history);
      } on LlmException catch (e) {
        yield ErrorEvent(e.message);
        return;
      } catch (e) {
        yield ErrorEvent('Unexpected error: $e');
        return;
      }

      _history.add({'role': 'assistant', 'content': turn.canonicalBlocks});

      if (turn.text.trim().isNotEmpty) yield TextEvent(turn.text);

      if (!turn.wantsTools) return;

      final results = <Map<String, dynamic>>[];
      for (final call in turn.toolUses) {
        yield ToolStartEvent(call.name, call.input);
        final started = DateTime.now();
        String output;
        var isError = false;
        try {
          output = await runTool(call.name, call.input);
        } catch (e) {
          output = 'Tool error: $e';
          isError = true;
        }
        final elapsed = DateTime.now().difference(started).inMilliseconds;
        yield ToolEndEvent(call.name, output, elapsed, isError);
        results.add({
          'type': 'tool_result',
          'tool_use_id': call.id,
          'content': output,
          if (isError) 'is_error': true,
        });
      }
      _history.add({'role': 'user', 'content': results});
    }
    yield ErrorEvent('Stopped after $_maxToolRounds tool rounds without a final answer.');
  }
}
