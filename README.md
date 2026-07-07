# MultiStrategyEA v4.00 — Multi-Pair MetaTrader 5 Expert Advisor

> **Full manual: [USER-GUIDE.md](USER-GUIDE.md)** — step-by-step MT5 install,
> every input explained, balance handling, backtest workflow, live checklist, FAQ.

Multi-strategy, **multi-symbol** FX EA. Attach to ONE chart — it trades the whole
basket from the `Symbols` input. Every distance parameter is ATR-relative
(stops, targets, trailing, range filters, spread filter), so the same settings
scale automatically across EURUSD, USDJPY, GBPUSD, gold, anything.

## Basket

Default: `EURUSD,GBPUSD,USDJPY,AUDUSD,USDCAD,XAUUSD`. Edit the `Symbols` input.
Broker uses suffixed names (e.g. `EURUSD.m`)? Set `Symbol suffix` to `.m`.
Empty list = chart symbol only.

**Per-strategy symbol filters** — each strategy can be restricted to a subset of
the basket (empty = all symbols):

- `Trend: only these symbols` — default empty (trend trades everything, incl. gold)
- `Mean reversion: only these symbols` — default `EURUSD,GBPUSD,AUDUSD,USDCAD`
  (**excludes XAUUSD and USDJPY** — fading gold/yen trends is how MR dies)
- `Breakout: only these symbols` — default empty

Filters match by prefix, so `EURUSD` also matches broker `EURUSD.m`.

## Strategies (per symbol, each toggleable)

| # | Strategy | Entry | Exit | Magic |
|---|----------|-------|------|-------|
| 1 | Trend following | EMA 20/50 cross + ADX ≥ 22 + DI± agreement + H4 trend alignment | TP ladder: +1R bank 50% + breakeven, +2R bank 50% of rest + lock +1R, remainder ATR-trails to 4-ATR TP | 610001 |
| 2 | Mean reversion | RSI ≤ 30 / ≥ 70 **and** close outside Bollinger, ADX ≤ 25 | Live TP order at Bollinger middle band (re-anchored every bar, fills intrabar), ATR stop, 24-bar time stop | 610002 |
| 3 | London breakout | Close breaks 00:00–07:00 range; range must be 0.3–3.0× ATR; one long + one short per day per symbol | TP = 1× range height, ATR stop | 610003 |

## Risk layers (portfolio-aware)

- **Per trade** — size from `Risk per trade (%)` (default 0.7% — lower than
  single-pair because basket exposure adds up) and stop distance, margin-capped.
- **Portfolio caps** — max 6 total open positions; new entries blocked when the
  sum of open risk (distance-to-stop in money, across all pairs) would exceed
  `Max total open risk %` (default 4%). Positions already at breakeven count as
  zero risk, so winners don't block new signals.
- **Daily circuit breaker** — no new entries after −4% day.
- **Total drawdown halt** — full stop at 15% from equity peak. Prop-firm friendly.
- **ATR-relative spread filter** — skips entry when spread > 10% of ATR; adapts
  per pair automatically (no more one-size points threshold).
- **Friday flat** — closes everything before weekend gap risk.
- **News filter (live)** — blocks entries ±30 min around high-impact calendar
  events touching either currency of a pair (built-in MT5 calendar; no-ops in tester).
- **Loss-streak throttle** — 3 consecutive losses → risk halved until next winner.
- **Automation** — push notifications to MT5 mobile app (halts, closed trades),
  CSV trade journal in `MQL5/Files/`, streak state recovered from history on restart.

## Timeframe

`Working timeframe` input (default H1) applies to all symbols regardless of the
chart the EA sits on. Chart symbol/TF only drive tick delivery; a 5-second timer
covers quiet charts in live trading.

## Install

1. Copy `MultiStrategyEA.mq5` to `<MT5 Data Folder>/MQL5/Experts/`.
2. Compile in MetaEditor (F7) — 0 errors required.
3. Attach to any single chart (EURUSD H1 fine). Enable Algo Trading.
4. Do **not** attach to multiple charts — one instance manages the basket.

## Backtest (multi-currency)

MT5 Strategy Tester backtests the whole basket in one run — it pulls data for
every symbol the EA requests:

1. Expert: MultiStrategyEA. Chart symbol: EURUSD. Period: H1.
2. Modelling: **Every tick based on real ticks**. Range: 3–5 years.
3. First runs: one symbol in the list, one strategy enabled — establish each
   pair/strategy baseline.
4. Then full basket. Compare: basket equity curve should be smoother than any
   single pair (diversification working). If not, cut the pair that drags.
5. Optimize with criterion **Custom max** (`OnTester()` = recovery factor ×
   profit factor × √trades — resists curve-fitting).
6. Out-of-sample validation: optimize 2020–2023, verify 2024–2026. In-sample-only
   winners are curve-fit — discard.
7. Accept only: profit factor > 1.3, max DD < 20%, > 100 trades.

## Per-pair tuning notes

- **Trend** works best on trending majors: EURUSD, GBPUSD, USDJPY H1–H4.
- **Mean reversion** prefers rangebound crosses: EURCHF, EURGBP, AUDNZD.
- **Breakout** wants pairs active at London open: GBPUSD, EURUSD, EURGBP.
- Don't run all three strategies on every pair blindly — backtest per
  pair/strategy, then build the basket from combos that individually pass.
  Save winning configs as `.set` preset files (Strategy Tester → Inputs →
  right-click → Save).
- Correlation warning: EURUSD/GBPUSD and AUDUSD/NZDUSD move together. Portfolio
  risk cap limits stacked exposure, but prefer mixing USD-long and USD-short
  pairs in the basket.
- Breakout hours are **server time** — align with broker UTC offset so the range
  ends at London open (07:00–08:00 UTC). Broker at UTC+2 → range 02:00–09:00.

### Gold (XAUUSD)

- Broker name varies: `XAUUSD`, `GOLD`, `XAUUSD.m` — check Market Watch, adjust
  the symbol list/suffix accordingly.
- All ATR-relative parameters adapt to gold's volatility automatically —
  including the spread filter (gold spreads are wide in points but usually fine
  as % of ATR).
- Best fits: **trend** and **breakout** strategies — gold trends hard and moves
  strongly at London/NY opens. **Mean reversion is dangerous on gold** (fading
  gold trends blows accounts) — the default MR symbol filter already excludes
  XAUUSD; only add it back if a gold-only MR backtest genuinely passes.
- Gold spikes on news (Fed, CPI, geopolitics). The 3.0× ATR max-range filter
  already skips spike days for breakout; daily loss breaker covers the rest.
- Consider lower risk on gold runs: it gaps more than majors over weekends —
  Friday flat option strongly recommended when gold is in the basket.

## Honest warning

No EA is a money printer. Defaults are sane baselines, not tuned magic. Path:
backtest per pair/strategy → build basket from passers → optimize with
out-of-sample validation → **demo forward test 1–3 months** → small live size.
Never risk money you can't afford to lose.
