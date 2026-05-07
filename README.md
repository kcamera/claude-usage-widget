# ClaudeUsageWidget

A small macOS menu bar app + always-on-top floating panel that surfaces my Claude Pro usage at a glance, so I stop interrupting flow to check `claude.ai/settings/usage` after every prompt.

Personal project. Local-only in Phase 1. Not distributed.

## What it does

- **Menu bar item**: Claude mark + compact `X% · Y%` readout (5h rolling · 7d rolling).
- **Floating panel** (chromeless, draggable, optional always-on-top): per-window radial dial with family-segmented arcs (Opus / Sonnet / Haiku), reset countdowns, raw input/output/cache token totals broken out per *exact* model version (e.g. `claude-opus-4-7` vs `claude-opus-4-6`).
- **Live updates** via FSEvents on `~/.claude/projects/`, with a 30s poll backstop.
- **User calibration**: enter your real `claude.ai/settings/usage` % when you see it; the widget fits a scale parameter and uses it for the soft-% going forward. Honesty badge per window: `Estimated` vs `Calibrated (n samples)`.

## Data source

Parses Claude Code session logs at `~/.claude/projects/<encoded-cwd>/<session-uuid>.jsonl`. Only `type: "assistant"` events with a `message.usage` block are counted. Cross-checked against `npx ccusage` during development — totals agree.

**Caveat**: this is local-only. Claude Desktop **Chat tab** usage does not write to `~/.claude/projects/`, so the local soft-% systematically under-counts if you mix Chat + Code use. Calibration narrows the gap; Phase 2 (planned) closes it via a WKWebView scrape of `claude.ai/settings/usage`.

## Build & run

Requires Xcode 16+, macOS 14+ (Sonoma).

```
open ClaudeUsageWidget/ClaudeUsageWidget.xcodeproj
```

Build & run the `ClaudeUsageWidget` scheme. App is `LSUIElement` (no Dock icon). App Sandbox is off so it can read `~/.claude/`.

## Calibration — known limitation

The shipped Phase 1 estimator uses an absolute-through-origin least-squares fit (`% = scale × weighted_tokens`). It is **wrong** in a specific way: the true relationship has an unobservable Chat-tab offset, so the global fit doesn't pass through the most recent calibration point — typing 65% can result in a displayed value a few points off, immediately. The correct algorithm (anchor on the most recent sample + learn the marginal rate from same-window deltas) is documented but not patched here, because Phase 2's server scrape replaces this layer entirely.

If you only use the Code tab, calibration converges fine. If you also use the Chat tab regularly, treat the % as directional until Phase 2.

## Project layout

```
ClaudeUsageWidget/
  ClaudeUsageWidgetApp.swift     @main, MenuBarExtra
  AppDelegate.swift              app lifecycle, owns store + panel
  Models/                        UsageEvent, WindowSummary, ModelWeights, CalibrationSample
  Parsing/                       JSONL parser + per-file incremental byte-offset reader
  Aggregation/                   5h + 7d rolling-window bucketer
  Calibration/                   sample store + scalar/per-model fit
  Watching/                      FSEvents wrapper + poll-timer backstop
  Store/                         UsageStore (@Observable), Preferences, LaunchAtLogin
  UI/                            Panel, MenuBar, RadialDial, ClaudeMark, Preferences, sheets
```

## Status

- **Phase 1**: shipped on `phase-1` branch.
- **Phase 2** (planned, not started): authoritative server-side % via embedded WKWebView with persistent cookies. Spec lives in `~/.claude/plans/i-want-to-create-linked-balloon.md`.
