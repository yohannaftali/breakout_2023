//+------------------------------------------------------------------+
//|                                                           Engine |
//|                                    Copyright 2023, Yohan Naftali |
//|                                              https://yohanli.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, Yohan Naftali"
#property link      "https://github.com/yohannaftali"
#property version   "231.204"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\DealInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class Engine {
private:
    CTrade trade;
    CDealInfo deal;
    COrderInfo order;
    CPositionInfo position;
    CAccountInfo account;

    ulong magicNumber;

    // Trading Time
    // - Timing
    string beginOrderString;
    string endOrderString;
    bool isTradingTime();
    bool isNewBar();
    bool isNewM1();

    // - Quality
    int maxTimeDelay; // max allowable delay in seconds
    long maxSpread; // in pip ex 10
    int timeDelay();

    // - Order
    bool allowOrder;

    // - Trailing
    int timer;
    int pauseTrailing; // pause first trailing in seconds
    bool startTrailing;
    int noTrailing;

    // Indicators
    int zigzagHandle;
    double offsetPrice; // in price ex 0.00010
    int pivotNo;
    double resistance;
    double support;
    bool initZigZag();
    void calculateSR();
    bool calculateZigzag();
    bool calculateZigzagWithoutPivot(int barCalc);
    bool isTrendUp;

    // TP and SL
    double stopLossPoint;      // in point ex 10 point
    double stopLossPrice;      // in price ex 0.00010
    double trailingStopPrice;  // in price ex 0.00010
    double hAsk;               // highest ask price
    double lBid;               // lowest bid price
    double slPrice;            // stop loss price
    double takeProfitMargin();

    // Volume
    double riskPercentage;
    double riskReward;
    double minVolume;
    double maxVolume;
    double stepVolume;
    int digitVolume;
    void initVolume();
    double calculateVolume();
    int getDigit(double num);

    // Order
    void createOrder();
    void orderBuy(double ask, double volume);
    void orderSell(double bid, double volume);
    void updateTrailingStop();
    void clearAllOrders();

    // History Trade
    int positionLast;
    int historyLast;
    int dealLast;
    //int orderLast;
    int maxOpenOrder;
    int totalPosition();
    int totalOrder();
    int totalHistory();

    // Statistics
    int consecutiveLoss;
    int consecutiveWin;
    int maxConsecutiveLoss;
    int maxConsecutiveWin;

public:
    Engine();
    ~Engine();

    // Set Variable
    void setTradingWindow(string BeginOrder, string EndOrder);
    void setRiskReward(double RiskPercentage, double RiskReward);
    void setSafety(double StopLossPip, double TrailingStopPip, int PauseTrailing, long MaxSpreadPip);
    void setOffset(double OffsetPip, int PivotNo);
    void setMagicNumber(ulong magicNumber);

    // Events
    int onInit();
    void onTick();
    void onTrade();
    void onTimer();
    void onTradeTransaction( const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result);
    void onDeinit(const int reason);
};

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Engine::Engine() {
    maxTimeDelay = 300;
    maxOpenOrder = 2;
    positionLast = 0;
    //orderLast = 0;
    dealLast = 0;
    historyLast = 0;
    consecutiveLoss = 0;
    consecutiveWin = 0;
    maxConsecutiveLoss = 0;
    maxConsecutiveWin = 0;
    noTrailing = 0;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Engine::setTradingWindow( string BeginOrder, string EndOrder) {
    beginOrderString = BeginOrder;
    endOrderString = EndOrder;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Engine::setRiskReward(double RiskPercentage, double RiskReward) {
    riskPercentage = RiskPercentage;
    riskReward = RiskReward;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Engine::setSafety(double StopLossPip, double TrailingStopPip, int PauseTrailing, long MaxSpreadPip) {
    int pipToPoint = (Digits() == 3 || Digits() == 5) ? 10 : 1;
    stopLossPoint = StopLossPip * pipToPoint;
    stopLossPrice = NormalizeDouble(StopLossPip * pipToPoint * Point(),  Digits());
    trailingStopPrice = NormalizeDouble(TrailingStopPip * pipToPoint * Point(), Digits());
    pauseTrailing = PauseTrailing;
    maxSpread = MaxSpreadPip;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Engine::setOffset(double OffsetPip, int PivotNo) {
    int pipToPoint = (Digits() == 3 || Digits() == 5) ? 10 : 1;
    offsetPrice = NormalizeDouble(OffsetPip * pipToPoint * Point(), Digits());
    pivotNo = PivotNo;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Engine::setMagicNumber(ulong MagicNumber) {
    magicNumber = MagicNumber;
    trade.SetExpertMagicNumber(magicNumber);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int Engine::onInit() {
    initVolume();
    bool init = initZigZag();
    isTrendUp = false;
    if(!init) return (INIT_FAILED);
    positionLast = totalPosition();
    //orderLast = totalOrder();
    dealLast = 0;
    historyLast = totalHistory();
    allowOrder = false;
    startTrailing = false;
    timer = 0;
    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Engine::initVolume() {
    stepVolume = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    digitVolume = getDigit(stepVolume);
    minVolume = SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MIN);
    minVolume = NormalizeDouble(minVolume, digitVolume);
    maxVolume = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    maxVolume = NormalizeDouble(maxVolume, digitVolume);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool Engine::initZigZag() {
    resistance = 0;
    support = 0;
    int inpDepth = 12;
    int inpDeviation = 5;
    int inpBackstep = 3;

    zigzagHandle = iCustom(Symbol(), Period(), "Examples\\ZigZag", inpDepth, inpDeviation, inpBackstep);
    if(zigzagHandle == INVALID_HANDLE) {
        Print("Invalid handle indicators");
        return false;
    }

    calculateSR();
    return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Engine::onTick() {
    if(startTrailing) {
        updateTrailingStop();
        startTrailing =  false;
        timer = 0;
    }

    if(timeDelay() > maxTimeDelay) {
        clearAllOrders();
        if (isTradingTime()) {
            Print("Error: server unreachable");
        }
        return;
    }

    if(isNewBar()) {
        if(totalPosition() == 0) {
            allowOrder = true;
            calculateSR();
        }
    }

    if(allowOrder && isTradingTime()) {
        createOrder();
    }
    return;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Engine::onTimer() {
    timer ++;
    if(timer >= pauseTrailing) {
        startTrailing =  true;
        return;
    }
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Engine::calculateSR() {
    bool calculation = calculateZigzag();

    if(!calculation) {
        Print("trending detected, trade skipped for current period");
        allowOrder = false;
    }
    
    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    long spread = SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);

    string msg = "Support/Resistance: "  + DoubleToString(support, Digits()) + "/" + DoubleToString(resistance, Digits());
    static string lastMsg = "";
    if(msg != lastMsg) {
        Print(msg);
    } else {
        allowOrder = false;
    }

    if(ask >= resistance) {
        allowOrder = false;
    }

    if(bid <= support) {
        allowOrder = false;
    }

    if(spread >= maxSpread) {
        string msg = "⛔️ Spread is high (" + IntegerToString(spread) + " > " + IntegerToString(maxSpread) + ")";
        Print(msg);
        allowOrder = false;
    }

    if(resistance <= 0 || support <= 0) {
        allowOrder = false;
    }

    lastMsg = msg;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Engine::createOrder() {
    if(totalPosition() > 0) {
        Print("have position");
        return;
    }

    clearAllOrders();

    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    long spread = SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);

    if(ask > resistance) {
        Print("Ask/Bid/Spread: " + DoubleToString(ask, Digits()) + "/" + DoubleToString(bid, Digits()) + "/" + IntegerToString(spread));
        double volume = calculateVolume();
        orderBuy(ask, volume);
        return;
    }

    if(bid < support) {
        Print("Ask/Bid/Spread: " + DoubleToString(ask, Digits()) + "/" + DoubleToString(bid, Digits()) + "/" + IntegerToString(spread));
        double volume = calculateVolume();
        orderSell(bid, volume);
        return;
    }
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Engine::orderBuy(double ask, double volume) {
    hAsk = ask;
    slPrice = hAsk - stopLossPrice;
    if(slPrice <= 0) {
        string error = "SL: " + DoubleToString(slPrice, Digits()) + " must greater than 0";
        Print(error);
        return;
    }

    double tpPrice = ask + takeProfitMargin();
    trade.SetExpertMagicNumber(magicNumber);

    string msg = "Buy #" + IntegerToString(magicNumber);

    bool buy = trade.Buy(volume, Symbol(), 0.0, 0.0, 0.0, msg);

    if(!buy) {
        Print(trade.ResultComment());
        Print("Open sell failed, skip trade on current period");
    }

    allowOrder = false;
    startTrailing = false;
    noTrailing = 0;
    timer = 0;
    return;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Engine::orderSell(double bid, double volume) {
    lBid = bid;
    slPrice = lBid + stopLossPrice;

    double tpPrice = bid - takeProfitMargin();
    if(tpPrice <= 0) {
        string error = "TP: " + DoubleToString(tpPrice, Digits()) + " must greater than 0";
        Print(error);
        return;
    }

    trade.SetExpertMagicNumber(magicNumber);

    string msg = "Sell #" + IntegerToString(magicNumber);

    bool sell = trade.Sell(volume, Symbol(), 0.0, 0.0, 0.0, msg);
    if(!sell) {
        Print(trade.ResultComment());
        Print("Open sell failed, skip trade on current period");
    }

    allowOrder = false;
    startTrailing = false;
    noTrailing = 0;
    timer = 0;
    return;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Engine::updateTrailingStop() {
    if(!position.SelectByMagic(Symbol(), magicNumber)) return;

    ulong ticket = position.Ticket();

    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double spreadPrice = ask - bid;

    string tes = " Ticket #" + IntegerToString(ticket) + " " + Symbol() + " EA #" + IntegerToString(magicNumber);
    string abs = " - Ask: " + DoubleToString(ask, Digits()) + " | Bid: " + DoubleToString(bid, Digits()) + " | SL: " + DoubleToString(slPrice, Digits());

    ENUM_POSITION_TYPE type = position.PositionType();
    if(type == POSITION_TYPE_BUY) {
        double lastHAsk = hAsk;
        hAsk = ask > hAsk ? ask : hAsk;
        if(hAsk > lastHAsk) {
            noTrailing ++;
            string msg = "... Trailing up #" + IntegerToString(noTrailing) + tes + abs;
            Print(msg);
            slPrice = hAsk - trailingStopPrice;
        }

        if(ask > slPrice) return;
        if(!trade.PositionClose(ticket)) {
            string msg = "!!! Error close long position: " + trade.ResultRetcodeDescription();
            Print(msg);
            return;
        }
        return;
    }

    if(type == POSITION_TYPE_SELL)  {
        double lastLbid = lBid;
        lBid = bid < lBid ? bid : lBid;
        if(lBid < lastLbid) {
            noTrailing ++;
            string msg = "... Trailing down #" + IntegerToString(noTrailing) + tes + abs;
            Print(msg);
            slPrice = lBid + stopLossPrice;
        }

        if(bid < slPrice) return;
        if(!trade.PositionClose(ticket)) {
            string msg = "!!! Error close short position: " + trade.ResultRetcodeDescription();
            Print(msg);
            return;
        }
        return;
    }
    return;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double Engine::calculateVolume() {
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    double pointValue = tickValue * Point() / tickSize;
    double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    double riskValue = balance * (riskPercentage / 100.0);
    double volumeLot = riskValue / stopLossPoint / pointValue;
    volumeLot = NormalizeDouble(volumeLot / lotStep, 0) * lotStep;
    volumeLot = volumeLot > maxVolume ? maxVolume : volumeLot;
    volumeLot = volumeLot < minVolume ? minVolume : volumeLot;
    return volumeLot;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Engine::clearAllOrders() {
    if(totalOrder() == 0) return;
    for(int i = (OrdersTotal() - 1); i >= 0; i--) {
        if(order.SelectByIndex(i)) {
            if(order.Symbol() == Symbol() && order.Magic() == magicNumber) {
                ulong ticket = order.Ticket();
                trade.OrderDelete(ticket);
            }
        }
    }
    return;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Engine::onTrade() {
    int pos = totalPosition();
    if(positionLast != pos) {
        //Print("✏️ Position Changed from " + IntegerToString(positionLast) + " to " +  IntegerToString(pos));
        positionLast = pos;
    }

    if(pos > 0) {
        return;
    }

    int his = totalHistory();
    if(historyLast == his) {
        return;
    }

    //Print("✏️ History Changed from " + IntegerToString(historyLast) + " to " +  IntegerToString(his));
    clearAllOrders();
    historyLast = his;

    if(!HistorySelect(0, TimeCurrent())) return;

    int totalHistory = HistoryDealsTotal();
    for(int i = totalHistory ; i >= 0; i--) {
        ulong ticket = HistoryDealGetTicket(i);
        if(ticket == 0) continue;

        string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
        ulong magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
        if(symbol != Symbol() || magic != magicNumber) continue;

        long typeExit = HistoryDealGetInteger(ticket, DEAL_TYPE);
        long reasonExit = HistoryDealGetInteger(ticket, DEAL_REASON);
        if(!((typeExit == 0 || typeExit == 1) && (reasonExit == 3 || reasonExit == 4 || reasonExit == 5))) continue;

        long orderNo = HistoryDealGetInteger(ticket, DEAL_ORDER);
        double volume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
        double exitPrice = HistoryDealGetDouble(ticket, DEAL_PRICE);
        string tp = DoubleToString(HistoryDealGetDouble(ticket, DEAL_TP), Digits());
        string sl = DoubleToString(HistoryDealGetDouble(ticket, DEAL_SL), Digits());
        double dealProfit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
        string commision = DoubleToString(HistoryDealGetDouble(ticket, DEAL_COMMISSION)*2.0, 2);
        string fee = DoubleToString(HistoryDealGetDouble(ticket, DEAL_FEE), 2);
        string swap = DoubleToString(HistoryDealGetDouble(ticket, DEAL_SWAP), 2);
        string ask = DoubleToString(SymbolInfoDouble(Symbol(), SYMBOL_ASK), Digits());
        string bid = DoubleToString(SymbolInfoDouble(Symbol(), SYMBOL_BID), Digits());
        string spread = IntegerToString(SymbolInfoInteger(Symbol(), SYMBOL_SPREAD));

        if(! HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT) break;
        long positionId = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
        double entryPrice = 0.0;

        // Get Entry Position
        long entryType = 0;
        if (HistorySelectByPosition(positionId)) {
            for(int j = HistoryDealsTotal() -1; j >= 0; j--) {
                ulong ticketEntry = HistoryDealGetTicket(j);
                if(HistoryDealGetInteger(ticketEntry, DEAL_ENTRY) == DEAL_ENTRY_IN) {
                    entryType = HistoryDealGetInteger(ticketEntry, DEAL_TYPE);
                    entryPrice = HistoryDealGetDouble(ticketEntry, DEAL_PRICE);
                    break;
                }
            }
        }

        string direction = entryType == 0 ? "Long" : "Short";
        double deltaPrice = entryType == 0 ?  exitPrice - entryPrice : entryPrice - exitPrice;

        int pipToPoint = (Digits() == 3 || Digits() == 5) ? 10 : 1;
        double deltaPip = deltaPrice/(pipToPoint * Point());

        double ppp = deltaPip != 0 ? dealProfit/deltaPip : 0.0;
        if(dealProfit > 0) {
            consecutiveLoss = 0;
            consecutiveWin ++;
            maxConsecutiveWin = consecutiveWin > maxConsecutiveWin ? consecutiveWin : maxConsecutiveWin;
        } else {
            consecutiveWin = 0;
            consecutiveLoss ++;
            maxConsecutiveLoss = consecutiveLoss > maxConsecutiveLoss ? consecutiveLoss : maxConsecutiveLoss;
        }

        Print("-----------------------------");
        Print("Id: " + IntegerToString(positionId));
        Print("Position: " + direction);
        Print("Entry Price: " + DoubleToString(entryPrice, Digits()) );
        Print("Exit Price: " + DoubleToString(exitPrice, Digits()));
        Print("Margin: " + DoubleToString(deltaPip, Digits()) + " pip");
        Print("Volume: " + DoubleToString(volume, digitVolume) + " lot");
        Print("Profit: " + DoubleToString(dealProfit, Digits()));
        Print("Profit/Pip/Lot: " + DoubleToString(ppp/volume, Digits()));
        Print("Ask/Bid/Spread: " + ask + "/" + bid + "/" + spread);
        Print("Consecutive Win/Loss: " + IntegerToString(consecutiveWin) + "/" + IntegerToString(consecutiveLoss));
        Print("Max Consecutive Win/Loss: " + IntegerToString(maxConsecutiveWin) + "/" + IntegerToString(maxConsecutiveLoss));
        Print("-----------------------------");
        break;
    }
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int Engine::totalPosition() {
    int res = 0;
    for(int i = 0; i < PositionsTotal(); i++) {
        if(position.SelectByIndex(i)) {
            if(position.Symbol() == Symbol() && position.Magic() == magicNumber) {
                res++;
            }
        }
    }
    return res;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int Engine::totalOrder() {
    int res = 0;
    for(int i = 0; i < OrdersTotal(); i++) {
        order.SelectByIndex(i);
        if(order.Symbol() == Symbol() && order.Magic() == magicNumber) {
            res++;
        }
    }
    return res;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int Engine::totalHistory() {
    int res = 0;
    if(HistorySelect(0, TimeCurrent())) {
        int totalHistory = HistoryDealsTotal();
        for(int i = 0; i < totalHistory; i++) {
            ulong ticket = 0;
            if((ticket = HistoryDealGetTicket(i)) > 0) {
                string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
                ulong magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
                if(symbol == Symbol() && magic == magicNumber) {
                    res++;
                }
            }
        }
    }
    return res;
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int Engine::getDigit(double num) {
    int d = 0;
    double p = 1;
    while(MathRound(num * p) / p != num) {
        p = MathPow(10, ++d);
    }
    return d;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int Engine::timeDelay() {
    datetime currentTime = TimeCurrent();
    datetime serverTime = TimeTradeServer();
    return (int)(serverTime - currentTime);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool Engine::isTradingTime() {
    if(beginOrderString == "" && endOrderString == "") {
        return true;
    }

    datetime orderBegin = StringToTime(beginOrderString);
    datetime orderEnd = StringToTime(endOrderString);
    datetime currentTime = TimeTradeServer();
    if(orderEnd > orderBegin) {
        if(currentTime >= orderBegin && currentTime <= orderEnd) {
            return true;
        }
        return false;
    }

    if(orderEnd >= orderBegin) {
        return false;
    }

    // overlap time
    if(currentTime <= orderEnd) {
        return true;
    }

    if(currentTime >= orderBegin) {
        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double Engine::takeProfitMargin() {
    double takeProfitValue = riskReward * stopLossPrice;
    takeProfitValue = NormalizeDouble(takeProfitValue, Digits());
    return takeProfitValue;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool Engine::calculateZigzag() {
    int barCalc = BarsCalculated(zigzagHandle);

    if(pivotNo == 0) {
        return calculateZigzagWithoutPivot(barCalc);
    }

    // Highest
    double highest[];
    ArrayResize(highest, pivotNo + 1);
    double bufferHigh[];
    ArrayResize(bufferHigh, barCalc);
    CopyBuffer(zigzagHandle, 1, 0, barCalc, bufferHigh);
    ArraySetAsSeries(bufferHigh, true);

    int index = 0;
    int iH = 0;
    for(int i = 0; i < barCalc; i++) {
        if(index == (pivotNo + 1)) break;
        if(bufferHigh[i] != EMPTY_VALUE && bufferHigh[i] > 0) {
            highest[index] = bufferHigh[i];
            if(index == 0) {
                iH = i+1;
            }
            index++;
        }
    }

    double lowest[];
    ArrayResize(lowest, pivotNo + 1);
    double bufferLow[];
    ArrayResize(bufferLow, barCalc);
    CopyBuffer(zigzagHandle, 2, 0, barCalc, bufferLow);
    ArraySetAsSeries(bufferLow, true);

    index = 0;
    int iL = 0;
    for(int i = 0; i < barCalc; i++) {
        if(index == (pivotNo + 1)) break;
        if(bufferLow[i] != EMPTY_VALUE && bufferLow[i] > 0) {
            lowest[index] = bufferLow[i];
            if(index == 0) {
                iL = i+1;
            }
            index++;
        }
    }

    isTrendUp = iH < iL;

    int startMax = isTrendUp ? 1 : 0;
    int endMax = isTrendUp ? pivotNo + 1 : pivotNo;
    int highestIndex = ArrayMaximum(highest, startMax, endMax);
    int lowestHighestIndex = ArrayMinimum(highest, startMax, endMax);


    resistance = highest[highestIndex];
    double lowestResistance = highest[lowestHighestIndex];

    resistance = NormalizeDouble(resistance, Digits());

    int startMin = isTrendUp ? 0 : 1;
    int endMin = isTrendUp ? pivotNo : pivotNo + 1;
    int lowestIndex = ArrayMinimum(lowest, startMin, endMin);
    int highestLowestIndex = ArrayMaximum(lowest, startMin, endMin);

    support = lowest[lowestIndex];
    double highestSupport = lowest[highestLowestIndex];
    support = NormalizeDouble(support, Digits());

    return highestSupport < lowestResistance;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool Engine::calculateZigzagWithoutPivot(int barCalc) {
    double bufferHigh[];
    ArrayResize(bufferHigh, barCalc);
    CopyBuffer(zigzagHandle, 1, 0, barCalc, bufferHigh);
    ArraySetAsSeries(bufferHigh, true);

    for(int i = 0; i < barCalc; i++) {
        if(bufferHigh[i] != EMPTY_VALUE && bufferHigh[i] > 0) {
            resistance = bufferHigh[i];
            break;
        }
    }
    double bufferLow[];
    ArrayResize(bufferLow, barCalc);
    CopyBuffer(zigzagHandle, 2, 0, barCalc, bufferLow);
    ArraySetAsSeries(bufferLow, true);

    for(int i = 0; i < barCalc; i++) {
        if(bufferLow[i] != EMPTY_VALUE && bufferLow[i] > 0) {
            support = bufferLow[i];
            break;
        }
    }
    resistance = NormalizeDouble(resistance, Digits());
    support = NormalizeDouble(support, Digits());
    return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool Engine::isNewBar() {
    static datetime lastBar;
    return lastBar != (lastBar = iTime(Symbol(), PERIOD_CURRENT, 0));
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool Engine::isNewM1() {
    static datetime lastBarM1;
    return lastBarM1 != (lastBarM1 = iTime(Symbol(), PERIOD_M1, 0));
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Engine::onTradeTransaction(
    const MqlTradeTransaction& trans,
    const MqlTradeRequest& request,
    const MqlTradeResult& result) {
}


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Engine::~Engine() {
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Engine::onDeinit(const int reason) {
    if(zigzagHandle != INVALID_HANDLE) IndicatorRelease(zigzagHandle);
    Comment("");
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
