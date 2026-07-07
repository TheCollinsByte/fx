//+------------------------------------------------------------------+
//|                                             MultiStrategyEA.mq5  |
//|  Multi-strategy, multi-symbol Expert Advisor for MT5   v4.00     |
//|                                                                  |
//|  Attach to ONE chart; trades a whole basket of pairs from        |
//|  InpSymbols. All distance parameters are ATR-relative, so the    |
//|  same settings scale across pairs (EURUSD, USDJPY, GBPUSD...).   |
//|                                                                  |
//|  Strategies (each independently toggleable, own magic number):   |
//|    1. Trend-following : EMA cross + ADX/DI filter + higher-TF    |
//|                         trend alignment, ATR stops, breakeven,   |
//|                         partial close, ATR trailing              |
//|    2. Mean reversion  : RSI extreme + Bollinger band touch,      |
//|                         exit at middle band or time stop         |
//|    3. Session breakout: London-open range breakout with          |
//|                         ATR-based stop and range quality filter  |
//|                                                                  |
//|  Risk management:                                                |
//|    - Position size from % equity risk, margin-capped             |
//|    - Portfolio caps: max total positions, max total open risk %  |
//|    - Daily loss circuit breaker + total drawdown halt            |
//|    - ATR-relative spread filter (adapts to each pair)            |
//|    - Trading session window, Friday flat option                  |
//+------------------------------------------------------------------+
#property copyright "collo"
#property version   "4.00"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Symbols
input group "=== Symbols ==="
input string InpSymbols          = "EURUSD,GBPUSD,USDJPY,AUDUSD,USDCAD,XAUUSD"; // Symbol list (comma-separated, empty = chart symbol)
input string InpSymbolSuffix     = "";     // Broker symbol suffix (e.g. ".m", "pro")
input string InpTrendSymbols     = "";     // Trend: only these symbols (empty = all)
input string InpMR_Symbols       = "EURUSD,GBPUSD,AUDUSD,USDCAD"; // Mean reversion: only these symbols (empty = all)
input string InpBO_Symbols       = "";     // Breakout: only these symbols (empty = all)

//--- Risk inputs
input group "=== Risk & Protection ==="
input double InpRiskPercent      = 0.7;    // Risk per trade (% of equity)
input double InpMaxOpenRiskPct   = 4.0;    // Max total open risk across basket (% of equity)
input int    InpMaxTotalPos      = 6;      // Max total open positions across basket
input int    InpMaxPosPerStrat   = 1;      // Max open positions per strategy per symbol
input double InpMaxDailyLossPct  = 4.0;    // Daily loss circuit breaker (% of day-start equity)
input double InpMaxTotalDDPct    = 15.0;   // Total drawdown halt (% from equity peak, 0=off)
input double InpMinEquityStop    = 0.0;    // Hard equity floor: halt + close all below this (account currency, 0=off)
input bool   InpShowDashboard    = true;   // Show on-chart account dashboard
input double InpMaxSpreadATRPct  = 10.0;   // Max spread as % of ATR (adapts per pair)

input group "=== News Filter (live only; tester has no calendar) ==="
input bool   InpNewsFilter       = true;   // Block entries around high-impact news
input int    InpNewsBufferMin    = 30;     // Blackout window before/after event (minutes)

input group "=== Automation & Reporting ==="
input bool   InpNotifyPush       = false;  // Push notifications (needs MetaQuotes ID in terminal)
input bool   InpNotifyTrades     = true;   // Notify on closed trades (journal always; push if enabled)
input bool   InpLogTradesCSV     = true;   // Append closed trades to MultiStrategyEA_trades.csv
input int    InpLossStreakN      = 3;      // Halve risk after N consecutive losses (0=off)
input double InpThrottleFactor   = 0.5;    // Risk multiplier while throttled

input group "=== Session Control ==="
input int    InpSessionStartHr   = 0;      // Entry window start hour, server time (trend/MR)
input int    InpSessionEndHr     = 24;     // Entry window end hour, server time (trend/MR)
input bool   InpCloseFriday      = true;   // Close everything before weekend
input int    InpFridayCloseHr    = 20;     // Friday flat hour (server time)

//--- Trend-following inputs
input group "=== Strategy 1: Trend Following ==="
input bool   InpTrendEnabled     = true;   // Enable trend strategy
input int    InpTrendFastEMA     = 20;     // Fast EMA period
input int    InpTrendSlowEMA     = 50;     // Slow EMA period
input int    InpTrendADXPeriod   = 14;     // ADX period
input double InpTrendADXMin      = 22.0;   // Min ADX to allow entry
input bool   InpTrendUseDI       = true;   // Require DI+/DI- direction agreement
input bool   InpTrendUseHTF      = true;   // Require higher-TF trend alignment
input ENUM_TIMEFRAMES InpTrendHTF = PERIOD_H4; // Higher timeframe
input int    InpTrendHTF_EMA     = 50;     // Higher-TF EMA period
input double InpTrendSL_ATR      = 2.0;    // Stop loss (ATR multiples)
input double InpTrendTP_ATR      = 4.0;    // Take profit (ATR multiples)
input double InpTrendTrail_ATR   = 2.5;    // Trailing stop distance (ATR multiples)
input bool   InpTrendUseBE       = true;   // TP ladder: partial+BE at +1R, partial+lock at +2R
input double InpTrendPartialPct  = 50.0;   // Partial close size (% of position at each rung)
input double InpTrendRung2_R     = 2.0;    // Second rung trigger (R multiples, 0=off)
input long   InpTrendMagic       = 610001; // Magic number

//--- Mean-reversion inputs
input group "=== Strategy 2: Mean Reversion ==="
input bool   InpMR_Enabled       = true;   // Enable mean-reversion strategy
input int    InpMR_RSIPeriod     = 14;     // RSI period
input double InpMR_RSILow        = 30.0;   // RSI oversold threshold
input double InpMR_RSIHigh       = 70.0;   // RSI overbought threshold
input int    InpMR_BBPeriod      = 20;     // Bollinger period
input double InpMR_BBDev         = 2.0;    // Bollinger deviation
input double InpMR_SL_ATR        = 2.5;    // Stop loss (ATR multiples)
input double InpMR_ADXMax        = 25.0;   // Max ADX (skip strong trends)
input int    InpMR_TimeStopBars  = 24;     // Time stop: close after N bars (0=off)
input long   InpMR_Magic         = 610002; // Magic number

//--- Breakout inputs
input group "=== Strategy 3: London Breakout ==="
input bool   InpBO_Enabled       = true;   // Enable breakout strategy
input int    InpBO_RangeStartHr  = 0;      // Range start hour (server time)
input int    InpBO_RangeEndHr    = 7;      // Range end hour (server time)
input int    InpBO_TradeEndHr    = 16;     // Stop entering after this hour
input double InpBO_MinRangeATR   = 0.3;    // Min range height (ATR multiples, skip dead days)
input double InpBO_MaxRangeATR   = 3.0;    // Max range height (ATR multiples, skip news spikes)
input double InpBO_SL_ATR        = 1.5;    // Stop loss (ATR multiples)
input double InpBO_TP_RangeMult  = 1.0;    // Take profit (range-height multiples)
input long   InpBO_Magic         = 610003; // Magic number

//--- Shared
input group "=== Shared ==="
input ENUM_TIMEFRAMES InpTF      = PERIOD_H1; // Working timeframe (all symbols)
input int    InpATRPeriod        = 14;     // ATR period

//+------------------------------------------------------------------+
//| Per-symbol runtime context                                       |
//+------------------------------------------------------------------+
struct SymbolContext
  {
   string   name;
   int      hFastEMA;
   int      hSlowEMA;
   int      hHTF_EMA;
   int      hADX;
   int      hRSI;
   int      hBands;
   int      hATR;
   datetime lastBarTime;
   // breakout state (reset daily)
   double   boRangeHigh;
   double   boRangeLow;
   bool     boRangeSet;
   bool     boLongDone;
   bool     boShortDone;
  };

//--- Globals
CTrade         g_trade;
CPositionInfo  g_pos;
SymbolContext  g_ctx[];
int            g_nSymbols       = 0;

datetime g_currentDay     = 0;
double   g_dayStartEquity = 0.0;
double   g_equityPeak     = 0.0;
bool     g_haltedToday    = false;
bool     g_haltedTotal    = false;

int      g_lossStreak     = 0;      // consecutive losing closed trades
datetime g_newsCacheTime  = 0;      // last calendar sweep
string   g_newsCurrencies = "";     // currencies in blackout, e.g. "USD,EUR,"
bool     g_isTester       = false;

//+------------------------------------------------------------------+
int OnInit()
  {
   // parse symbol list
   string raw = InpSymbols;
   StringTrimLeft(raw);
   StringTrimRight(raw);
   string parts[];
   int n = 0;
   if(raw == "")
     {
      ArrayResize(parts, 1);
      parts[0] = _Symbol;
      n = 1;
     }
   else
      n = StringSplit(raw, ',', parts);

   ArrayResize(g_ctx, 0);
   for(int i = 0; i < n; i++)
     {
      string s = parts[i];
      StringTrimLeft(s);
      StringTrimRight(s);
      if(s == "")
         continue;
      if(InpSymbolSuffix != "" && StringFind(s, InpSymbolSuffix) < 0)
         s += InpSymbolSuffix;

      if(!SymbolSelect(s, true))
        {
         PrintFormat("Symbol %s not found — skipped", s);
         continue;
        }

      SymbolContext ctx;
      ctx.name        = s;
      ctx.hFastEMA    = iMA(s, InpTF, InpTrendFastEMA, 0, MODE_EMA, PRICE_CLOSE);
      ctx.hSlowEMA    = iMA(s, InpTF, InpTrendSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
      ctx.hADX        = iADX(s, InpTF, InpTrendADXPeriod);
      ctx.hRSI        = iRSI(s, InpTF, InpMR_RSIPeriod, PRICE_CLOSE);
      ctx.hBands      = iBands(s, InpTF, InpMR_BBPeriod, 0, InpMR_BBDev, PRICE_CLOSE);
      ctx.hATR        = iATR(s, InpTF, InpATRPeriod);
      ctx.hHTF_EMA    = InpTrendUseHTF
                        ? iMA(s, InpTrendHTF, InpTrendHTF_EMA, 0, MODE_EMA, PRICE_CLOSE)
                        : INVALID_HANDLE;
      ctx.lastBarTime = 0;
      ctx.boRangeHigh = 0.0;
      ctx.boRangeLow  = 0.0;
      ctx.boRangeSet  = false;
      ctx.boLongDone  = false;
      ctx.boShortDone = false;

      if(ctx.hFastEMA == INVALID_HANDLE || ctx.hSlowEMA == INVALID_HANDLE ||
         ctx.hADX == INVALID_HANDLE || ctx.hRSI == INVALID_HANDLE ||
         ctx.hBands == INVALID_HANDLE || ctx.hATR == INVALID_HANDLE ||
         (InpTrendUseHTF && ctx.hHTF_EMA == INVALID_HANDLE))
        {
         PrintFormat("Indicator handles failed for %s", s);
         return(INIT_FAILED);
        }

      int idx = ArraySize(g_ctx);
      ArrayResize(g_ctx, idx + 1);
      g_ctx[idx] = ctx;
     }

   g_nSymbols = ArraySize(g_ctx);
   if(g_nSymbols == 0)
     {
      Print("No valid symbols — nothing to trade");
      return(INIT_FAILED);
     }
   PrintFormat("MultiStrategyEA v4.00: trading %d symbols on %s",
               g_nSymbols, EnumToString(InpTF));

   g_equityPeak = AccountInfoDouble(ACCOUNT_EQUITY);
   g_isTester   = (bool)MQLInfoInteger(MQL_TESTER);
   InitLossStreakFromHistory();
   g_trade.SetDeviationInPoints(20);
   EventSetTimer(5);   // live: poll basket even when chart symbol is quiet
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   Comment("");
   for(int i = 0; i < g_nSymbols; i++)
     {
      IndicatorRelease(g_ctx[i].hFastEMA);
      IndicatorRelease(g_ctx[i].hSlowEMA);
      IndicatorRelease(g_ctx[i].hADX);
      IndicatorRelease(g_ctx[i].hRSI);
      IndicatorRelease(g_ctx[i].hBands);
      IndicatorRelease(g_ctx[i].hATR);
      if(g_ctx[i].hHTF_EMA != INVALID_HANDLE)
         IndicatorRelease(g_ctx[i].hHTF_EMA);
     }
  }

//+------------------------------------------------------------------+
void OnTick()   { ProcessAll(); }
void OnTimer()  { ProcessAll(); }

//+------------------------------------------------------------------+
void ProcessAll()
  {
   UpdateProtectionState();
   RefreshNewsCache();

   if(InpShowDashboard)
      UpdateDashboard();

   // hard equity floor: capital preservation beats everything else
   if(InpMinEquityStop > 0.0 &&
      AccountInfoDouble(ACCOUNT_EQUITY) <= InpMinEquityStop)
     {
      if(!g_haltedTotal)
        {
         g_haltedTotal = true;
         Notify(StringFormat("Equity floor %.2f reached. Closing all and halting.", InpMinEquityStop));
        }
      CloseAllOwnPositions();
      return;
     }

   if(InpCloseFriday && IsFridayFlatTime())
     {
      CloseAllOwnPositions();
      return;
     }

   if(g_haltedTotal)
      return;

   bool inSession = InSessionWindow();

   for(int i = 0; i < g_nSymbols; i++)
     {
      // management runs on every call, even when entries halted
      if(InpTrendEnabled)
         ManageTrendPositions(g_ctx[i]);

      if(!IsNewBar(g_ctx[i]))
         continue;

      if(InpMR_Enabled)
         ManageMeanReversionExits(g_ctx[i]);

      if(g_haltedToday)
         continue;
      if(!SpreadOK(g_ctx[i]))
         continue;
      if(NewsBlocked(g_ctx[i].name))
         continue;

      if(InpTrendEnabled && inSession && StrategyAllows(InpTrendSymbols, g_ctx[i].name))
         RunTrendStrategy(g_ctx[i]);
      if(InpMR_Enabled && inSession && StrategyAllows(InpMR_Symbols, g_ctx[i].name))
         RunMeanReversionEntries(g_ctx[i]);
      if(InpBO_Enabled && StrategyAllows(InpBO_Symbols, g_ctx[i].name))
         RunBreakoutStrategy(g_ctx[i]);
     }
  }

//+------------------------------------------------------------------+
//| Daily reset, daily loss breaker, total drawdown halt             |
//+------------------------------------------------------------------+
void UpdateProtectionState()
  {
   datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(today != g_currentDay)
     {
      g_currentDay     = today;
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_haltedToday    = false;
      for(int i = 0; i < g_nSymbols; i++)
        {
         g_ctx[i].boRangeSet  = false;
         g_ctx[i].boLongDone  = false;
         g_ctx[i].boShortDone = false;
        }
     }

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > g_equityPeak)
      g_equityPeak = equity;

   if(!g_haltedToday && g_dayStartEquity > 0.0)
     {
      double lossPct = (g_dayStartEquity - equity) / g_dayStartEquity * 100.0;
      if(lossPct >= InpMaxDailyLossPct)
        {
         g_haltedToday = true;
         Notify(StringFormat("Daily loss limit hit (%.2f%%). No new entries until next day.", lossPct));
        }
     }

   if(!g_haltedTotal && InpMaxTotalDDPct > 0.0 && g_equityPeak > 0.0)
     {
      double ddPct = (g_equityPeak - equity) / g_equityPeak * 100.0;
      if(ddPct >= InpMaxTotalDDPct)
        {
         g_haltedTotal = true;
         Notify(StringFormat("TOTAL drawdown limit hit (%.2f%%). EA halted — manual review required.", ddPct));
        }
     }
  }

//+------------------------------------------------------------------+
//| Notify: journal always, push optional                            |
//+------------------------------------------------------------------+
void Notify(string msg)
  {
   Print(msg);
   if(InpNotifyPush && !g_isTester)
      SendNotification("MultiStrategyEA: " + msg);
  }

//+------------------------------------------------------------------+
//| Seed the loss streak from recent account history                 |
//+------------------------------------------------------------------+
void InitLossStreakFromHistory()
  {
   g_lossStreak = 0;
   if(InpLossStreakN <= 0)
      return;
   if(!HistorySelect(TimeCurrent() - 30 * 86400, TimeCurrent()))
      return;

   int total = HistoryDealsTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0)
         continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_OUT)
         continue;
      if(!IsOwnMagic(HistoryDealGetInteger(dealTicket, DEAL_MAGIC)))
         continue;

      double pnl = HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                 + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
                 + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      if(pnl < 0.0)
         g_lossStreak++;
      else
         break;   // streak broken by most recent winner
     }
  }

//+------------------------------------------------------------------+
//| Current risk multiplier (loss-streak throttle)                   |
//+------------------------------------------------------------------+
double RiskFactor()
  {
   if(InpLossStreakN > 0 && g_lossStreak >= InpLossStreakN)
      return(InpThrottleFactor);
   return(1.0);
  }

//+------------------------------------------------------------------+
//| Closed-trade bookkeeping: streak, CSV journal, notification      |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT)
      return;
   long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(!IsOwnMagic(magic))
      return;

   double pnl = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
              + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
              + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   string sym     = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   string comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
   double volume  = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);

   // loss-streak throttle bookkeeping
   if(pnl < 0.0)
     {
      g_lossStreak++;
      if(InpLossStreakN > 0 && g_lossStreak == InpLossStreakN)
         Notify(StringFormat("%d losses in a row — risk throttled to %.0f%% until next win.",
                             g_lossStreak, InpThrottleFactor * 100.0));
     }
   else if(pnl > 0.0)
     {
      if(InpLossStreakN > 0 && g_lossStreak >= InpLossStreakN)
         Notify("Winner — risk throttle lifted.");
      g_lossStreak = 0;
     }

   if(InpNotifyTrades)
      Notify(StringFormat("Closed %s %.2f lots [%s]: %+.2f %s",
                          sym, volume, comment, pnl,
                          AccountInfoString(ACCOUNT_CURRENCY)));

   // CSV journal (terminal Files folder; tester writes to tester sandbox)
   if(InpLogTradesCSV)
     {
      int fh = FileOpen("MultiStrategyEA_trades.csv",
                        FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ';');
      if(fh != INVALID_HANDLE)
        {
         if(FileSize(fh) == 0)
            FileWrite(fh, "time", "symbol", "magic", "comment", "volume",
                      "pnl", "balance_after");
         FileSeek(fh, 0, SEEK_END);
         FileWrite(fh, TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES),
                   sym, magic, comment, DoubleToString(volume, 2),
                   DoubleToString(pnl, 2),
                   DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
         FileClose(fh);
        }
     }
  }

//+------------------------------------------------------------------+
//| News filter: sweep the built-in economic calendar every 5 min,   |
//| collect currencies with high-impact events inside the blackout   |
//| window. No calendar in the Strategy Tester -> filter no-ops.     |
//+------------------------------------------------------------------+
void RefreshNewsCache()
  {
   if(!InpNewsFilter || g_isTester)
      return;
   datetime now = TimeCurrent();
   if(now - g_newsCacheTime < 300)
      return;
   g_newsCacheTime  = now;
   g_newsCurrencies = "";

   MqlCalendarValue values[];
   datetime from = now - InpNewsBufferMin * 60;
   datetime to   = now + InpNewsBufferMin * 60;
   if(!CalendarValueHistory(values, from, to))
      return;

   for(int i = 0; i < ArraySize(values); i++)
     {
      MqlCalendarEvent event;
      if(!CalendarEventById(values[i].event_id, event))
         continue;
      if(event.importance != CALENDAR_IMPORTANCE_HIGH)
         continue;
      MqlCalendarCountry country;
      if(!CalendarCountryById(event.country_id, country))
         continue;
      if(StringFind(g_newsCurrencies, country.currency + ",") < 0)
         g_newsCurrencies += country.currency + ",";
     }
  }

//+------------------------------------------------------------------+
bool NewsBlocked(string sym)
  {
   if(!InpNewsFilter || g_isTester || g_newsCurrencies == "")
      return(false);
   string base   = SymbolInfoString(sym, SYMBOL_CURRENCY_BASE);
   string profit = SymbolInfoString(sym, SYMBOL_CURRENCY_PROFIT);
   return(StringFind(g_newsCurrencies, base + ",") >= 0 ||
          StringFind(g_newsCurrencies, profit + ",") >= 0);
  }

//+------------------------------------------------------------------+
//| On-chart account dashboard                                       |
//+------------------------------------------------------------------+
void UpdateDashboard()
  {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double dayPnl  = (g_dayStartEquity > 0.0)
                    ? (equity - g_dayStartEquity) / g_dayStartEquity * 100.0
                    : 0.0;
   double ddPct   = (g_equityPeak > 0.0)
                    ? (g_equityPeak - equity) / g_equityPeak * 100.0
                    : 0.0;
   string currency = AccountInfoString(ACCOUNT_CURRENCY);

   string status = "TRADING";
   if(g_haltedTotal)
      status = "HALTED (drawdown/equity floor)";
   else if(g_haltedToday)
      status = "PAUSED (daily loss limit, resumes next day)";

   string throttle = (RiskFactor() < 1.0)
                     ? StringFormat("  THROTTLED %.0f%% (%d losses)", RiskFactor() * 100.0, g_lossStreak)
                     : "";
   string news = (InpNewsFilter && g_newsCurrencies != "")
                 ? "\nNews blackout: " + g_newsCurrencies
                 : "";

   string text =
      "MultiStrategyEA v4.00  |  " + status + "\n" +
      StringFormat("Balance: %.2f %s   Equity: %.2f %s\n", balance, currency, equity, currency) +
      StringFormat("Today: %+.2f%%   Drawdown from peak: %.2f%%\n", dayPnl, ddPct) +
      StringFormat("Open positions: %d / %d   Open risk: %.2f%% / %.2f%%\n",
                   CountAllOwnPositions(), InpMaxTotalPos,
                   TotalOpenRiskPct(), InpMaxOpenRiskPct) +
      StringFormat("Risk per trade: %.2f%% of equity (auto-compounds)%s   Symbols: %d",
                   InpRiskPercent, throttle, g_nSymbols) + news;
   Comment(text);
  }

//+------------------------------------------------------------------+
bool IsFridayFlatTime()
  {
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   return(now.day_of_week == 5 && now.hour >= InpFridayCloseHr);
  }

//+------------------------------------------------------------------+
bool InSessionWindow()
  {
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   if(InpSessionStartHr <= InpSessionEndHr)
      return(now.hour >= InpSessionStartHr && now.hour < InpSessionEndHr);
   return(now.hour >= InpSessionStartHr || now.hour < InpSessionEndHr);
  }

//+------------------------------------------------------------------+
//| Spread filter, ATR-relative so it adapts to each pair            |
//+------------------------------------------------------------------+
bool SpreadOK(SymbolContext &ctx)
  {
   if(InpMaxSpreadATRPct <= 0.0)
      return(true);
   double atr = GetATR(ctx);
   if(atr == EMPTY_VALUE || atr <= 0.0)
      return(false);
   double point  = SymbolInfoDouble(ctx.name, SYMBOL_POINT);
   double spread = (double)SymbolInfoInteger(ctx.name, SYMBOL_SPREAD) * point;
   return(spread <= atr * InpMaxSpreadATRPct / 100.0);
  }

//+------------------------------------------------------------------+
bool IsNewBar(SymbolContext &ctx)
  {
   datetime barTime = iTime(ctx.name, InpTF, 0);
   if(barTime > 0 && barTime != ctx.lastBarTime)
     {
      ctx.lastBarTime = barTime;
      return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
double GetBuffer(int handle, int bufferIndex, int shift)
  {
   double buf[1];
   if(CopyBuffer(handle, bufferIndex, shift, 1, buf) != 1)
      return(EMPTY_VALUE);
   return(buf[0]);
  }

//+------------------------------------------------------------------+
double GetATR(SymbolContext &ctx, int shift = 1)
  {
   return(GetBuffer(ctx.hATR, 0, shift));
  }

//+------------------------------------------------------------------+
//| Per-strategy symbol filter. Empty list = all basket symbols.     |
//| Matches by prefix so "EURUSD" also matches broker "EURUSD.m".    |
//+------------------------------------------------------------------+
bool StrategyAllows(string listStr, string sym)
  {
   if(listStr == "")
      return(true);
   string parts[];
   int n = StringSplit(listStr, ',', parts);
   for(int i = 0; i < n; i++)
     {
      string s = parts[i];
      StringTrimLeft(s);
      StringTrimRight(s);
      if(s != "" && StringFind(sym, s) == 0)
         return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
bool IsOwnMagic(long magic)
  {
   return(magic == InpTrendMagic || magic == InpMR_Magic || magic == InpBO_Magic);
  }

//+------------------------------------------------------------------+
bool IsOwnSymbol(string sym)
  {
   for(int i = 0; i < g_nSymbols; i++)
      if(g_ctx[i].name == sym)
         return(true);
   return(false);
  }

//+------------------------------------------------------------------+
void CloseAllOwnPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(g_pos.SelectByIndex(i) &&
         IsOwnSymbol(g_pos.Symbol()) &&
         IsOwnMagic(g_pos.Magic()))
         g_trade.PositionClose(g_pos.Ticket());
     }
  }

//+------------------------------------------------------------------+
int CountPositions(string sym, long magic)
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(g_pos.SelectByIndex(i) &&
         g_pos.Symbol() == sym &&
         g_pos.Magic() == magic)
         count++;
     }
   return(count);
  }

//+------------------------------------------------------------------+
int CountAllOwnPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(g_pos.SelectByIndex(i) &&
         IsOwnSymbol(g_pos.Symbol()) &&
         IsOwnMagic(g_pos.Magic()))
         count++;
     }
   return(count);
  }

//+------------------------------------------------------------------+
//| Sum of open risk (distance to SL, in money) across the basket    |
//+------------------------------------------------------------------+
double TotalOpenRiskPct()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0)
      return(100.0);

   double riskMoney = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_pos.SelectByIndex(i))
         continue;
      if(!IsOwnSymbol(g_pos.Symbol()) || !IsOwnMagic(g_pos.Magic()))
         continue;

      double sl = g_pos.StopLoss();
      if(sl <= 0.0)
         continue;   // no SL — shouldn't happen, but don't count garbage

      string sym       = g_pos.Symbol();
      double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
      if(tickValue <= 0.0 || tickSize <= 0.0)
         continue;

      double dist = 0.0;
      if(g_pos.PositionType() == POSITION_TYPE_BUY)
         dist = g_pos.PriceOpen() - sl;    // negative once SL is past breakeven
      else
         dist = sl - g_pos.PriceOpen();
      if(dist <= 0.0)
         continue;   // risk-free position (SL at/past entry)

      riskMoney += dist / tickSize * tickValue * g_pos.Volume();
     }
   return(riskMoney / equity * 100.0);
  }

//+------------------------------------------------------------------+
//| Portfolio-level gate before any new entry                        |
//+------------------------------------------------------------------+
bool PortfolioAllowsEntry()
  {
   if(CountAllOwnPositions() >= InpMaxTotalPos)
      return(false);
   if(TotalOpenRiskPct() + InpRiskPercent > InpMaxOpenRiskPct)
      return(false);
   return(true);
  }

//+------------------------------------------------------------------+
//| Lot size from % equity risk and stop distance, margin-capped     |
//+------------------------------------------------------------------+
double CalcLots(string sym, double stopDistance, ENUM_ORDER_TYPE type)
  {
   if(stopDistance <= 0.0)
      return(0.0);

   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney  = equity * InpRiskPercent / 100.0 * RiskFactor();
   double tickValue  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0)
      return(0.0);

   double lossPerLot = stopDistance / tickSize * tickValue;
   if(lossPerLot <= 0.0)
      return(0.0);

   double lots = riskMoney / lossPerLot;

   // cap by free margin: never use more than 80% of what's available
   double price = (type == ORDER_TYPE_BUY)
                  ? SymbolInfoDouble(sym, SYMBOL_ASK)
                  : SymbolInfoDouble(sym, SYMBOL_BID);
   double marginPerLot = 0.0;
   if(OrderCalcMargin(type, sym, 1.0, price, marginPerLot) && marginPerLot > 0.0)
     {
      double freeMargin  = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double maxByMargin = freeMargin * 0.8 / marginPerLot;
      lots = MathMin(lots, maxByMargin);
     }

   double minLot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(lotStep > 0.0)
      lots = MathFloor(lots / lotStep) * lotStep;
   if(lots < minLot)
      return(0.0);   // cannot honor risk limit — skip trade rather than oversize
   lots = MathMin(maxLot, lots);
   return(NormalizeDouble(lots, 2));
  }

//+------------------------------------------------------------------+
bool OpenPosition(string sym, long magic, ENUM_ORDER_TYPE type,
                  double sl, double tp, string comment)
  {
   if(!PortfolioAllowsEntry())
      return(false);

   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double price = (type == ORDER_TYPE_BUY)
                  ? SymbolInfoDouble(sym, SYMBOL_ASK)
                  : SymbolInfoDouble(sym, SYMBOL_BID);

   double stopDistance = MathAbs(price - sl);
   double lots = CalcLots(sym, stopDistance, type);
   if(lots <= 0.0)
      return(false);

   sl = NormalizeDouble(sl, digits);
   tp = (tp > 0.0) ? NormalizeDouble(tp, digits) : 0.0;

   g_trade.SetExpertMagicNumber(magic);
   bool ok = (type == ORDER_TYPE_BUY)
             ? g_trade.Buy(lots, sym, 0.0, sl, tp, comment)
             : g_trade.Sell(lots, sym, 0.0, sl, tp, comment);
   if(!ok)
      PrintFormat("%s %s: order failed, retcode=%d", sym, comment, g_trade.ResultRetcode());
   return(ok);
  }

//+------------------------------------------------------------------+
//| Strategy 1: EMA cross + ADX/DI + higher-TF trend following       |
//+------------------------------------------------------------------+
void RunTrendStrategy(SymbolContext &ctx)
  {
   if(CountPositions(ctx.name, InpTrendMagic) >= InpMaxPosPerStrat)
      return;

   double fast1 = GetBuffer(ctx.hFastEMA, 0, 1);
   double fast2 = GetBuffer(ctx.hFastEMA, 0, 2);
   double slow1 = GetBuffer(ctx.hSlowEMA, 0, 1);
   double slow2 = GetBuffer(ctx.hSlowEMA, 0, 2);
   double adx   = GetBuffer(ctx.hADX, MAIN_LINE, 1);
   double diP   = GetBuffer(ctx.hADX, PLUSDI_LINE, 1);
   double diM   = GetBuffer(ctx.hADX, MINUSDI_LINE, 1);
   double atr   = GetATR(ctx);

   if(fast1 == EMPTY_VALUE || fast2 == EMPTY_VALUE || slow1 == EMPTY_VALUE ||
      slow2 == EMPTY_VALUE || adx == EMPTY_VALUE || diP == EMPTY_VALUE ||
      diM == EMPTY_VALUE || atr == EMPTY_VALUE || atr <= 0.0)
      return;

   if(adx < InpTrendADXMin)
      return;

   bool crossUp   = (fast2 <= slow2 && fast1 > slow1);
   bool crossDown = (fast2 >= slow2 && fast1 < slow1);
   if(!crossUp && !crossDown)
      return;

   if(InpTrendUseDI)
     {
      if(crossUp && diP <= diM)
         return;
      if(crossDown && diM <= diP)
         return;
     }

   if(InpTrendUseHTF)
     {
      double htfEMA   = GetBuffer(ctx.hHTF_EMA, 0, 1);
      double htfClose = iClose(ctx.name, InpTrendHTF, 1);
      if(htfEMA == EMPTY_VALUE || htfClose <= 0.0)
         return;
      if(crossUp && htfClose < htfEMA)
         return;   // don't buy against higher-TF downtrend
      if(crossDown && htfClose > htfEMA)
         return;   // don't sell against higher-TF uptrend
     }

   if(crossUp)
     {
      double ask = SymbolInfoDouble(ctx.name, SYMBOL_ASK);
      double sl  = ask - InpTrendSL_ATR * atr;
      double tp  = ask + InpTrendTP_ATR * atr;
      OpenPosition(ctx.name, InpTrendMagic, ORDER_TYPE_BUY, sl, tp, "Trend-L");
     }
   else
     {
      double bid = SymbolInfoDouble(ctx.name, SYMBOL_BID);
      double sl  = bid + InpTrendSL_ATR * atr;
      double tp  = bid - InpTrendTP_ATR * atr;
      OpenPosition(ctx.name, InpTrendMagic, ORDER_TYPE_SELL, sl, tp, "Trend-S");
     }
  }

//+------------------------------------------------------------------+
//| Trend position management: breakeven, partial close, trailing    |
//+------------------------------------------------------------------+
void ManageTrendPositions(SymbolContext &ctx)
  {
   double atr = GetATR(ctx);
   if(atr == EMPTY_VALUE || atr <= 0.0)
      return;
   double trailDist = InpTrendTrail_ATR * atr;
   int digits = (int)SymbolInfoInteger(ctx.name, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(ctx.name, SYMBOL_POINT);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_pos.SelectByIndex(i))
         continue;
      if(g_pos.Symbol() != ctx.name || g_pos.Magic() != InpTrendMagic)
         continue;

      ulong  ticket = g_pos.Ticket();
      double open   = g_pos.PriceOpen();
      double sl     = g_pos.StopLoss();
      double tp     = g_pos.TakeProfit();
      bool   isBuy  = (g_pos.PositionType() == POSITION_TYPE_BUY);
      double bid    = SymbolInfoDouble(ctx.name, SYMBOL_BID);
      double ask    = SymbolInfoDouble(ctx.name, SYMBOL_ASK);

      // Original 1R distance, recovered from the TP that was set at entry
      // (TP = TP_ATR multiples, SL = SL_ATR multiples of the same entry ATR).
      // Survives SL moves, unlike |open - sl|.
      double rDist = 0.0;
      if(tp > 0.0 && InpTrendTP_ATR > 0.0)
         rDist = MathAbs(tp - open) * InpTrendSL_ATR / InpTrendTP_ATR;
      else
         rDist = MathAbs(open - sl);   // fallback: pre-BE SL distance

      if(InpTrendUseBE && rDist > 0.0)
        {
         double profitDist = isBuy ? (bid - open) : (open - ask);
         // ladder stage from where SL sits relative to entry:
         //   stage 0: SL still on losing side  -> next rung is +1R (partial + BE)
         //   stage 1: SL at breakeven          -> next rung is +2R (partial + lock 1R)
         //   stage 2: SL at/beyond entry+1R    -> ladder done, trail handles the rest
         double slGain = isBuy ? (sl - open) : (sl != 0.0 ? open - sl : -rDist);
         int stage = (slGain >= 0.9 * rDist) ? 2 : (slGain >= 0.0 ? 1 : 0);

         double rungR   = 0.0;
         double lockSL  = 0.0;
         if(stage == 0 && profitDist >= rDist)
           {
            rungR  = 1.0;
            lockSL = isBuy ? open + 2 * point : open - 2 * point;   // breakeven
           }
         else if(stage == 1 && InpTrendRung2_R > 0.0 && profitDist >= InpTrendRung2_R * rDist)
           {
            rungR  = InpTrendRung2_R;
            lockSL = isBuy ? open + rDist : open - rDist;           // lock +1R
           }

         if(rungR > 0.0)
           {
            double lotStep = SymbolInfoDouble(ctx.name, SYMBOL_VOLUME_STEP);
            double minLot  = SymbolInfoDouble(ctx.name, SYMBOL_VOLUME_MIN);
            double part    = g_pos.Volume() * InpTrendPartialPct / 100.0;
            if(lotStep > 0.0)
               part = MathFloor(part / lotStep) * lotStep;
            if(part >= minLot && g_pos.Volume() - part >= minLot)
               g_trade.PositionClosePartial(ticket, part);

            g_trade.PositionModify(ticket, NormalizeDouble(lockSL, digits), tp);
            continue;   // re-evaluate trailing next call with fresh state
           }
        }

      // ATR trailing
      if(isBuy)
        {
         double newSL = NormalizeDouble(bid - trailDist, digits);
         if(newSL > sl && newSL < bid)
            g_trade.PositionModify(ticket, newSL, tp);
        }
      else
        {
         double newSL = NormalizeDouble(ask + trailDist, digits);
         if((newSL < sl || sl == 0.0) && newSL > ask)
            g_trade.PositionModify(ticket, newSL, tp);
        }
     }
  }

//+------------------------------------------------------------------+
//| Strategy 2: mean reversion — exits (middle band / time stop)     |
//+------------------------------------------------------------------+
void ManageMeanReversionExits(SymbolContext &ctx)
  {
   double bbMid  = GetBuffer(ctx.hBands, BASE_LINE, 1);
   double close1 = iClose(ctx.name, InpTF, 1);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_pos.SelectByIndex(i))
         continue;
      if(g_pos.Symbol() != ctx.name || g_pos.Magic() != InpMR_Magic)
         continue;

      bool closeIt = false;

      if(bbMid != EMPTY_VALUE && close1 > 0.0)
        {
         if((g_pos.PositionType() == POSITION_TYPE_BUY  && close1 >= bbMid) ||
            (g_pos.PositionType() == POSITION_TYPE_SELL && close1 <= bbMid))
            closeIt = true;
         else
           {
            // keep the TP order anchored to the current middle band so the
            // position can hit TP intrabar, not just on bar-close checks
            int digits = (int)SymbolInfoInteger(ctx.name, SYMBOL_DIGITS);
            double newTP = NormalizeDouble(bbMid, digits);
            double tickSz = SymbolInfoDouble(ctx.name, SYMBOL_TRADE_TICK_SIZE);
            if(MathAbs(newTP - g_pos.TakeProfit()) > tickSz)
               g_trade.PositionModify(g_pos.Ticket(), g_pos.StopLoss(), newTP);
           }
        }

      // time stop: reversion thesis expired
      if(!closeIt && InpMR_TimeStopBars > 0)
        {
         int barsHeld = Bars(ctx.name, InpTF, g_pos.Time(), TimeCurrent()) - 1;
         if(barsHeld >= InpMR_TimeStopBars)
            closeIt = true;
        }

      if(closeIt)
         g_trade.PositionClose(g_pos.Ticket());
     }
  }

//+------------------------------------------------------------------+
//| Strategy 2: mean reversion — entries                             |
//+------------------------------------------------------------------+
void RunMeanReversionEntries(SymbolContext &ctx)
  {
   if(CountPositions(ctx.name, InpMR_Magic) >= InpMaxPosPerStrat)
      return;

   double rsi    = GetBuffer(ctx.hRSI, 0, 1);
   double bbUp   = GetBuffer(ctx.hBands, UPPER_BAND, 1);
   double bbLow  = GetBuffer(ctx.hBands, LOWER_BAND, 1);
   double adx    = GetBuffer(ctx.hADX, MAIN_LINE, 1);
   double atr    = GetATR(ctx);
   double close1 = iClose(ctx.name, InpTF, 1);

   if(rsi == EMPTY_VALUE || bbUp == EMPTY_VALUE || bbLow == EMPTY_VALUE ||
      adx == EMPTY_VALUE || atr == EMPTY_VALUE || atr <= 0.0 || close1 <= 0.0)
      return;

   // skip strong trends — fading them is how mean reversion dies
   if(adx > InpMR_ADXMax)
      return;

   double bbMid = GetBuffer(ctx.hBands, BASE_LINE, 1);

   if(rsi <= InpMR_RSILow && close1 <= bbLow)
     {
      double ask = SymbolInfoDouble(ctx.name, SYMBOL_ASK);
      double sl  = ask - InpMR_SL_ATR * atr;
      double tp  = (bbMid != EMPTY_VALUE && bbMid > ask) ? bbMid : 0.0;
      OpenPosition(ctx.name, InpMR_Magic, ORDER_TYPE_BUY, sl, tp, "MR-L");
     }
   else if(rsi >= InpMR_RSIHigh && close1 >= bbUp)
     {
      double bid = SymbolInfoDouble(ctx.name, SYMBOL_BID);
      double sl  = bid + InpMR_SL_ATR * atr;
      double tp  = (bbMid != EMPTY_VALUE && bbMid < bid) ? bbMid : 0.0;
      OpenPosition(ctx.name, InpMR_Magic, ORDER_TYPE_SELL, sl, tp, "MR-S");
     }
  }

//+------------------------------------------------------------------+
//| Strategy 3: London-open range breakout                           |
//+------------------------------------------------------------------+
void RunBreakoutStrategy(SymbolContext &ctx)
  {
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   double atr = GetATR(ctx);
   if(atr == EMPTY_VALUE || atr <= 0.0)
      return;

   // build the range once the range window has closed
   if(!ctx.boRangeSet && now.hour >= InpBO_RangeEndHr)
     {
      datetime rangeStart = g_currentDay + InpBO_RangeStartHr * 3600;
      datetime rangeEnd   = g_currentDay + InpBO_RangeEndHr   * 3600;
      int startBar = iBarShift(ctx.name, InpTF, rangeStart);
      int endBar   = iBarShift(ctx.name, InpTF, rangeEnd);
      if(startBar < 0 || endBar < 0 || startBar <= endBar)
         return;

      int count = startBar - endBar + 1;
      int hiIdx = iHighest(ctx.name, InpTF, MODE_HIGH, count, endBar);
      int loIdx = iLowest(ctx.name, InpTF, MODE_LOW, count, endBar);
      if(hiIdx < 0 || loIdx < 0)
         return;

      double hi = iHigh(ctx.name, InpTF, hiIdx);
      double lo = iLow(ctx.name, InpTF, loIdx);
      double height = hi - lo;

      // quality filter: skip dead ranges and news-spike ranges
      if(height < InpBO_MinRangeATR * atr || height > InpBO_MaxRangeATR * atr)
        {
         ctx.boRangeSet  = true;   // mark evaluated so we don't rebuild all day
         ctx.boLongDone  = true;   // but disable both directions
         ctx.boShortDone = true;
         return;
        }

      ctx.boRangeHigh = hi;
      ctx.boRangeLow  = lo;
      ctx.boRangeSet  = true;
     }

   if(!ctx.boRangeSet || now.hour >= InpBO_TradeEndHr)
      return;
   if(CountPositions(ctx.name, InpBO_Magic) >= InpMaxPosPerStrat)
      return;

   double close1      = iClose(ctx.name, InpTF, 1);
   double rangeHeight = ctx.boRangeHigh - ctx.boRangeLow;
   if(close1 <= 0.0 || rangeHeight <= 0.0)
      return;

   if(!ctx.boLongDone && close1 > ctx.boRangeHigh)
     {
      double ask = SymbolInfoDouble(ctx.name, SYMBOL_ASK);
      double sl  = ask - InpBO_SL_ATR * atr;
      double tp  = ask + InpBO_TP_RangeMult * rangeHeight;
      if(OpenPosition(ctx.name, InpBO_Magic, ORDER_TYPE_BUY, sl, tp, "BO-L"))
         ctx.boLongDone = true;
     }
   else if(!ctx.boShortDone && close1 < ctx.boRangeLow)
     {
      double bid = SymbolInfoDouble(ctx.name, SYMBOL_BID);
      double sl  = bid + InpBO_SL_ATR * atr;
      double tp  = bid - InpBO_TP_RangeMult * rangeHeight;
      if(OpenPosition(ctx.name, InpBO_Magic, ORDER_TYPE_SELL, sl, tp, "BO-S"))
         ctx.boShortDone = true;
     }
  }

//+------------------------------------------------------------------+
//| Custom optimization criterion: reward smooth, well-sampled equity|
//| curves; punish thin trade counts and deep drawdowns.             |
//+------------------------------------------------------------------+
double OnTester()
  {
   double profit  = TesterStatistics(STAT_PROFIT);
   double maxDD   = TesterStatistics(STAT_EQUITY_DD);
   double trades  = TesterStatistics(STAT_TRADES);
   double pf      = TesterStatistics(STAT_PROFIT_FACTOR);

   if(trades < 30 || profit <= 0.0)
      return(0.0);
   if(maxDD <= 0.0)
      maxDD = 1.0;

   // recovery factor weighted by profit factor and sample size
   return(profit / maxDD * MathMin(pf, 3.0) * MathSqrt(trades));
  }
//+------------------------------------------------------------------+
