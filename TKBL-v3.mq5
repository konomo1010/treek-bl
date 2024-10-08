// 在下面代码基础上，实现以下功能并给出完整代码：
// 1. 从进场后的第1根K线算起，到第5根K线结束(一共隔了5根K线)还未触发移动止损的话，那么当前K线运行10秒后直接平仓。
// 2. 相隔的K线数量可调节。
// 3. 10秒由StartDelay当前K线开盘后延迟秒数调节。




// 添加平仓条件：

// 如果从进场后的第1根K线开始计算，直到第5根K线结束（相隔5根K线）仍未触发移动止损，那么在当前K线运行10秒（或通过StartDelay设置的秒数）后，强制平仓。
// 添加一个新的输入参数BarsToWait来调节相隔的K线数量（默认5根）。
// 动态检查和刷新布林带值：

// 确保每次在OnTick中检查布林带值时，都动态获取第3根K线的布林带上轨和下轨。


#include <Trade\Trade.mqh>

// 输入参数
input double Lots = 0.05;                      // 每次下单的初始手数
input ENUM_TIMEFRAMES Timeframe = PERIOD_M5;   // 选择的时间周期，默认5分钟
input int SL_Points1 = 50;                     // 初始止损点数（基点）
input int SL_Points2 = 30;                     // 动态调整止损点数（基点）
input int StartDelay = 10;                     // 当前K线开盘后延迟秒数
input int BarsToWait = 5;                      // 相隔的K线数量，默认5根
input int BuyPriceRangeMin = 300;              // 做多时收盘价与最低价的最小基点范围
input int BuyPriceRangeMax = 700;              // 做多时收盘价与最低价的最大基点范围
input int SellPriceRangeMin = 300;             // 做空时收盘价与最高价的最小基点范围
input int SellPriceRangeMax = 700;             // 做空时收盘价与最高价的最大基点范围
input int TradeStartHour = 0;                 // 允许交易的开始时间（小时）
input int TradeEndHour = 24;                   // 允许交易的结束时间（小时）
input double DrawdownPercentage = 5.0;        // 资金回撤百分比，默认10%
input double DrawdownLots = 0.05;              // 资金回撤时的手数调整，默认初始手数
input double MinBalanceForDrawdown = 500.0;    // 回撤策略生效的最低资金水平
input int BollingerPeriod = 10;                // 布林带周期，默认20
input double BollingerDeviation = 1.5;         // 布林带标准差倍数，默认2.0
input int BufferPoints = 10;                   // 缓存基点，用于布林带条件的判断
input int MinBodyPoints = 30;                  // 最小实体基点（新增参数）

CTrade trade;

double starHigh = 0;
double starLow = 0;
double starClose = 0;
double starOpen = 0;
bool starSet = true;
bool firstCondition = true; // 第一次止损条件标识
datetime OrderOpenTime = 0; // 记录开仓开盘时间
double thirdCandleLow = 0;  // 记录第3根K线的最低价
double thirdCandleHigh = 0; // 记录第3根K线的最高价
bool loss = false;          // 止损是否被打掉
datetime lossOpenTime = 0;  // 记录止损被打掉所处K线开仓时间
bool canOpenNewOrder = true; // 是否可以开新单
bool isOrderClosedThisBar = false; // 标记当前K线是否有订单被关闭
int barsSinceEntry = 0; // 从进场后的K线数目
datetime entryTime = 0; // 记录进场时间

// 新增变量
double initialAccountBalance;  // 初始账户资金
double maxAccountBalance;      // 历史最大账户资金
double currentLots;            // 当前下单手数
double drawdownThreshold;      // 回撤触发阈值
int bollingerHandle;           // 布林带指标句柄

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    initialAccountBalance = AccountInfoDouble(ACCOUNT_BALANCE); // 获取初始账户资金
    maxAccountBalance = initialAccountBalance; // 初始化最大账户资金
    currentLots = Lots;  // 设置初始手数
    drawdownThreshold = DrawdownPercentage / 100.0; // 设置资金回撤百分比阈值

    // 创建布林带指标句柄
    bollingerHandle = iBands(_Symbol, Timeframe, BollingerPeriod, BollingerDeviation, 0, PRICE_CLOSE);

    // 检查布林带句柄是否有效
    if (bollingerHandle == INVALID_HANDLE)
    {
        Print("Error creating Bollinger Bands indicator handle");
        return (INIT_FAILED);
    }

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // 释放布林带指标句柄
    IndicatorRelease(bollingerHandle);
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
//| 根据当前资金计算手数                                              |
//+------------------------------------------------------------------+
double CalculateLots(double balance, double initialBalance, double initialLots)
{
    // 根据资金倍数动态调整手数
    double factor = 2.5;
    double lots = initialLots;

    while (balance >= initialBalance * factor)
    {
        lots *= 2; // 每达到2.5倍的资金，手数加倍
        factor *= 2.5; // 下一次倍增的目标
    }

    return lots;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // 更新账户资金和调整手数
    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);

    // 动态刷新历史最大资金值
    if (currentBalance > maxAccountBalance)
    {
        maxAccountBalance = currentBalance;
        // 资金恢复到历史最大值，按资金水平调整手数
        double newLots = CalculateLots(currentBalance, initialAccountBalance, Lots);
        if (newLots != currentLots)
        {
            currentLots = newLots;
            Print("资金恢复到历史最大值，调整手数为: ", currentLots);
        }
    }
    else
    {
        // 检查是否低于回撤策略控制的最低资金水平
        if (currentBalance >= MinBalanceForDrawdown)
        {
            // 如果资金回撤超过设定的百分比
            if (currentBalance <= maxAccountBalance * (1 - drawdownThreshold))
            {
                if (currentLots != DrawdownLots) // 只有当前手数不等于回撤手数时才调整
                {
                    currentLots = DrawdownLots; // 调整手数为设定的回撤手数
                    Print("资金回撤达到设定值，手数调整为: ", currentLots);
                }
                // 动态更新历史最大资金为当前资金，防止多次减少手数
                maxAccountBalance = currentBalance; 
            }
        }
        else
        {
            // 如果资金低于最低阈值，则不受回撤策略影响，使用初始手数
            if (currentLots != Lots)
            {
                currentLots = Lots;
                Print("资金低于回撤策略控制的最低资金水平，手数恢复为初始值: ", currentLots);
            }
        }
    }

    // 准备获取布林带上下边缘的值
    double bollingerUpper[], bollingerLower[];

    // 复制布林带上轨和下轨数据
    if (CopyBuffer(bollingerHandle, 1, 2, 1, bollingerUpper) <= 0 || CopyBuffer(bollingerHandle, 2, 2, 1, bollingerLower) <= 0)
    {
        Print("Error copying Bollinger Bands data");
        return;
    }

    // 获取第三根K线（信号K线的最后一根）的收盘价
    double thirdCandleClose = iClose(_Symbol, Timeframe, 2);

    // 计算缓存基点
    double bufferPips = BufferPoints * _Point;

    // 判断是否满足布林带条件
    bool bollingerConditionForBuy = (thirdCandleClose > (bollingerUpper[0] + bufferPips)); // 做多条件
    bool bollingerConditionForSell = (thirdCandleClose < (bollingerLower[0] - bufferPips)); // 做空条件

    // 获取当前K线时间
    datetime currentBarTime = iTime(_Symbol, Timeframe, 0);

    // 如果进入了新的一根K线，重置标记
    if (OrderOpenTime != currentBarTime)
    {
        isOrderClosedThisBar = false;
    }

    // 检查是否存在未平仓订单
    if (PositionsTotal() > 0)
    {
        // 如果存在订单，即使超出交易时间，也需要管理持仓
        if (OrderOpenTime != currentBarTime && !starSet)
        {
            starLow = iLow(_Symbol, Timeframe, 1);
            starHigh = iHigh(_Symbol, Timeframe, 1);
            starClose = iClose(_Symbol, Timeframe, 1);
            starOpen = iOpen(_Symbol, Timeframe, 1);
            starSet = true;
            Print("OrderOpenTime: ", OrderOpenTime, " now: ", currentBarTime);
            Print(">>>> starLow: ", iLow(_Symbol, Timeframe, 1), " , starHigh: ", iHigh(_Symbol, Timeframe, 1));
        }

        // 动态调整止损逻辑
        double currentClose = iClose(_Symbol, Timeframe, 1);
        double currentLow = iLow(_Symbol, Timeframe, 1);
        double currentHigh = iHigh(_Symbol, Timeframe, 1);

        Print("=============> ", starLow, " , ", thirdCandleLow);
        Print("=============> ", starHigh, " , ", thirdCandleHigh);

        // 首次止损移动条件（做空）
        if (firstCondition && currentClose < MathMin(starLow, thirdCandleLow))
        {
            firstCondition = false;  // 第一次止损条件不再适用
            starHigh = currentHigh;
            starLow = currentLow;
            ulong ticket = PositionGetTicket(0);
            if (ticket > 0)
            {
                trade.PositionModify(ticket, starHigh + SL_Points2 * _Point, 0);
            }
        }
        // 后续止损移动条件（做空）
        else if (!firstCondition && currentClose < starLow)
        {
            starHigh = currentHigh;
            Print("!!!!!!!!!!!!!!!!!!> starHigh ", starHigh);
            starLow = currentLow;
            ulong ticket = PositionGetTicket(0);
            if (ticket > 0)
            {
                trade.PositionModify(ticket, starHigh + SL_Points2 * _Point, 0);
            }
        }
        // 首次止损移动条件（做多）
        else if (firstCondition && currentClose > MathMax(starHigh, thirdCandleHigh))
        {
            firstCondition = false;  // 第一次止损条件不再适用
            starHigh = currentHigh;
            starLow = currentLow;
            ulong ticket = PositionGetTicket(0);
            if (ticket > 0)
            {
                trade.PositionModify(ticket, starLow - SL_Points2 * _Point, 0);
            }
        }
        // 后续止损移动条件（做多）
        else if (!firstCondition && currentClose > starHigh)
        {
            starLow = currentLow;
            Print("!!!!!!!!!!!!!!!!!!> starLow ", starLow);
            starHigh = currentHigh;
            ulong ticket = PositionGetTicket(0);
            if (ticket > 0)
            {
                trade.PositionModify(ticket, starLow - SL_Points2 * _Point, 0);
            }
        }

        // 检查是否达到平仓条件
        barsSinceEntry = (currentBarTime - entryTime) / PeriodSeconds();
        if (barsSinceEntry >= BarsToWait)
        {
            static datetime lastCheckTime = 0;
            if (TimeCurrent() - lastCheckTime >= StartDelay)
            {
                lastCheckTime = TimeCurrent();
                // 平仓
                if (PositionsTotal() > 0)
                {
                    ulong ticket = PositionGetTicket(0);
                    if (ticket > 0)
                    {
                        trade.PositionClose(ticket);
                        Print("未触发移动止损条件，达到最大K线数，平仓");
                        canOpenNewOrder = true; // 允许开新单
                        barsSinceEntry = 0; // 重置计数器
                        entryTime = 0; // 重置进场时间
                    }
                }
            }
        }

        return; // 退出OnTick，不进行新的开仓操作
    }

    // 检查是否在允许的交易时间范围内，如果不在范围内，则不执行任何开仓操作
    if (!IsWithinTradingHours())
    {
        return;
    }

    // 如果已经有订单在当前K线被关闭，则不再开新单
    if (isOrderClosedThisBar)
    {
        return;
    }

    if (loss)
    {
        if (lossOpenTime == currentBarTime)
        {
            Print("》》》》》 未走完 ", lossOpenTime, "  ", currentBarTime);
            return;
        }
        Print("》》》》》 已走完");
        loss = false;
        canOpenNewOrder = true; // 恢复开新单状态
    }

    // 确保至少有4根K线（1根当前K线 + 3根已完成K线）
    if (iBars(_Symbol, Timeframe) < 4)
        return;  // 如果不足4根K线数据，退出

    // 获取最近的4根已经完成的K线数据（注意这里用的是 [1], [2], [3], [4]）
    double high[4], low[4], close[4], open[4]; // 将数组大小设为4，以便访问前4根K线数据

    for (int i = 0; i < 4; i++)
    {
        high[i] = iHigh(_Symbol, Timeframe, i + 1);
        low[i] = iLow(_Symbol, Timeframe, i + 1);
        close[i] = iClose(_Symbol, Timeframe, i + 1);
        open[i] = iOpen(_Symbol, Timeframe, i + 1);
    }

    // 检查每根K线的实体是否大于最小基点要求
    bool isBodyLargeEnough = true;
    for (int i = 0; i < 3; i++)
    {
        double bodySize = MathAbs(open[i] - close[i]) / _Point; // 实体大小（基点）
        if (bodySize < MinBodyPoints)
        {
            isBodyLargeEnough = false;
            break;
        }
    }

    // 如果信号K线的实体大小不足，则不继续进行交易信号判断
    if (!isBodyLargeEnough)
    {
        return;
    }

    // 做空条件检查
    bool sellCondition = (open[2] > open[1] && open[1] > open[0] &&  // 开盘价逐步降低
                          close[2] > close[1] && close[1] > close[0]  // 收盘价逐步降低
                          && bollingerConditionForSell); // 需满足布林带条件

    // 做多条件检查
    bool buyCondition = (open[2] < open[1] && open[1] < open[0] &&    // 开盘价逐步升高
                         close[2] < close[1] && close[1] < close[0]   // 收盘价逐步升高
                         && bollingerConditionForBuy); // 需满足布林带条件

    if (sellCondition)
    {
        double body3 = MathAbs(open[0] - close[0]);
        double lowerShadow3 = MathAbs(low[0] - MathMin(open[0], close[0]));
        double highestHigh = MathMax(high[0], MathMax(high[1], high[2]));
        double priceRange = highestHigh - close[0];

        if (body3 > lowerShadow3 && low[0] < low[1] && low[0] < low[2] &&
            priceRange >= SellPriceRangeMin * _Point && priceRange <= SellPriceRangeMax * _Point)
        {
            // 记录第3根K线的最低价
            thirdCandleLow = low[0];

            // 确保在当前K线开盘后10秒执行
            static datetime lastOrderTime = 0;
            if (canOpenNewOrder && TimeCurrent() - lastOrderTime > 60 && TimeCurrent() - currentBarTime > StartDelay)
            {
                lastOrderTime = TimeCurrent();
                OrderOpenTime = currentBarTime;
                entryTime = currentBarTime; // 设置进场时间
                barsSinceEntry = 0; // 重置K线计数器
                Print("获取下单开盘时间：", OrderOpenTime, "  ", lossOpenTime);

                // 获取当前的卖价（Bid）
                double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

                // 计算初始止损价格：前一根K线的最高点 + 50基点
                double stopLossPrice = high[1] + 50 * _Point;

                // 做空操作并设置止损
                if (trade.Sell(currentLots, _Symbol, bidPrice, stopLossPrice, 0, "Sell after 3 bearish candles"))
                {
                    firstCondition = true; // 设置为初始状态
                    starSet = false;
                    canOpenNewOrder = false; // 设置为不允许开新单状态
                    isOrderClosedThisBar = false; // 确保在当前K线内没有新的开单
                    return;
                }
            }
        }
    }
    else if (buyCondition)
    {
        double body3 = MathAbs(open[0] - close[0]);
        double upperShadow3 = MathAbs(high[0] - MathMax(open[0], close[0]));
        double lowestLow = MathMin(low[0], MathMin(low[1], low[2]));
        double priceRange = close[0] - lowestLow;

        if (body3 > upperShadow3 && high[0] > high[1] && high[0] > high[2] &&
            priceRange >= BuyPriceRangeMin * _Point && priceRange <= BuyPriceRangeMax * _Point)
        {
            // 记录第3根K线的最高价
            thirdCandleHigh = high[0];

            // 确保在当前K线开盘后10秒执行
            static datetime lastOrderTime = 0;
            if (canOpenNewOrder && TimeCurrent() - lastOrderTime > 60 && TimeCurrent() - currentBarTime > StartDelay)
            {
                lastOrderTime = TimeCurrent();
                OrderOpenTime = currentBarTime;
                entryTime = currentBarTime; // 设置进场时间
                barsSinceEntry = 0; // 重置K线计数器
                Print("获取下单开盘时间：", OrderOpenTime, "  ", lossOpenTime);

                // 获取当前的买价（Ask）
                double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

                // 计算初始止损价格：前一根K线的最低点 - 50基点
                double stopLossPrice = low[1] - 50 * _Point;

                // 做多操作并设置止损
                if (trade.Buy(currentLots, _Symbol, askPrice, stopLossPrice, 0, "Buy after 3 bullish candles"))
                {
                    firstCondition = true; // 设置为初始状态
                    starSet = false;
                    canOpenNewOrder = false; // 设置为不允许开新单状态
                    isOrderClosedThisBar = false; // 确保在当前K线内没有新的开单
                    return;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Trade event function                                             |
//+------------------------------------------------------------------+
void OnTrade()
{
    // Select history from the current time minus a period
    if (HistorySelect(TimeCurrent() - PeriodSeconds(), TimeCurrent()))
    {
        int historyCount = HistoryOrdersTotal(); // Get the number of historical orders

        // Iterate through historical orders
        for (int i = historyCount - 1; i >= 0; i--)
        {
            ulong ticket = HistoryOrderGetTicket(i); // Get the ticket number of the historical order

            if (HistoryOrderSelect(ticket)) // Select the historical order
            {
                // Get the order reason
                ENUM_ORDER_REASON orderReason = (ENUM_ORDER_REASON)HistoryOrderGetInteger(ticket, ORDER_REASON);

                // Check if the order was closed due to a stop loss
                if (orderReason == ORDER_REASON_SL)
                {
                    // Print a warning message
                    lossOpenTime = iTime(NULL, Timeframe, 0);
                    loss = true;
                    isOrderClosedThisBar = true; // 设置标记，表示当前K线内订单被关闭
                    Print("Warning: Order ", ticket, " was closed due to a stop loss.", lossOpenTime);
                }
            }
        }
    }
}
//+------------------------------------------------------------------+
