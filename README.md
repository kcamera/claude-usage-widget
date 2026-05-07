# ClaudeUsageWidget

A small macOS menu bar app + always-on-top floating panel that surfaces my Claude Pro usage at a glance, so I stop interrupting flow to check `claude.ai/settings/usage` after every prompt.

Personal project. Local-only in Phase 1. Not distributed.

## What it does

- **Menu bar item**: Claude mark + compact `X% · Y%` readout (5h rolling · 7d rolling).
- **Floating panel** (chromeless, draggable, optional always-on-top): per-window radial dial with family-segmented arcs (Opus / Sonnet / Haiku), reset countdowns, raw input/output/cache token totals broken out per *exact* model version (e.g. `claude-opus-4-7` vs `claude-opus-4-6`).
- **Live updates** via FSEvents on `~/.claude/projects/`, with a 30s poll backstop.
- **User calibration**: enter your real `claude.ai/settings/usage` % when you see it; the widget anchors to that value and learns the marginal rate from successive samples. Honesty badge per window: `Estimated`, `Calibrated (anchor only)`, or `Calibrated (n samples)`.

## Data source

Parses Claude Code session logs at `~/.claude/projects/<encoded-cwd>/<session-uuid>.jsonl`. Only `type: "assistant"` events with a `message.usage` block are counted. Cross-checked against `npx ccusage` during development — totals agree.

**Caveat**: this is local-only. Claude Desktop **Chat tab** usage does not write to `~/.claude/projects/`, so the local soft-% systematically under-counts if you mix Chat + Code use. The user-driven calibration feature narrows the gap. See "Why no automatic server polling?" below for why we don't close the gap fully.

## Build & run

Requires Xcode 16+, macOS 14+ (Sonoma).

```
open ClaudeUsageWidget/ClaudeUsageWidget.xcodeproj
```

Build & run the `ClaudeUsageWidget` scheme. App is `LSUIElement` (no Dock icon). App Sandbox is off so it can read `~/.claude/`.

## How calibration works

When you click **Calibrate** on a window card, you enter the % currently shown on `claude.ai/settings/usage`. The widget treats that value as ground truth at the moment you typed it — at that instant, the displayed % equals what you entered, exactly.

Between calibrations, the widget extrapolates using a *marginal rate* — how many percentage points each additional weighted token tends to add — learned from successive samples in the same window. With one sample the marginal rate falls back to a pricing-prior seed; with two or more in-window samples the rate is fit from your actual `Δ%` vs `Δtokens`. This handles the reality that Anthropic's % includes Chat-tab usage we can't see locally: the anchor absorbs whatever invisible Chat-tab offset exists at the moment of calibration, and we only extrapolate forward.

**Window resets.** When you see `claude.ai` reset to a fresh window, check the *"First sample in a new window"* box in the calibration sheet and enter the new reset time (relative *Resets in H hours M minutes* for the 5-hour window, absolute date+time picker for the 7-day window). The widget uses that boundary to (a) drive the panel's reset countdown, (b) expire the old anchor, and (c) avoid pairing samples across the boundary when learning the marginal rate.

If you only use the Code tab, the soft-% converges quickly with one or two calibrations per window. If you also use the Chat tab, recalibrate whenever the displayed % drifts noticeably from what you see on `claude.ai`.

## Why no automatic server polling?

This widget deliberately **does not** poll Claude's servers for usage data. There is an internal endpoint that powers the `claude.ai/settings/usage` page in your browser, and it would be technically straightforward to authenticate against it with persistent cookies and pull the official numbers every few minutes. We chose not to.

The Anthropic developer API (`api.anthropic.com`) is a fully sanctioned product with a published spec, dedicated keys, and an explicit developer agreement — programmatic access there is fine. The `claude.ai` web service is a different product: a consumer subscription accessed via browser. Its internal endpoints are not part of any documented offering, and Anthropic's consumer terms of service generally restrict automated access to the service. A widget that authenticates with your cookies and polls those endpoints — even at low cadence, on one device, reading only your own data — is a literal violation of those terms.

The realistic risk is account suspension, which would also revoke Claude Code access. That risk is small for personal-use polling, but not zero, and we judged the marginal benefit over the calibrated soft-% not worth it. **In short: this app respects the claude.ai consumer ToS by not making any network requests to Anthropic services.**

If Anthropic ever ships an officially supported usage API for Pro subscribers, we'd happily revisit.

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

Phase 1 is the shipping baseline. Server-side polling (originally scoped as Phase 2) has been deferred indefinitely on ToS grounds — see "Why no automatic server polling?" above.
