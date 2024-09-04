#include <Trade\Trade.mqh>

// 输入参数
input double Lots = 0.05;                      // 每次下单的初始手数
input ENUM_TIMEFRAMES Timeframe = PERIOD_M5;   // 选择的时间周期，默认5分钟
input int SL_Points_Buffer = 50;               // 初始止损缓存基点
input int MinBodyPoints = 50;                  // 最小实体大小（基点）
input int MaxBodyPoints = 300;                 // 最大实体大小（基点）
input int MA1_Period = 144;                    // 移动平均线1周期
input int MA2_Period = 169;                    // 移动平均线2周期
input ENUM_MA_METHOD MA_Method = MODE_SMA;     // 移动平均线方法
input ENUM_APPLIED_PRICE Applied_Price = PRICE_CLOSE; // 移动平均线应用价格
input int StartDelay = 10;                     // 当前K线结束前等待时间（秒）
input int DynamicSL_Buffer = 100;              // 动态止损缓存基点
input bool EnableDynamicSL = true;             // 是否启用动态止损
input int TradeStartHour = 0;                  // 允许交易的开始时间（小时）
input int TradeEndHour = 24;                   // 允许交易的结束时间（小时）

CTrade trade;

// 全局变量
datetime lastCloseTime = 0;                   // 记录最后一次订单关闭的时间
bool isOrderClosedThisBar = false;             // 标记当前K线是否有订单被关闭
double aBarHigh, aBarLow;                      // 记录aBar的高低价
datetime aBarTime;                             // 记录aBar的时间
bool orderOpened = false;                      // 标记是否有订单打开
int signalBarIndex = -1;                       // 信号K线的索引

int maHandle1, maHandle2;                      // 移动平均线句柄

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // 创建移动平均线指标句柄
    maHandle1 = iMA(_Symbol, Timeframe, MA1_Period, 0, MA_Method, Applied_Price);
    maHandle2 = iMA(_Symbol, Timeframe, MA2_Period, 0, MA_Method, Applied_Price);

    // 检查MA句柄是否有效
    if (maHandle1 == INVALID_HANDLE || maHandle2 == INVALID_HANDLE)
    {
        Print("无法创建MA句柄");
        return (INIT_FAILED);
    }

    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // 释放MA指标句柄
    IndicatorRelease(maHandle1);
    IndicatorRelease(maHandle2);
}

//+------------------------------------------------------------------+
//| 检查当前时间是否在允许的交易时间范围内                           |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
    MqlDateTime timeStruct;
    TimeToStruct(TimeCurrent(), timeStruct);  // 获取服务器时间并转换为结构体

    int currentHour = timeStruct.hour;
    return (currentHour >= TradeStartHour && currentHour < TradeEndHour);
}

//+------------------------------------------------------------------+
//| 检查进场信号                                                     |
//+------------------------------------------------------------------+
void CheckEntrySignals()
{
    double ma1Values[4], ma2Values[4]; // 用于存储MA1和MA2的值

    // 获取前4根K线的MA值
    if (CopyBuffer(maHandle1, 0, 0, 4, ma1Values) < 4 || CopyBuffer(maHandle2, 0, 0, 4, ma2Values) < 4)
    {
        Print("无法复制MA数据");
        return;
    }

    // 获取最近的4根已经完成的K线数据
    double high[4], low[4], close[4], open[4]; // 将数组大小设为4，以便访问前4根K线数据

    for (int i = 0; i < 4; i++)
    {
        high[i] = iHigh(_Symbol, Timeframe, i + 1);
        low[i] = iLow(_Symbol, Timeframe, i + 1);
        close[i] = iClose(_Symbol, Timeframe, i + 1);
        open[i] = iOpen(_Symbol, Timeframe, i + 1);
    }

    // 做多条件检查（1根K线形态）
    if (ma1Values[1] < ma2Values[1] &&  // 均线排列条件
        open[1] < ma1Values[1] && close[1] > ma2Values[1] && // K线形态条件
        MathAbs(open[1] - close[1]) >= MinBodyPoints * _Point &&
        MathAbs(open[1] - close[1]) <= MaxBodyPoints * _Point)
    {
        static datetime lastOrderTime = 0;
        if (TimeCurrent() - lastOrderTime > 60 && TimeCurrent() - iTime(_Symbol, Timeframe, 0) > StartDelay)
        {
            lastOrderTime = TimeCurrent();
            double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double stopLossPrice = low[1] - SL_Points_Buffer * _Point;

            if (trade.Buy(Lots, _Symbol, askPrice, stopLossPrice, 0, "Buy Signal"))
            {
                aBarHigh = high[1];
                aBarLow = low[1];
                aBarTime = iTime(_Symbol, Timeframe, 1); // 使用上一个K线时间作为aBar时间
                signalBarIndex = 1; // 记录信号K线的索引
                isOrderClosedThisBar = false;
                orderOpened = true;
            }
        }
    }

    // 做空条件检查（1根K线形态）
    if (ma1Values[1] > ma2Values[1] &&  // 均线排列条件
        open[1] > ma1Values[1] && close[1] < ma2Values[1] && // K线形态条件
        MathAbs(open[1] - close[1]) >= MinBodyPoints * _Point &&
        MathAbs(open[1] - close[1]) <= MaxBodyPoints * _Point)
    {
        static datetime lastOrderTime = 0;
        if (TimeCurrent() - lastOrderTime > 60 && TimeCurrent() - iTime(_Symbol, Timeframe, 0) > StartDelay)
        {
            lastOrderTime = TimeCurrent();
            double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double stopLossPrice = high[1] + SL_Points_Buffer * _Point;

            if (trade.Sell(Lots, _Symbol, bidPrice, stopLossPrice, 0, "Sell Signal"))
            {
                aBarHigh = high[1];
                aBarLow = low[1];
                aBarTime = iTime(_Symbol, Timeframe, 1); // 使用上一个K线时间作为aBar时间
                signalBarIndex = 1; // 记录信号K线的索引
                isOrderClosedThisBar = false;
                orderOpened = true;
            }
        }
    }

    // 添加2根信号K线形态的逻辑...
    // 在这里添加两个K线形态的逻辑检查...
}

//+------------------------------------------------------------------+
//| 动态止损管理                                                     |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
    for (int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket > 0)
        {
            double previousClose = iClose(_Symbol, Timeframe, 1); // 上一根K线的收盘价
            double maxHigh = aBarHigh;                            // 初始化最大高点
            double minLow = aBarLow;                              // 初始化最小低点

            // 查找从aBar到上一根K线之间的最大高点和最小低点
            for (int j = iBarShift(_Symbol, Timeframe, aBarTime); j > 1; j--)
            {
                double high = iHigh(_Symbol, Timeframe, j);
                double low = iLow(_Symbol, Timeframe, j);

                if (high > maxHigh)
                    maxHigh = high;
                if (low < minLow)
                    minLow = low;
            }

            double currentSL = PositionGetDouble(POSITION_SL);
            double newStopLoss;

            // 更新aBar的逻辑应该在这里，即不论是否更新了止损价格，都要更新aBar
            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
                // 做多动态止损逻辑
                if (previousClose > maxHigh)
                {
                    newStopLoss = minLow - DynamicSL_Buffer * _Point;
                    trade.PositionModify(ticket, newStopLoss, 0);
                    // 更新aBar
                    aBarHigh = iHigh(_Symbol, Timeframe, 1);
                    aBarLow = iLow(_Symbol, Timeframe, 1);
                    aBarTime = iTime(_Symbol, Timeframe, 1);
                }
            }
            else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            {
                // 做空动态止损逻辑
                if (previousClose < minLow)
                {
                    newStopLoss = maxHigh + DynamicSL_Buffer * _Point;
                    trade.PositionModify(ticket, newStopLoss, 0);
                    // 更新aBar
                    aBarHigh = iHigh(_Symbol, Timeframe, 1);
                    aBarLow = iLow(_Symbol, Timeframe, 1);
                    aBarTime = iTime(_Symbol, Timeframe, 1);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // 检查是否在允许的交易时间范围内
    if (!IsWithinTradingHours())
    {
        return;
    }

    // 如果有持仓，管理动态止损
    if (PositionsTotal() > 0)
    {
        if (EnableDynamicSL)
        {
            ManageTrailingStop();
        }
        return;
    }

    // 如果没有持仓，嗅探进场信号
    CheckEntrySignals();
}

//+------------------------------------------------------------------+
//| 交易事件处理函数                                                 |
//+------------------------------------------------------------------+
void OnTrade()
{
    // 检查是否有订单关闭
    if (HistorySelect(TimeCurrent() - PeriodSeconds(Timeframe), TimeCurrent()))
    {
        int historyCount = HistoryOrdersTotal(); // 获取历史订单总数

        // 遍历历史订单
        for (int i = historyCount - 1; i >= 0; i--)
        {
            ulong ticket = HistoryOrderGetTicket(i); // 获取历史订单的票号

            if (HistoryOrderSelect(ticket)) // 选择历史订单
            {
                // 获取订单的关闭原因
                ENUM_ORDER_REASON orderReason = (ENUM_ORDER_REASON)HistoryOrderGetInteger(ticket, ORDER_REASON);

                // 检查订单是否因止损或止盈而关闭
                if (orderReason == ORDER_REASON_SL || orderReason == ORDER_REASON_TP)
                {
                    lastCloseTime = iTime(_Symbol, Timeframe, 0); // 更新最后一次订单关闭的时间为当前K线时间
                    isOrderClosedThisBar = true; // 当前K线内订单被止盈或止损
                    Print("Warning: Order ", ticket, " was closed due to ", orderReason == ORDER_REASON_SL ? "stop loss" : "take profit", ".");
                }
            }
        }
    }
}
