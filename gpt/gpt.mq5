#include <Trade\Trade.mqh>

// 输入参数
input double Lots = 0.1;                             // 每次下单的初始手数
input int StopLossPoints = 50;                        // 固定止损点数
input int TakeProfitPoints = 50;                      // 固定止盈点数
input int MA_Fast_Period = 5;                         // 快速移动平均线周期
input int MA_Slow_Period = 20;                        // 慢速移动平均线周期
input ENUM_TIMEFRAMES Timeframe = PERIOD_M5;          // 时间周期，5分钟
input ENUM_MA_METHOD MA_Method = MODE_SMA;            // 移动平均线方法
input ENUM_APPLIED_PRICE Applied_Price = PRICE_CLOSE; // 移动平均线应用价格
input bool EnableTrailingStop = true;                 // 是否启用移动止损
input int TrailingStopPoints = 20;                    // 移动止损点数

CTrade trade;

// 全局变量
int maFastHandle;
int maSlowHandle;
double maFastValues[];
double maSlowValues[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // 创建移动平均线指标句柄
    maFastHandle = iMA(_Symbol, Timeframe, MA_Fast_Period, 0, MA_Method, Applied_Price);
    maSlowHandle = iMA(_Symbol, Timeframe, MA_Slow_Period, 0, MA_Method, Applied_Price);

    // 检查MA句柄是否有效
    if (maFastHandle == INVALID_HANDLE || maSlowHandle == INVALID_HANDLE)
    {
        Print("无法创建MA句柄");
        return INIT_FAILED;
    }

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // 释放MA指标句柄
    IndicatorRelease(maFastHandle);
    IndicatorRelease(maSlowHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    static datetime lastTradeTime = 0;

    // 仅在新的K线开始时进行计算
    if (lastTradeTime == iTime(_Symbol, Timeframe, 0))
        return;

    lastTradeTime = iTime(_Symbol, Timeframe, 0);

    double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    // 获取当前时间周期的MA值
    if (CopyBuffer(maFastHandle, 0, 0, 2, maFastValues) <= 0 || CopyBuffer(maSlowHandle, 0, 0, 2, maSlowValues) <= 0)
    {
        Print("无法复制MA数据");
        return;
    }

    double maFastPrev = maFastValues[1];
    double maFastCurr = maFastValues[0];
    double maSlowPrev = maSlowValues[1];
    double maSlowCurr = maSlowValues[0];

    // 检查多头信号
    if (maFastCurr > maSlowCurr && maFastPrev <= maSlowPrev && iClose(_Symbol, Timeframe, 1) > maFastCurr)
    {
        double stopLoss = bidPrice - StopLossPoints * _Point;
        double takeProfit = bidPrice + TakeProfitPoints * _Point;
        if (PositionsTotal() == 0)
        {
            trade.Buy(Lots, _Symbol, askPrice, stopLoss, takeProfit, "Buy Signal");
        }
    }

    // 检查空头信号
    if (maFastCurr < maSlowCurr && maFastPrev >= maSlowPrev && iClose(_Symbol, Timeframe, 1) < maFastCurr)
    {
        double stopLoss = askPrice + StopLossPoints * _Point;
        double takeProfit = askPrice - TakeProfitPoints * _Point;
        if (PositionsTotal() == 0)
        {
            trade.Sell(Lots, _Symbol, bidPrice, stopLoss, takeProfit, "Sell Signal");
        }
    }

    // 如果有持仓，管理移动止损
    if (EnableTrailingStop && PositionsTotal() > 0)
    {
        ManageTrailingStop();
    }
}

//+------------------------------------------------------------------+
//| 管理移动止损                                                     |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
    for (int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket > 0)
        {
            double price = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            double stopLoss = PositionGetDouble(POSITION_SL);

            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
                double newStopLoss = currentPrice - TrailingStopPoints * _Point;
                if (newStopLoss > stopLoss)
                {
                    trade.PositionModify(ticket, newStopLoss, 0);
                }
            }
            else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            {
                double newStopLoss = currentPrice + TrailingStopPoints * _Point;
                if (newStopLoss < stopLoss)
                {
                    trade.PositionModify(ticket, newStopLoss, 0);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
