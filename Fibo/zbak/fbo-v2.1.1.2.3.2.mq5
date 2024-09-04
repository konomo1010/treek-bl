// 最大允许的前一根K线实体大小（基点） 在执行进场操作前，判断一下当前K线的前一根K线的实体大小，如果大于500个基点，放弃这笔交易。 进场确认K线的实体大小可调节。
// 判断当前K线到信号K线直接的所有K线的大小，只要有一根大于500个基点，就放弃这笔交易。 依然是将判断逻辑放到放到 UpdateSignalValidity()下在执行OpenBuyOrder()和OpenSellOrder()前进行检查。
/**
 * 
 * 
存在进场后回踩MA144的情况
    2023.3.31 17:00 
    2024.6.3  10:20 
    2022.5.13  11:25
    2021.4.16 10:15
    2023.6.13 16:25


2021.8.3  15:40  可能异常止损。
2021.5.19 16:00  可能异常进场。


在以下代码的基础上，增加止盈功能，当初始止损大于500个基点时，按照盈亏比1:1来设置止盈。 止盈功能设置开启开关，盈亏比可调节，止盈判断基点可调节。 给出完整代码


在上述代码的基础上，更新以下止盈策略并给出完整代码：
1. 当初始止损大于500个基点时，需要设置止盈。止盈基点可调节。
2. 止盈方案有两种，分别是按盈亏比止盈和固定止盈。可选择。默认选择固定止盈方式。
3. 如果选择盈亏比止盈，默认按照盈亏比1:1来设置止盈。盈亏比可调节。
4. 如果选择固定止盈，那么按照设置的固定止盈基数配置。默认是200个基点。固定止盈基数可调节。


**/
#include <Trade\Trade.mqh>

// 输入参数
input double Lots = 0.05;                             // 每次下单的初始手数
input ENUM_TIMEFRAMES Timeframe = PERIOD_M5;          // 选择的时间周期，默认5分钟
input int SL_Points_Buffer = 50;                      // 动态止损缓存基点
input int MinBodyPoints = 50;                         // 最小实体大小（基点）
input int MaxBodyPoints = 300;                        // 最大实体大小（基点）
input int MA1_Period = 144;                           // 移动平均线1周期
input int MA2_Period = 169;                           // 移动平均线2周期
input ENUM_MA_METHOD MA_Method = MODE_SMA;            // 移动平均线方法
input ENUM_APPLIED_PRICE Applied_Price = PRICE_CLOSE; // 移动平均线应用价格
input int StartDelay = 10;                            // 当前K线结束前等待时间（秒）
input int DynamicSL_Buffer = 100;                     // 动态止损缓存基点
input bool EnableDynamicSL = true;                    // 是否启用动态止损
input int TradeStartHour = 0;                         // 允许交易的开始时间（小时）
input int TradeEndHour = 24;                          // 允许交易的结束时间（小时）
input string AllowedMonths = "2,3,4,5,6,7,8,9,10,11"; // 允许交易的月份（用逗号分隔）
input int MaxCandleBodySizePoints = 500;              // 最大允许的K线实体大小（基点）
input bool EnableTakeProfit = true;                   // 是否启用动态止盈功能
input double RiskRewardRatio = 1.0;                   // 盈亏比
input int TakeProfitThresholdPoints = 500;            // 动态止盈判断基点阈值
input bool EnableFixedSL = false;                     // 是否启用固定止损
input bool EnableFixedTP = false;                     // 是否启用固定止盈
input int FixedSLPoints = 200;                        // 固定止损点数（基点）
input int FixedTPPoints = 200;                        // 固定止盈点数（基点）

CTrade trade;

// 全局变量
datetime lastCloseTime = 0;        // 记录最后一次订单关闭的时间
bool isOrderClosedThisBar = false; // 标记当前K线是否有订单被关闭
double aBarHigh, aBarLow;          // 记录aBar的高低价
datetime aBarTime;                 // 记录aBar的时间
bool orderOpened = false;          // 标记是否有订单打开
int signalBarIndex = -1;           // 信号K线的索引

// 记录止损被打掉的状态
bool stopLossHitThisBar = false;

int maHandle1, maHandle2; // 移动平均线句柄
int maHandleMA144;        // MA144的句柄

// 用于跟踪信号K线后的最大值
double maxHigh, minLow;

// 信号K线的最高和最低价格
double signalHigh, signalLow;

// 标记信号是否有效
bool isSignalValid = false;
bool longSignalConfirmed = false;
bool shortSignalConfirmed = false;

// 记录进场时间
datetime entryTime = 0;

// 动态止损管理用到的高低价
double trailingMaxHigh, trailingMinLow;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // 创建移动平均线指标句柄
    maHandle1 = iMA(_Symbol, Timeframe, MA1_Period, 0, MA_Method, Applied_Price);
    maHandle2 = iMA(_Symbol, Timeframe, MA2_Period, 0, MA_Method, Applied_Price);
    maHandleMA144 = iMA(_Symbol, Timeframe, 144, 0, MA_Method, Applied_Price);

    // 检查MA句柄是否有效
    if (maHandle1 == INVALID_HANDLE || maHandle2 == INVALID_HANDLE || maHandleMA144 == INVALID_HANDLE)
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
    IndicatorRelease(maHandleMA144);
}

//+------------------------------------------------------------------+
//| 检查当前时间是否在允许的交易时间范围内                           |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
    MqlDateTime timeStruct;
    TimeToStruct(TimeCurrent(), timeStruct); // 获取服务器时间并转换为结构体

    int currentHour = timeStruct.hour;
    return (currentHour >= TradeStartHour && currentHour < TradeEndHour);
}

//+------------------------------------------------------------------+
//| 检查当前月份是否在允许的交易月份范围内                           |
//+------------------------------------------------------------------+
bool IsMonthAllowed(int month)
{
    string months[];                      // 创建一个字符串数组来存储解析后的月份
    StringSplit(AllowedMonths, ',', months);  // 使用逗号分隔符解析输入的字符串

    for (int i = 0; i < ArraySize(months); i++)
    {
        if (StringToInteger(months[i]) == month)
        {
            return true;  // 如果当前月份在允许的月份列表中，则返回true
        }
    }

    return false;  // 如果不在列表中，返回false
}

//+------------------------------------------------------------------+
//| 检查进场信号                                                     |
//+------------------------------------------------------------------+
void CheckEntrySignals()
{
    // 如果当前有持仓，或本K线止损被打掉，不允许再开仓
    if (PositionsTotal() > 0 || stopLossHitThisBar)
    {
        return;
    }

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

    // 检查多头和空头信号
    if (!longSignalConfirmed && CheckLongEntrySignal(high, low, close, open, ma1Values, ma2Values))
    {
        // 初始化最大最小值
        maxHigh = MathMax(high[1], high[2]); // 记录信号K线后的最大高点
        trailingMaxHigh = maxHigh;           // 初始化动态止损用的最大高点
        trailingMinLow = low[1];             // 初始化动态止损用的最小低点
        longSignalConfirmed = true;
        isSignalValid = true;
        Print("多头信号已确认");

        // 计算信号K线的索引
        signalBarIndex = iBarShift(_Symbol, Timeframe, iTime(_Symbol, Timeframe, 2));
    }
    else if (!shortSignalConfirmed && CheckShortEntrySignal(high, low, close, open, ma1Values, ma2Values))
    {
        // 初始化最大最小值
        minLow = MathMin(low[1], low[2]); // 记录信号K线后的最小低点
        trailingMinLow = minLow;          // 初始化动态止损用的最小低点
        trailingMaxHigh = high[1];        // 初始化动态止损用的最大高点
        shortSignalConfirmed = true;
        isSignalValid = true;
        Print("空头信号已确认");

        // 计算信号K线的索引
        signalBarIndex = iBarShift(_Symbol, Timeframe, iTime(_Symbol, Timeframe, 2));
    }
}

//+------------------------------------------------------------------+
//| 检查多头进场信号                                                 |
//+------------------------------------------------------------------+
bool CheckLongEntrySignal(double &high[], double &low[], double &close[], double &open[], double &ma1Values[], double &ma2Values[])
{
    // 检查单根信号K线形态 - 做多
    if (ma1Values[1] < ma2Values[1] &&                       // 均线排列条件
        open[1] < ma1Values[1] && close[1] > ma2Values[1] && // K线形态条件
        MathAbs(open[1] - close[1]) >= MinBodyPoints * _Point &&
        MathAbs(open[1] - close[1]) <= MaxBodyPoints * _Point)
    {
        // 记录单根信号K线的最高价和最低价
        signalHigh = high[1];
        signalLow = low[1];

        // 计算信号K线的索引
        signalBarIndex = iBarShift(_Symbol, Timeframe, iTime(_Symbol, Timeframe, 1));
        return true;
    }

    // 检查两根信号K线形态 - 做多
    if (ma1Values[2] < ma2Values[2] && ma1Values[1] < ma2Values[1] &&                                                     // 均线排列条件
        open[2] < ma1Values[2] && close[1] > ma2Values[1] &&                                                              // 第一根信号K线和第二根信号K线形态条件
        high[2] < close[1] && low[1] > open[2] &&                                                                         // 多头排列条件
        MathAbs(open[2] - close[2]) >= MinBodyPoints * _Point && MathAbs(open[2] - close[2]) <= MaxBodyPoints * _Point && // 实体大小
        MathAbs(open[1] - close[1]) >= MinBodyPoints * _Point && MathAbs(open[1] - close[1]) <= MaxBodyPoints * _Point)   // 实体大小
    {
        // 记录两根信号K线的最高价和最低价
        signalHigh = MathMax(high[1], high[2]);
        signalLow = MathMin(low[1], low[2]);

        // 计算信号K线的索引
        signalBarIndex = iBarShift(_Symbol, Timeframe, iTime(_Symbol, Timeframe, 2));
        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| 检查空头进场信号                                                 |
//+------------------------------------------------------------------+
bool CheckShortEntrySignal(double &high[], double &low[], double &close[], double &open[], double &ma1Values[], double &ma2Values[])
{
    // 检查单根信号K线形态 - 做空
    if (ma1Values[1] > ma2Values[1] &&                       // 均线排列条件
        open[1] > ma1Values[1] && close[1] < ma2Values[1] && // K线形态条件
        MathAbs(open[1] - close[1]) >= MinBodyPoints * _Point &&
        MathAbs(open[1] - close[1]) <= MaxBodyPoints * _Point)
    {
        // 记录单根信号K线的最高价和最低价
        signalHigh = high[1];
        signalLow = low[1];

        // 计算信号K线的索引
        signalBarIndex = iBarShift(_Symbol, Timeframe, iTime(_Symbol, Timeframe, 1));
        return true;
    }

    // 检查两根信号K线形态 - 做空
    if (ma1Values[2] > ma2Values[2] && ma1Values[1] > ma2Values[1] &&                                                     // 均线排列条件
        open[2] > ma1Values[2] && close[1] < ma2Values[1] &&                                                              // 第一根信号K线和第二根信号K线形态条件
        low[2] > close[1] && high[1] < open[2] &&                                                                         // 空头排列条件
        MathAbs(open[2] - close[2]) >= MinBodyPoints * _Point && MathAbs(open[2] - close[2]) <= MaxBodyPoints * _Point && // 实体大小
        MathAbs(open[1] - close[1]) >= MinBodyPoints * _Point && MathAbs(open[1] - close[1]) <= MaxBodyPoints * _Point)   // 实体大小
    {
        // 记录两根信号K线的最高价和最低价
        signalHigh = MathMax(high[1], high[2]);
        signalLow = MathMin(low[1], low[2]);

        // 计算信号K线的索引
        signalBarIndex = iBarShift(_Symbol, Timeframe, iTime(_Symbol, Timeframe, 2));
        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| 更新信号的有效性                                                 |
//+------------------------------------------------------------------+
void UpdateSignalValidity()
{
    if (!isSignalValid)
        return; // 如果信号已经无效，直接返回

    // 获取当前K线的上一根已完成K线的时间
    datetime lastCompletedBarTime = iTime(_Symbol, Timeframe, 1);
    int lastCompletedShift = iBarShift(_Symbol, Timeframe, lastCompletedBarTime);
    double maValue[1];

    if (CopyBuffer(maHandleMA144, 0, lastCompletedShift, 1, maValue) <= 0)
    {
        Print("无法获取MA144的值");
        isSignalValid = false;
        return;
    }

    double lastCompletedClose = iClose(_Symbol, Timeframe, lastCompletedShift);
    double lastCompletedHigh = iHigh(_Symbol, Timeframe, lastCompletedShift);
    double lastCompletedLow = iLow(_Symbol, Timeframe, lastCompletedShift);
    double lastCompletedOpen = iOpen(_Symbol, Timeframe, lastCompletedShift);

    // 检查多头信号的有效性
    if (longSignalConfirmed)
    {
        if (lastCompletedClose < maValue[0])
        {
            ResetSignalState(); // 重置信号状态
            Print("多头信号无效: 上一根已完成K线的收盘价低于MA144");
        }
        else if (lastCompletedClose > maxHigh)
        {
            // 检查从信号K线到当前K线的所有K线的实体大小
            bool largeCandleFound = false;
            for (int i = lastCompletedShift; i >= signalBarIndex; i--)
            {
                double openPrice = iOpen(_Symbol, Timeframe, i);
                double closePrice = iClose(_Symbol, Timeframe, i);
                double candleBodySize = MathAbs(openPrice - closePrice) / _Point;

                if (candleBodySize > MaxCandleBodySizePoints)
                {
                    largeCandleFound = true;
                    break;
                }
            }

            if (!largeCandleFound)
            {
                // 多头信号确认，等待进场
                Print("多头信号确认，准备进场");
                Sleep(StartDelay * 1000); // 等待设定的延迟时间
                OpenBuyOrder(signalHigh, signalLow);
            }
            else
            {
                Print("从信号K线到当前K线之间存在实体大小超过限制的K线，放弃多头交易。");
                ResetSignalState(); // 信号无效，重置状态
            }
        }

        // 更新maxHigh值
        if (lastCompletedHigh > maxHigh)
        {
            maxHigh = lastCompletedHigh;
        }
    }
    // 检查空头信号的有效性
    else if (shortSignalConfirmed)
    {
        if (lastCompletedClose > maValue[0])
        {
            ResetSignalState(); // 重置信号状态
            Print("空头信号无效: 上一根已完成K线的收盘价高于MA144");
        }
        else if (lastCompletedClose < minLow)
        {
            // 检查从信号K线到当前K线的所有K线的实体大小
            bool largeCandleFound = false;
            for (int i = lastCompletedShift; i >= signalBarIndex; i--)
            {
                double openPrice = iOpen(_Symbol, Timeframe, i);
                double closePrice = iClose(_Symbol, Timeframe, i);
                double candleBodySize = MathAbs(openPrice - closePrice) / _Point;

                if (candleBodySize > MaxCandleBodySizePoints)
                {
                    largeCandleFound = true;
                    break;
                }
            }

            if (!largeCandleFound)
            {
                // 空头信号确认，等待进场
                Print("空头信号确认，准备进场");
                Sleep(StartDelay * 1000); // 等待设定的延迟时间
                OpenSellOrder(signalHigh, signalLow);
            }
            else
            {
                Print("从信号K线到当前K线之间存在实体大小超过限制的K线，放弃空头交易。");
                ResetSignalState(); // 信号无效，重置状态
            }
        }

        // 更新minLow值
        if (lastCompletedLow < minLow)
        {
            minLow = lastCompletedLow;
        }
    }
}

//+------------------------------------------------------------------+
//| 开多单操作                                                       |
//+------------------------------------------------------------------+
void OpenBuyOrder(double high, double low)
{
    static datetime lastOrderTime = 0;
    if (TimeCurrent() - lastOrderTime > 60)
    {
        lastOrderTime = TimeCurrent();
        double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double stopLossPrice = 0;
        double takeProfitPrice = 0;

        if (EnableFixedSL)
        {
            // 使用固定止损
            stopLossPrice = askPrice - FixedSLPoints * _Point;
        }
        else
        {
            // 动态止损逻辑
            stopLossPrice = low - SL_Points_Buffer * _Point;
        }

        if (EnableFixedTP)
        {
            // 使用固定止盈
            takeProfitPrice = askPrice + FixedTPPoints * _Point;
        }
        else if (EnableTakeProfit && SL_Points_Buffer > TakeProfitThresholdPoints)
        {
            // 动态止盈逻辑
            takeProfitPrice = askPrice + (askPrice - stopLossPrice) * RiskRewardRatio;
        }

        if (trade.Buy(Lots, _Symbol, askPrice, stopLossPrice, takeProfitPrice, "Buy Signal"))
        {
            aBarHigh = iHigh(_Symbol, Timeframe, 1); // 将aBar设置为当前K线
            aBarLow = iLow(_Symbol, Timeframe, 1);   // 将aBar设置为当前K线
            aBarTime = iTime(_Symbol, Timeframe, 1); // 使用当前K线时间作为aBar时间
            isOrderClosedThisBar = false;
            orderOpened = true;
            entryTime = TimeCurrent(); // 记录进场时间

            // 设置动态止损用的最大/最小值
            trailingMaxHigh = aBarHigh; // 初始化为进场K线的最高价
            trailingMinLow = low;       // 信号K线的最低价

            Print("做多订单已下单。");
            ResetSignalState(); // 重置信号状态
        }
    }
}

//+------------------------------------------------------------------+
//| 开空单操作                                                       |
//+------------------------------------------------------------------+
void OpenSellOrder(double high, double low)
{
    static datetime lastOrderTime = 0;
    if (TimeCurrent() - lastOrderTime > 60)
    {
        lastOrderTime = TimeCurrent();
        double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double stopLossPrice = 0;
        double takeProfitPrice = 0;

        if (EnableFixedSL)
        {
            // 使用固定止损
            stopLossPrice = bidPrice + FixedSLPoints * _Point;
        }
        else
        {
            // 动态止损逻辑
            stopLossPrice = high + SL_Points_Buffer * _Point;
        }

        if (EnableFixedTP)
        {
            // 使用固定止盈
            takeProfitPrice = bidPrice - FixedTPPoints * _Point;
        }
        else if (EnableTakeProfit && SL_Points_Buffer > TakeProfitThresholdPoints)
        {
            // 动态止盈逻辑
            takeProfitPrice = bidPrice - (stopLossPrice - bidPrice) * RiskRewardRatio;
        }

        if (trade.Sell(Lots, _Symbol, bidPrice, stopLossPrice, takeProfitPrice, "Sell Signal"))
        {
            aBarHigh = iHigh(_Symbol, Timeframe, 1); // 将aBar设置为当前K线
            aBarLow = iLow(_Symbol, Timeframe, 1);   // 将aBar设置为当前K线
            aBarTime = iTime(_Symbol, Timeframe, 1); // 使用当前K线时间作为aBar时间
            isOrderClosedThisBar = false;
            orderOpened = true;
            entryTime = TimeCurrent(); // 记录进场时间

            // 设置动态止损用的最大/最小值
            trailingMaxHigh = high;   // 信号K线的最高价
            trailingMinLow = aBarLow; // 初始化为进场K线的最低价

            Print("做空订单已下单。");
            ResetSignalState(); // 重置信号状态
        }
    }
}

//+------------------------------------------------------------------+
//| 管理动态止损                                                     |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
    for (int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket > 0)
        {
            double previousClose = iClose(_Symbol, Timeframe, 1); // 上一根K线的收盘价
            double maxHighLocal = aBarHigh;                       // 初始化最大高点
            double minLowLocal = aBarLow;                         // 初始化最小低点

            // 查找从aBar到上一根K线之间的最大高点和最小低点
            for (int j = iBarShift(_Symbol, Timeframe, aBarTime); j > 1; j--)
            {
                double high = iHigh(_Symbol, Timeframe, j);
                double low = iLow(_Symbol, Timeframe, j);

                if (high > maxHighLocal)
                    maxHighLocal = high;
                if (low < minLowLocal)
                    minLowLocal = low;
            }

            double currentSL = PositionGetDouble(POSITION_SL);
            double newStopLoss;

            // 更新aBar的逻辑应该在这里，即不论是否更新了止损价格，都要更新aBar
            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
                // 做多动态止损逻辑
                if (previousClose > maxHighLocal)
                {
                    newStopLoss = minLowLocal - DynamicSL_Buffer * _Point;
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
                if (previousClose < minLowLocal)
                {
                    newStopLoss = maxHighLocal + DynamicSL_Buffer * _Point;
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
//| 重置信号状态                                                     |
//+------------------------------------------------------------------+
void ResetSignalState()
{
    isSignalValid = false;
    longSignalConfirmed = false;
    shortSignalConfirmed = false;
    maxHigh = 0;
    minLow = 0;
    signalHigh = 0;
    signalLow = 0;
    entryTime = 0;
    stopLossHitThisBar = false;  // 重置止损状态
    Print("信号状态已重置，等待新信号...");
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
                    isOrderClosedThisBar = true;                  // 当前K线内订单被止盈或止损
                    stopLossHitThisBar = true;  // 标记止损被打掉
                    Print("注意: 订单 ", ticket, " 已经被关闭 ", orderReason == ORDER_REASON_SL ? "止损" : "take profit", ".");
                    trailingMaxHigh = 0;
                    trailingMinLow = 0;
                    ResetSignalState(); // 重置信号状态
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

    // 获取当前服务器时间的月份
    MqlDateTime timeStruct;
    TimeToStruct(TimeCurrent(), timeStruct);
    int currentMonth = timeStruct.mon;

    // 检查是否在允许的交易月份内
    if (!IsMonthAllowed(currentMonth))
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

    // 更新信号的有效性
    UpdateSignalValidity();

    // 如果没有持仓，嗅探进场信号
    CheckEntrySignals();
}

//+------------------------------------------------------------------+
