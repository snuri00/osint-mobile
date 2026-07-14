import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme.dart';

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key, required this.url, required this.palette});
  final String url;
  final OsintPalette palette;

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  int _progress = 0;
  String _host = '';

  @override
  void initState() {
    super.initState();
    _host = Uri.tryParse(widget.url)?.host ?? widget.url;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(widget.palette.bg)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => mounted ? setState(() => _progress = p) : null,
        onPageStarted: (_) => mounted ? setState(() => _progress = 0) : null,
        onPageFinished: (_) => mounted ? setState(() => _progress = 100) : null,
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _openExternal() async {
    final uri = Uri.tryParse(widget.url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        elevation: 0,
        iconTheme: IconThemeData(color: p.muted),
        title: Text(_host, style: mono(color: p.text, size: 13), overflow: TextOverflow.ellipsis),
        shape: Border(bottom: BorderSide(color: p.line)),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: p.muted, size: 20),
            onPressed: () => _controller.reload(),
          ),
          IconButton(
            icon: Icon(Icons.open_in_browser, color: p.accent, size: 20),
            tooltip: 'Open in browser',
            onPressed: _openExternal,
          ),
        ],
        bottom: _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _progress / 100,
                  minHeight: 2,
                  backgroundColor: p.bg,
                  color: p.accent,
                ),
              )
            : null,
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}

Future<void> openLink(BuildContext context, String url, OsintPalette palette) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (uri.scheme == 'http' || uri.scheme == 'https') {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WebViewScreen(url: url, palette: palette),
    ));
  } else {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
