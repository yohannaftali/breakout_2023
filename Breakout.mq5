//+---------------------------------------------------------------------------+
//|                                                                  Breakout |
//|                                             Copyright 2023, Yohan Naftali |
//+---------------------------------------------------------------------------+
#property copyright "Copyright 2023, Yohan Naftali"
#property version   "231.114"

#include "Engine.mqh"

//--- input parameters
input group "Trading Window";
input string _start = "03:50"; // Start Order Time (hh:mm) (Server Time)
input string _end = "15:30";   // End Order Time (hh:mm) (Server Time)

input group "risk Management";
input double _risk = 1;              // Risk (%)
input double _riskReward = 10;       // Risk/Reward Ratio
input double _maxVolume = 10;           // Maximum Volume (lot)
input double _stopLossPip = 1.8;     // Stop Loss (pip)
input double _trailingStopPip = 1.8; // Trailing Stop (pip)
input int _pauseTrailing = 1;        // Pause Before First Trailing (seconds)
input long _maxSpreadPip = 8;        // Maximum spread (pip)
input double _offsetPip = 0;         // Offset Upper/Lower From S/R (pip)

input group "Expert Advisor"
input ulong _magicNumber = 99999;    // EA's MagicNumber

Engine e;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnInit() {
    e.setTradingWindow(_start, _end);
    e.setRiskReward(_risk, _riskReward, _maxVolume);
    e.setSafety(_stopLossPip, _trailingStopPip, _pauseTrailing, _maxSpreadPip);
    e.setOffset(_offsetPip);
    e.setMagicNumber(_magicNumber);
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
