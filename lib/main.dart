import 'package:flutter/material.dart';

import 'src/settings.dart';
import 'src/theme.dart';
import 'src/tools/feeds.dart';
import 'src/ui/chat_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  await FeedRegistry.load();
  runApp(OsintApp(settings: settings));
}

class OsintApp extends StatelessWidget {
  const OsintApp({super.key, required this.settings});
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        return MaterialApp(
          title: 'osint-mcp mobile',
          debugShowCheckedModeBanner: false,
          theme: buildFlutterTheme(settings.theme),
          home: ChatScreen(settings: settings),
        );
      },
    );
  }
}
