enum Role { user, assistant, system }

enum ToolStatus { running, ok, error }

class ToolCall {
  ToolCall({
    required this.name,
    required this.input,
    this.output,
    this.status = ToolStatus.running,
    this.elapsedMs,
  });

  final String name;
  final Map<String, dynamic> input;
  String? output;
  ToolStatus status;
  int? elapsedMs;

  String get inputSummary {
    if (input.isEmpty) return '';
    return input.entries
        .where((e) => e.value != null && '${e.value}'.isNotEmpty)
        .map((e) => '${e.key}=${e.value}')
        .join(' · ');
  }
}

class ChatMessage {
  ChatMessage({
    required this.role,
    this.text = '',
    List<ToolCall>? tools,
    this.isError = false,
  }) : tools = tools ?? <ToolCall>[];

  final Role role;
  String text;
  final List<ToolCall> tools;
  bool isError;
}
