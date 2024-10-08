/**

使用MQL5代码实现以下EA策略：
周期：1分钟
进场信号：
    做多：当市场出现开盘价在布林带下轨下方-10个基点以下，收盘价在布林带下轨上方+10基点时以上，信号K线已完成，当前K线运行10秒后进场。
    做空：当市场出现开盘价在布林带上轨上方+10个基点以上，收盘价在布林带上轨下方-10基点时以下，信号K线已完成，当前K线运行10秒后进场。
    其中10基点可调节。

止损策略：
    1. 进场后止损线设置在信号K线的+/-50基点处，进场的同时设置止损线。
    2. 进场K线记作star, 当价格突破star的最高/低加时，移动止损线到当前K线的最高/最低价+/-50基点处，同时当前K线记为star,以此类推，直到止损被打掉。
订单限制：
    1. 单一订单原则，有且只有一个订单，当上一个订单完成后，才能进场下一个订单。




**/
//+------------------------------------------------------------------+
//|                                                    CustomEA.mq5  |
//|                        Copyright 2024, MetaTrader                |
//|                                                                  |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>

// 定义输入参数
input ENUM_TIMEFRAMES TimeFrame = PERIOD_M1;  // 可调节的时间周期
input int BollingerBandsPeriod = 20;          // 布林带周期
input double BollingerBandsDeviation = 2.0;   // 布林带标准差
input int SignalPips = 10;                    // 进场信号基点调整
input int StopLossPips = 50;                  // 初始止损基点调整
input double LotSize = 0.05;                  // 交易手数
input int Slippage = 3;                       // 滑点
input int EntryDelaySeconds = 10;             // 进场延迟秒数

CTrade trade;
datetime lastOrderTime = 0;                   // 记录最后一笔订单的时间
double starHigh, starLow;                     // 记录star K线的最高价和最低价
ulong ticket = 0;                             // 记录当前订单的ticket

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // 检查当前是否有未平仓订单
    if (PositionsTotal() > 0)
    {
        // 获取当前订单信息
        if (PositionSelect(_Symbol))
        {
            double currentStopLoss = PositionGetDouble(POSITION_SL);
            ENUM_POSITION_TYPE positionType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

            // 获取当前K线的最高价和最低价
            double currentHigh = iHigh(_Symbol, TimeFrame, 0);
            double currentLow = iLow(_Symbol, TimeFrame, 0);

            // 多头移动止损
            if (positionType == POSITION_TYPE_BUY)
            {
                if (currentHigh > starHigh) // 如果当前价格突破star最高价
                {
                    double newStopLoss = currentLow - StopLossPips * _Point;
                    trade.PositionModify(PositionGetInteger(POSITION_TICKET), newStopLoss, 0);
                    starHigh = currentHigh; // 更新star K线的最高价
                }
            }
            // 空头移动止损
            else if (positionType == POSITION_TYPE_SELL)
            {
                if (currentLow < starLow) // 如果当前价格突破star最低价
                {
                    double newStopLoss = currentHigh + StopLossPips * _Point;
                    trade.PositionModify(PositionGetInteger(POSITION_TICKET), newStopLoss, 0);
                    starLow = currentLow; // 更新star K线的最低价
                }
            }
        }
        return; // 如果当前有订单，退出函数，不进行新的交易
    }

    // 如果没有未平仓订单，继续检查进场信号

    // 获取布林带指标句柄
    int bollingerHandle = iBands(_Symbol, TimeFrame, BollingerBandsPeriod, 0, BollingerBandsDeviation, PRICE_CLOSE);
   
    double BollingerUpper[], BollingerLower[];

    // 获取布林带上轨和下轨的数据
    if (CopyBuffer(bollingerHandle, 1, 0, 1, BollingerUpper) <= 0 ||  // 上轨数据，索引1
        CopyBuffer(bollingerHandle, 2, 0, 1, BollingerLower) <= 0)   // 下轨数据，索引2
    {
        Print("Failed to copy Bollinger Bands data: ", GetLastError());
        return;
    }

    double openPrice = iOpen(_Symbol, TimeFrame, 1);
    double closePrice = iClose(_Symbol, TimeFrame, 1);
    double highPrice = iHigh(_Symbol, TimeFrame, 1);
    double lowPrice = iLow(_Symbol, TimeFrame, 1);

    datetime currentTime = TimeCurrent();

    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    // 多头进场条件检查
    if (openPrice < (BollingerLower[0] - SignalPips * _Point) && closePrice > (BollingerLower[0] + SignalPips * _Point))
    {
        if (currentTime - iTime(_Symbol, TimeFrame, 0) >= EntryDelaySeconds)
        {
            if (lastOrderTime != iTime(_Symbol, TimeFrame, 1))
            {
                double sl = lowPrice - StopLossPips * _Point;
                double tp = 0;
                if (trade.Buy(LotSize, NULL, ask, sl, tp, "Buy Order"))
                {
                    lastOrderTime = iTime(_Symbol, TimeFrame, 1);
                    starHigh = highPrice; // 设置star K线的最高价
                    starLow = lowPrice;   // 设置star K线的最低价
                    ticket = trade.ResultOrder();
                }
            }
        }
    }

    // 空头进场条件检查
    if (openPrice > (BollingerUpper[0] + SignalPips * _Point) && closePrice < (BollingerUpper[0] - SignalPips * _Point))
    {
        if (currentTime - iTime(_Symbol, TimeFrame, 0) >= EntryDelaySeconds)
        {
            if (lastOrderTime != iTime(_Symbol, TimeFrame, 1))
            {
                double sl = highPrice + StopLossPips * _Point;
                double tp = 0;
                if (trade.Sell(LotSize, NULL, bid, sl, tp, "Sell Order"))
                {
                    lastOrderTime = iTime(_Symbol, TimeFrame, 1);
                    starHigh = highPrice; // 设置star K线的最高价
                    starLow = lowPrice;   // 设置star K线的最低价
                    ticket = trade.ResultOrder();
                }
            }
        }
    }
}
//+------------------------------------------------------------------+
