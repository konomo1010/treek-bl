#include <Trade\Trade.mqh>

// 输入参数
input double Lots = 0.05;                      // 每次下单的初始手数
input ENUM_TIMEFRAMES Timeframe = PERIOD_M5;   // 选择的时间周期，默认5分钟
input int SL_Points = 50;                      // 初始止损点数（基点）
input int TP_Points = 50;                      // 止盈点数（基点）
input int StartDelay = 10;                     // 当前K线开盘后延迟秒数
input int PriceBufferPoints = 10;              // 布林带基点调整
input int BodySizePoints = 30;                 // 最小实体大小（基点）
input int PriceRangeMin = 300;                 // 收盘价与最高价/最低价的最小基点范围
input int PriceRangeMax = 700;                 // 收盘价与最高价/最低价的最大基点范围
input int TradeStartHour = 0;                  // 允许交易的开始时间（小时）
input int TradeEndHour = 24;                   // 允许交易的结束时间（小时）
input int BollingerPeriod = 15;                // 布林带周期
input double BollingerDeviation = 1.5;         // 布林带标准差倍数
input bool EnableTrailingStop = true;          // 是否启用移动止损
input bool EnableTakeProfit = true;            // 是否启用止盈
input int TrailingStopBufferPoints = 30;       // 移动止损的缓存基点
input int InitialSLPoints = 100;               // 进场时的初始止损（固定止损，基点）

CTrade trade;

// 全局变量
double starHigh = 0;
double starLow = 0;
datetime starCompleteTime = 0; // 记录进场K线完成的时间
bool starSet = false;
datetime OrderOpenTime = 0;     // 记录开仓开盘时间
bool canOpenNewOrder = true;    // 是否可以开新单
bool isOrderClosedThisBar = false; // 标记当前K线是否有订单被关闭
datetime lastCloseTime = 0;     // 记录最后一次订单关闭的时间

int bollingerHandle;  // 布林带指标句柄

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // 创建布林带指标句柄
    bollingerHandle = iBands(_Symbol, Timeframe, BollingerPeriod, 2, BollingerDeviation, PRICE_CLOSE);

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
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // 检查是否在允许的交易时间范围内，如果不在范围内，则不执行任何操作
    if (!IsWithinTradingHours())
    {
        return;
    }

    // 获取当前K线时间
    datetime currentBarTime = iTime(_Symbol, Timeframe, 0);

    // 如果进入新K线，重置isOrderClosedThisBar标志
    if (currentBarTime != OrderOpenTime)
    {
        isOrderClosedThisBar = false;
    }

    // 检查是否已在当前K线内平仓，如果是，则不允许再开新仓
    if (isOrderClosedThisBar)
    {
        return;
    }

    // 如果有持仓，管理动态止损
    if (PositionsTotal() > 0)
    {
        if (EnableTrailingStop)
        {
            ManageTrailingStop();
        }
        return;
    }

    // 如果没有持仓，嗅探进场信号
    CheckEntrySignals();
}

//+------------------------------------------------------------------+
//| 检查进场信号                                                     |
//+------------------------------------------------------------------+
void CheckEntrySignals()
{
    // 如果当前K线已经有订单被关闭，不再开新单
    if (isOrderClosedThisBar)
    {
        return;
    }

    // 准备获取布林带上下边缘的值
    double bollingerUpper[], bollingerLower[];

    // 复制布林带上轨和下轨数据
    if (CopyBuffer(bollingerHandle, 1, 0, 1, bollingerUpper) <= 0 ||  // 上轨数据，索引1
        CopyBuffer(bollingerHandle, 2, 0, 1, bollingerLower) <= 0)    // 下轨数据，索引2
    {
        Print("Error copying Bollinger Bands data: ", GetLastError());
        return;
    }

    // 获取当前K线时间
    datetime currentBarTime = iTime(_Symbol, Timeframe, 0);

    // 确保至少有4根K线（1根当前K线 + 3根已完成K线）
    if (iBars(_Symbol, Timeframe) < 4)
        return;  // 如果不足4根K线数据，退出

    // 获取最近的4根已经完成的K线数据
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
        if (bodySize < BodySizePoints)
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

    // 做多和做空条件检查
    bool buyCondition = (open[2] > open[1] && open[1] > open[0] &&  // 开盘价逐步降低
                         close[2] > close[1] && close[1] > close[0] && // 收盘价逐步降低
                         (close[0] < (bollingerLower[0] - PriceBufferPoints * _Point))); // 需满足布林带条件

    bool sellCondition = (open[2] < open[1] && open[1] < open[0] &&    // 开盘价逐步升高
                         close[2] < close[1] && close[1] < close[0] &&  // 收盘价逐步升高
                         (close[0] > (bollingerUpper[0] + PriceBufferPoints * _Point))); // 需满足布林带条件

    if (buyCondition)
    {
        // 检查第三根K线的实体大小与前两根K线的实体大小的比较
        double body3 = MathAbs(open[0] - close[0]);
        double body1 = MathAbs(open[2] - close[2]);
        double body2 = MathAbs(open[1] - close[1]);

        if (body3 > body1 && body3 > body2)
        {
            double priceRange = MathAbs(close[0] - MathMax(high[2], high[1])) / _Point;
            if (priceRange >= PriceRangeMin && priceRange <= PriceRangeMax)
            {
                static datetime lastOrderTime = 0;
                if (TimeCurrent() - lastOrderTime > 60 && TimeCurrent() - currentBarTime > StartDelay)
                {
                    lastOrderTime = TimeCurrent();
                    OrderOpenTime = currentBarTime;

                    double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                    double stopLossPrice = askPrice - InitialSLPoints * _Point; // 立即设置初始止损
                    double takeProfitPrice = EnableTakeProfit ? high[2] + TP_Points * _Point : 0;

                    if (trade.Buy(Lots, _Symbol, askPrice, stopLossPrice, takeProfitPrice, "Buy after 3 bearish candles"))
                    {
                        starSet = true;
                        starLow = low[0];  // 设置初始star值
                        starHigh = high[0];
                        starCompleteTime = TimeCurrent() + PeriodSeconds(Timeframe); // 设置star完成时间
                        isOrderClosedThisBar = false;
                        return;
                    }
                }
            }
        }
    }
    else if (sellCondition)
    {
        // 检查第三根K线的实体大小与前两根K线的实体大小的比较
        double body3 = MathAbs(open[0] - close[0]);
        double body1 = MathAbs(open[2] - close[2]);
        double body2 = MathAbs(open[1] - close[1]);

        if (body3 > body1 && body3 > body2)
        {
            double priceRange = MathAbs(close[0] - MathMin(low[2], low[1])) / _Point;
            if (priceRange >= PriceRangeMin && priceRange <= PriceRangeMax)
            {
                static datetime lastOrderTime = 0;
                if (TimeCurrent() - lastOrderTime > 60 && TimeCurrent() - currentBarTime > StartDelay)
                {
                    lastOrderTime = TimeCurrent();
                    OrderOpenTime = currentBarTime;

                    double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                    double stopLossPrice = bidPrice + InitialSLPoints * _Point; // 立即设置初始止损
                    double takeProfitPrice = EnableTakeProfit ? low[2] - TP_Points * _Point : 0;

                    if (trade.Sell(Lots, _Symbol, bidPrice, stopLossPrice, takeProfitPrice, "Sell after 3 bullish candles"))
                    {
                        starSet = true;
                        starHigh = high[0];  // 设置初始star值
                        starLow = low[0];
                        starCompleteTime = TimeCurrent() + PeriodSeconds(Timeframe); // 设置star完成时间
                        isOrderClosedThisBar = false;
                        return;
                    }
                }
            }
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
            // 重新获取当前K线的价格数据
            double previousClose = iClose(_Symbol, Timeframe, 1); // 上一根K线的收盘价
            double previousHigh = iHigh(_Symbol, Timeframe, 1);   // 上一根K线的最高价
            double previousLow = iLow(_Symbol, Timeframe, 1);     // 上一根K线的最低价

            double currentSL = PositionGetDouble(POSITION_SL);
            double currentTP = PositionGetDouble(POSITION_TP);

            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
                // 移动止损逻辑（做多）
                if (previousClose > starHigh)
                {
                    double newStopLoss = previousLow - TrailingStopBufferPoints * _Point; // 使用可调节的移动止损缓存基点
                    trade.PositionModify(ticket, newStopLoss, currentTP); // 保持止盈
                    starHigh = previousHigh; // 更新star值
                }
            }
            else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            {
                // 移动止损逻辑（做空）
                if (previousClose < starLow)
                {
                    double newStopLoss = previousHigh + TrailingStopBufferPoints * _Point; // 使用可调节的移动止损缓存基点
                    trade.PositionModify(ticket, newStopLoss, currentTP); // 保持止盈
                    starLow = previousLow; // 更新star值
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| 检查历史订单是否有止盈或止损                                     |
//+------------------------------------------------------------------+
void OnTrade()
{
    // 获取当前时间段内的订单历史记录
    if (HistorySelect(TimeCurrent() - PeriodSeconds(Timeframe), TimeCurrent()))
    {
        int historyCount = HistoryOrdersTotal(); // 获取历史订单总数

        // 遍历历史订单
        for (int i = historyCount - 1; i >= 0; i--)
        {
            ulong ticket = HistoryOrderGetTicket(i); // 获取历史订单票号

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
//+------------------------------------------------------------------+
