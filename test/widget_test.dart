import 'package:flutter_test/flutter_test.dart';
import 'package:osint_mobile/src/settings.dart';
import 'package:osint_mobile/src/theme.dart';

void main() {
  test('provider ids and default models are stable', () {
    expect(LlmProvider.anthropic.id, 'anthropic');
    expect(LlmProvider.deepseek.id, 'deepseek');
    expect(LlmProvider.openai.id, 'openai');
    expect(LlmProviderX.fromId('openai'), LlmProvider.openai);
    expect(LlmProviderX.fromId('bogus'), LlmProvider.anthropic);
    for (final p in LlmProvider.values) {
      expect(p.defaultModel, isNotEmpty);
    }
  });

  test('palette resolves for both theme modes', () {
    expect(OsintPalette.of(OsintThemeMode.dark).accent, OsintPalette.dark.accent);
    expect(OsintPalette.of(OsintThemeMode.light).bg, OsintPalette.light.bg);
  });
}
