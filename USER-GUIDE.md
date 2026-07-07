# MultiStrategyEA v4.00 — Complete User Guide

Step-by-step manual: install, configure, backtest, go live, and understand how
the EA manages your account balance.

---

## 1. What this EA does

One EA instance, attached to one chart, trades a basket of pairs
(default: EURUSD, GBPUSD, USDJPY, AUDUSD, USDCAD, XAUUSD) with three
strategies at once:

1. **Trend following** — rides EMA-cross trends confirmed by ADX/DI and the H4
   trend. Banks profit in rungs (+1R, +2R) and trails the rest.
2. **Mean reversion** — fades RSI/Bollinger extremes in quiet markets, takes
   profit at the Bollinger middle band. Disabled on gold/yen by default.
3. **London breakout** — trades the break of the Asian-session range at London
   open, with range-quality filters.

Every stop, target, and filter is ATR-relative, so the same settings adapt to
each pair's volatility automatically.

---

## 2. How the EA handles your balance

The EA reads your account **live, every tick** — no manual input of balance
anywhere:

| Mechanism | What it does |
|---|---|
| **% -of-equity position sizing** | Every trade risks `Risk per trade %` (default 0.7%) of **current equity**. Balance grows → lot sizes grow (auto-compounding). Balance shrinks → lots shrink automatically (auto-deleveraging). You never set lot sizes. |
| **Margin cap** | A trade never uses more than 80% of free margin, whatever the risk math says. |
| **Portfolio risk cap** | Sum of open risk across all pairs capped at `Max total open risk %` (default 4% of equity). New entries blocked past the cap. |
| **Daily circuit breaker** | Day loses `Max daily loss %` (default 4%) of day-start equity → no new entries until the next day. |
| **Total drawdown halt** | Equity falls `Max total DD %` (default 15%) below its all-time-in-session peak → EA stops entirely; requires manual restart (remove/re-attach). |
| **Hard equity floor** | Optional `Min equity stop` (absolute number, e.g. 800 on a 1000 account): equity touches it → EA closes everything and halts. Ultimate capital protection. |
| **On-chart dashboard** | Top-left of the chart shows live Balance, Equity, today's P&L %, drawdown from peak, open positions, open risk vs cap, throttle state, and active news blackouts — you always see what the EA sees. |
| **Loss-streak throttle** | After 3 consecutive losing trades (configurable), risk per trade is automatically halved until the next winner. Anti-tilt for the machine. |

**Example** — 1,000 USD account, defaults: each trade risks ~7 USD. Account
grows to 2,000 → each trade risks ~14 USD. Bad day hits −40 USD → EA pauses
until tomorrow. Equity ever drops to 850 → still trading; set
`Min equity stop = 800` and if it touches 800 everything closes and stops.

---

## 3. Installing in MT5 (step by step)

1. **Open the data folder**: MT5 → *File → Open Data Folder*.
2. Navigate to `MQL5/Experts/` and copy `MultiStrategyEA.mq5` there.
3. **Compile**: open MetaEditor (F4 from MT5), find the file in the Navigator,
   open it, press **F7**. Bottom pane must say `0 errors, 0 warnings`
   (warnings are tolerable; errors are not).
4. Back in MT5, press **Ctrl+N** (Navigator) → *Expert Advisors* →
   `MultiStrategyEA` appears.
5. **Enable algo trading**: click the **Algo Trading** button in the top
   toolbar so it turns green.
6. Open **one** chart — EURUSD H1 is fine (chart symbol/period don't restrict
   the EA; the working timeframe is an input).
7. Drag `MultiStrategyEA` onto the chart. In the dialog:
   - *Common* tab → tick **Allow Algo Trading**.
   - *Inputs* tab → adjust (see section 4).
   - OK.
8. Smiley/blue hat icon top-right of the chart = running. Dashboard text
   appears top-left.

**Do not attach to a second chart** — one instance manages the whole basket;
two instances would double positions.

### Broker symbol names

Market Watch shows `EURUSD.m` or `GOLD` instead of `EURUSD`/`XAUUSD`? Either:
- set `Symbol suffix` input (e.g. `.m`), or
- edit the `Symbols` list to the exact names your broker uses.

Unknown symbols are skipped with a journal message (*Toolbox → Experts* tab).

---

## 4. Inputs explained

### Symbols
| Input | Default | Meaning |
|---|---|---|
| Symbols | EURUSD,…,XAUUSD | Basket, comma-separated. Empty = chart symbol only. |
| Symbol suffix | (empty) | Broker suffix, e.g. `.m`. |
| Trend/MR/Breakout: only these symbols | see defaults | Per-strategy allowlist; empty = all basket symbols. MR default excludes XAUUSD & USDJPY on purpose. |

### Risk & Protection
| Input | Default | Meaning |
|---|---|---|
| Risk per trade (%) | 0.7 | % of current equity risked per position. The single most important input. 0.25–0.5 conservative, 1.0 aggressive. |
| Max total open risk (%) | 4.0 | Cap on summed open risk across the basket. |
| Max total positions | 6 | Hard count cap across all pairs/strategies. |
| Max daily loss (%) | 4.0 | Daily pause threshold. |
| Max total DD (%) | 15.0 | Full halt threshold (0 = off). Prop-firm users: set below your firm's limit, e.g. 8. |
| Min equity stop | 0 (off) | Absolute equity floor in account currency. Close all + halt. |
| Max spread (% of ATR) | 10 | Skip entries when spread exceeds this fraction of ATR. |
| Show dashboard | true | On-chart account panel. |

### News Filter (v4)
| Input | Default | Meaning |
|---|---|---|
| News filter | true | Blocks new entries when a **high-impact** calendar event for either currency of a pair falls within the blackout window. Uses MT5's built-in economic calendar — no external service, no API key. USD news blocks EURUSD/USDJPY/XAUUSD…, EUR news blocks EURUSD, etc. Existing positions stay managed (stops/trails keep working). |
| News buffer (min) | 30 | Blackout = event time ± this many minutes. |

**Tester note**: the Strategy Tester has no calendar — the filter automatically
no-ops in backtests. Expect slightly better live behavior than backtests around
news (fewer spike entries).

Calendar must be enabled: MT5 → *Tools → Options → Server* → allow news, and
your broker must supply calendar data (most do).

### Automation & Reporting (v4)
| Input | Default | Meaning |
|---|---|---|
| Push notifications | false | Sends events to your phone via the MT5 mobile app. Setup: install MT5 mobile app → *Settings → Chat and Messages* shows your **MetaQuotes ID** → desktop MT5 → *Tools → Options → Notifications* → enter the ID, test. Then set this input true. |
| Notify on closed trades | true | Every closed trade logged to Experts journal (and pushed if enabled): symbol, lots, strategy, P&L. |
| Log trades CSV | true | Appends every closed trade to `MQL5/Files/MultiStrategyEA_trades.csv` (time, symbol, strategy, volume, P&L, balance after) — import into Excel/Sheets for your own analytics. |
| Loss streak N | 3 | Consecutive losses that trigger the risk throttle (0 = off). Streak survives restarts — it's re-read from account history. |
| Throttle factor | 0.5 | Risk multiplier while throttled. Lifts on the first winner. |

### Session
| Input | Default | Meaning |
|---|---|---|
| Session start/end hour | 0 / 24 | Entry window for trend & MR (server time). |
| Close Friday / hour | true / 20 | Flatten before the weekend. |

### Strategy blocks
Trend (EMA periods, ADX min, SL/TP/trail ATR multiples, TP-ladder switches),
Mean reversion (RSI/Bollinger periods and thresholds, time stop), Breakout
(range hours, range quality ATR bounds, SL/TP). Defaults are sane baselines —
change them through backtesting, not guessing.

**Breakout hours are server time.** Find your broker's UTC offset (Market Watch
clock vs UTC) and shift `Range start/end` so the range ends at London open
(07:00–08:00 UTC). Broker at UTC+2 → range 02:00–09:00.

---

## 5. Backtesting (do this before anything live)

1. MT5 → *View → Strategy Tester* (Ctrl+R).
2. Settings: Expert = MultiStrategyEA; Symbol = EURUSD; Period = H1;
   Modelling = **Every tick based on real ticks**; Date range = 3–5 years;
   Deposit = what you'll actually trade.
3. **Baseline runs**: set `Symbols` to one pair, enable one strategy, run.
   Repeat per pair/strategy. Keep combos with profit factor > 1.3,
   max DD < 20%, > 100 trades.
4. **Basket run**: full symbol list, passing strategies enabled. The combined
   equity curve should be smoother than any single pair — if a pair drags,
   remove it.
5. **Optimize** (optional): Tester → Inputs → tick parameters to vary →
   Criterion: **Custom max** (the EA scores recovery factor × profit factor ×
   √trades — resists curve-fitting). Then **validate out-of-sample**: optimize
   on 2020–2023, verify champions on 2024–2026. Discard anything that only
   wins in-sample.
6. Save good configs: Inputs tab → right-click → *Save* → `.set` file.

---

## 6. Going live (checklist)

1. ✅ Backtest passed (section 5).
2. ✅ **Demo forward test 1–3 months** on a demo account with your live broker's
   real spreads. This is not optional.
3. ✅ VPS or always-on PC — the EA must run 24/5. MT5 → *Tools → Options →
   Community/VPS* offers built-in VPS hosting; any Windows VPS works too.
4. ✅ Start live with the smallest risk: `Risk per trade = 0.25`, raise slowly
   after a profitable month.
5. ✅ Check the dashboard and *Toolbox → Experts* journal daily.
6. ✅ Withdraw profits periodically — compounding works both directions.

---

## 7. Reading the dashboard

```
MultiStrategyEA v4.00  |  TRADING
Balance: 1000.00 USD   Equity: 1012.40 USD
Today: +1.24%   Drawdown from peak: 0.00%
Open positions: 2 / 6   Open risk: 1.38% / 4.00%
Risk per trade: 0.70% of equity (auto-compounds)   Symbols: 6
News blackout: USD,
```

Extra states: `THROTTLED 50% (3 losses)` appears next to risk when the
loss-streak throttle is active; `News blackout: <currencies>` lists currencies
currently blocked around high-impact events.

- **TRADING** — normal. **PAUSED** — daily loss limit hit, resumes next day
  automatically. **HALTED** — drawdown/equity floor hit; EA will not resume
  until you remove and re-attach it (deliberate: a 15% drawdown means review,
  not auto-retry).
- **Open risk** — money lost if every open position hits its stop right now,
  as % of equity. Positions moved to breakeven count as 0.

---

## 8. FAQ / Troubleshooting

**No trades for days?** Normal. Filters (ADX, session, spread, range quality)
skip most days. Check the Experts journal for skip messages; verify Algo
Trading is green and the smiley shows on the chart.

**"Symbol not found — skipped" in journal?** Broker name mismatch — fix
`Symbols`/`Symbol suffix` (section 3).

**Order failed, retcode 10016/10014?** Broker rejected SL/TP too close or bad
volume — usually exotic broker limits; try a different pair or raise SL ATR
multiple.

**EA stopped after big loss?** By design (breaker/halt). Review what happened
before re-attaching. Don't just restart and hope.

**Restart/crash mid-trade?** Safe. All positions carry stop-loss orders on the
broker's server — they are protected even with MT5 closed. On restart the EA
re-adopts its positions via magic numbers and resumes management. The TP-ladder
stage is read from where the stop sits, so it survives restarts too.

**Can I trade other symbols (indices, crypto CFDs)?** Technically yes — ATR
scaling carries over — but backtest first; session/breakout logic assumes FX
market hours.

---

## 9. Honest expectations

No settings make every trade hit TP; no EA prints money. This one is built to
survive first (sizing, breakers, floors) and profit second (three uncorrelated
edges, profit-banking exits). Expect losing days and weeks. The workflow that
earns the "best" label: backtest → out-of-sample validate → demo forward test →
small live → iterate on real reports. Never fund it with money you can't lose.
