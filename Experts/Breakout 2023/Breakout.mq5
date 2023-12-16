//+---------------------------------------------------------------------------+
//|                                                                  Breakout |
//|                                             Copyright 2023, Yohan Naftali |
//+---------------------------------------------------------------------------+
#property copyright "Copyright 2023, Yohan Naftali"
#property link      "https://github.com/yohannaftali"
#property version   "231.204"

#include "Engine.mqh"

//--- input parameters
input group "Trading Window";
input string start = "00:00";       // Start Order Time (hh:mm) (Server Time)
input string end = "23:59";         // End Order Time (hh:mm) (Server Time)

input group "Risk Management";
input double risk = 1;              // Risk (%)
input double riskReward = 10;       // Risk/Reward Ratio
input double stopLossPip = 0.8;     // Stop Loss (pip)
input double trailingStopPip = 0.8; // Trailing Stop (pip)
input int pauseTrailing = 1;        // Pause Between Trailing (seconds)
input long maxSpreadPip = 10;       // Maximum spread (pip)
input double offsetPip = 0;         // Offset Upper/Lower From S/R (pip)
input int pivotNo = 3;              // No of Pivot Point

input group "Expert Advisor"
input ulong magicNumber = 1;        // EA's MagicNumber

Engine e;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnInit() {
    e.setTradingWindow(start, end);
    e.setRiskReward(risk, riskReward);
    e.setSafety(stopLossPip, trailingStopPip, pauseTrailing, maxSpreadPip);
    e.setOffset(offsetPip, pivotNo);
    e.setMagicNumber(magicNumber);
    EventSetTimer(1);
    return (e.onInit());
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    e.onDeinit(reason);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick() {
    e.onTick();
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTimer() {
    e.onTimer();
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTrade() {
    e.onTrade();
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result) {
    e.onTradeTransaction(trans, request, result);
}
//+------------------------------------------------------------------+
