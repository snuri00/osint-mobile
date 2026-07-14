import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../theme.dart';
import 'webview_screen.dart';

class MarkdownView extends StatelessWidget {
  const MarkdownView({
    super.key,
    required this.data,
    required this.palette,
    this.isError = false,
  });

  final String data;
  final OsintPalette palette;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final base = isError ? p.warn : p.text;
    TextStyle m(double size, {Color? c, FontWeight? w, double h = 1.5}) =>
        mono(color: c ?? base, size: size, weight: w ?? FontWeight.w400, height: h);

    final sheet = MarkdownStyleSheet(
      p: m(13.5),
      h1: m(18, c: p.accent, w: FontWeight.w700, h: 1.3),
      h2: m(16, c: p.accent, w: FontWeight.w700, h: 1.3),
      h3: m(14.5, c: p.cloud, w: FontWeight.w700, h: 1.3),
      h4: m(13.5, c: p.cloud, w: FontWeight.w700),
      h5: m(13, c: p.cloud, w: FontWeight.w600),
      h6: m(12.5, c: p.cloud, w: FontWeight.w600),
      strong: m(13.5, c: base, w: FontWeight.w700),
      em: TextStyle(
          fontFamily: kMonoFamily,
          fontFamilyFallback: kMonoFallback,
          color: base,
          fontSize: 13.5,
          fontStyle: FontStyle.italic),
      a: m(13.5, c: p.accent, w: FontWeight.w600).copyWith(
          decoration: TextDecoration.underline, decorationColor: p.accent),
      code: mono(color: p.cloud, size: 12.5, height: 1.4),
      codeblockPadding: const EdgeInsets.all(10),
      codeblockDecoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(8),
      ),
      blockquote: m(13, c: p.muted),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: p.accent, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
      listBullet: m(13.5, c: p.accent),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.line)),
      ),
      tableHead: m(12.5, c: p.cloud, w: FontWeight.w700),
      tableBody: m(12.5),
      tableBorder: TableBorder.all(color: p.line, width: 0.8),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      tableColumnWidth: const FlexColumnWidth(),
    );

    return MarkdownBody(
      data: data,
      selectable: true,
      shrinkWrap: true,
      fitContent: true,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      styleSheet: sheet,
      onTapLink: (text, href, title) {
        if (href != null && href.isNotEmpty) openLink(context, href, p);
      },
    );
  }
}
