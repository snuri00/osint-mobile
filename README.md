# osint-mcp mobile

An agent-driven OSINT **news & situational-awareness** console for iOS and Android —
a faithful mobile adaptation of the `osint-mcp` terminal TUI.

You open the app, talk to an LLM, and it calls the news tools for you (exactly like
launching the terminal TUI). Fully standalone: **no backend server**. The news tools
run natively in Dart, and the LLM is called directly from the device with **your own
API key** (bring-your-own-key, pasted in Settings).

## What it does

- **Chat-first agent loop.** Ask about any event, place, or unfolding situation; the
  model decides which tools to run, shows the tool cards, then synthesizes a sourced brief.
- **Providers:** Anthropic, DeepSeek, OpenAI. Pick one in Settings, paste your key
  (copy-paste button included). Keys are stored encrypted on-device (`flutter_secure_storage`),
  one per provider, and only ever leave the phone in requests to that provider's API.
- **Keyless news tools** ported from `osint-mcp`:
  - `search_news` — ~500 curated RSS feeds, ranked/deduped, with source tier +
    propaganda-risk / state-affiliation flags
  - `search_events` — GDELT global coverage (DOC 2.0 ArtList)
  - `search_disasters` — USGS earthquakes + NASA EONET + GDACS
  - `search_reliefweb` — UN OCHA humanitarian reports
  - `monitor_country` — multi-source situational brief in one call

## Aesthetic

Reproduces the terminal chrome: the OSINT ASCII banner, the exact dark/light palette
(`#22d3ee` accent, `#e0a25c` cloud, `#0b1220` bg …), a monospace transcript, a
one-line status bar, a rounded-accent composer with the `›` prompt, and a footer hint.
Tool calls render as bordered cards with the braille spinner while running and an
expandable raw-output panel.

## Run

```
flutter pub get
flutter run                 # on a connected device/emulator
flutter build apk --release # Android
flutter build ios           # iOS (needs macOS + Xcode)
```

## Layout

```
lib/
  main.dart                  app entry, theme propagation, feed preload
  src/
    theme.dart               palette, mono typography, banner, spinner
    models.dart              ChatMessage / ToolCall
    settings.dart            provider + BYO-key store (secure)
    agent/
      agent.dart             tool-use loop -> AgentEvent stream
      providers.dart         Anthropic (+DeepSeek) & OpenAI clients
    tools/
      tool_defs.dart         Anthropic-format tool schemas
      feeds.dart             feed registry loader + tier/risk metadata
      news_tools.dart        RSS/GDELT/disaster/reliefweb + dispatcher
    ui/
      chat_screen.dart       TUI chrome (transcript/status/composer/footer)
      settings_screen.dart   provider, key paste, model, theme
      widgets.dart           spinner, tool card
assets/feeds.json            500 feeds + source metadata (from news_feeds.py)
```

## Known gaps / next steps

- Assistant text arrives per-turn, not token-streamed. Add SSE streaming to
  `providers.dart` for the live-typing TUI feel.
- No bundled monospace font yet — uses the platform mono fallback. Bundle
  JetBrains Mono for a pixel-identical look.
- iOS is code-complete but only Android was build-verified here (no macOS).
- Some RSS feeds may be unreachable from mobile networks; failures are skipped silently.
