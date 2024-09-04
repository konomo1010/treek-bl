/**
参考上述代码，用MQL5实现以下EA策略，并给出完整代码：
进场信号：
    做多：
        1. 三根K线的开盘价逐步降低，收盘价逐步降低，且第三根K线的收盘价低于布林带下轨-10个基点。基点可调节。
        2. 三根K线的实体大小均大于30个基点。基点可调节。
        3. 从左往右第三根K线的实体比前两根都大。
        4. 从左往右第三根信号K线的收盘价与第一根信号K线和第两根信号K线的最高价的差的绝对值在300-700个基点之间。做多信号价格距离基点可调节。
        5. 在三根信号K线已经完成的情况下,继续待定当前K线完成(记作第一根后信号K线)，如果后信号K线为阴线，且后信号K线实体大于从左往右第三根信号K线实体或者第一根后信号K线收盘价小于左往右第三根信号K线最低价,记录后信号K线的最低价,继续等待,直到出现一根已完成的阳线，
        
    做空：
        1. 三根K线的开盘价逐步升高，收盘价逐步升高，且第三根K线的收盘价高于布林带上轨+10个基点。基点可调节。
        2. 三根K线的实体大小均大于30个基点。基点可调节。
        3. 第三根K线的实体比前两根都大。
        4. 从左往右第三根K线的收盘价与第一根信号K线和第两根信号K线的最低价的差的绝对值在300-700个基点之间。做空信号价格距离基点可调节。

    指标：
        布林带：默认周期15，标准差1.5。参数可调节。


止盈：
    1. 做多：从左往右第一根K线的最高价+50个基点。
    2. 做空：从左往右第一根K线的最低价-50个基点。
    3. 基点可调节。
    3. 止盈功能可选择是否开启。

止损：
    1. 进场K线star临近结束前10秒，再将止损放在进场K线与三根信号K线最低价-50个基点(做多)/最高价+50个基点(做空)。初始止损基点可调节。即当star K线临近结束前10秒时，设置初始止损。
    2. 移动止损的逻辑：如果是做空，当前K线的上一根K线的收盘价低于star的最低价时将止损线设置在当前K线的上一根K线+10个基点处，并将当前K线的上一根K线记为star, 以此类推。移动止损缓存10基点可调节。如果是做多则相反。
    3. 移动止损功能可选择是否开启。


交易逻辑：
    1. 确保前面三根信号K线已经完成，等当前K线完成(即第4根K线)，如果第4根K线实体突破再在当前K线开盘后10秒执行。进场K线记为star。
    2. 在允许的时间范围内交易。时间范围可调节。
    3. 如果当前K线打掉止盈或止损，当前K线未完不允许再开仓。


2. 原来进场设置的止损变成止盈。
3. 进场的K线记为star。
3. 当现在的K线完成后，设置止损放在进场k线与三根信号线最高价+10基点(做空)/最低价-10个基点(做多)，缓冲基点可调节。
4. 移动止损的逻辑：如果是做空，当前K线的收盘价低于star的最低价时将止损线设置在当前K线+10个基点处，并将当前K线记为star, 以此类推。移动止损缓存10基点可调节。如果是做多则相反。

**/
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
input int StopLossDelaySeconds = 10;           // 设置止损延迟秒数

CTrade trade;

// 全局变量
double starHigh = 0;
double starLow = 0;
datetime starCompleteTime = 0; // 记录进场K线完成的时间
bool starSet = false;
bool stopLossSet = false;       // 标记是否已设置初始止损
datetime OrderOpenTime = 0;     // 记录开仓开盘时间
bool canOpenNewOrder = true;    // 是否可以开新单
bool isOrderClosedThisBar = false; // 标记当前K线是否有订单被关闭

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

    // 如果有持仓，管理动态止损和初始止损设置
    if (PositionsTotal() > 0)
    {
        // 检查star K线是否临近结束前10秒，并在其完成前10秒内设置初始止损
        if (starSet && !stopLossSet && TimeCurrent() >= (starCompleteTime - StopLossDelaySeconds))
        {
            SetInitialStopLoss();
            stopLossSet = true; // 标记止损已设置
        }

        if (EnableTrailingStop)
        {
            ManageTrailingStop();
        }
        return;
    }

    // 如果当前K线内订单已经关闭，则不再开仓
    if (isOrderClosedThisBar)
    {
        return;
    }

    // 如果没有持仓，嗅探进场信号
    CheckEntrySignals();
}

//+------------------------------------------------------------------+
//| 设置初始止损                                                     |
//+------------------------------------------------------------------+
void SetInitialStopLoss()
{
    for (int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket > 0)
        {
            double minLow = MathMin(starLow, MathMin(iLow(_Symbol, Timeframe, 1), MathMin(iLow(_Symbol, Timeframe, 2), iLow(_Symbol, Timeframe, 3))));
            double maxHigh = MathMax(starHigh, MathMax(iHigh(_Symbol, Timeframe, 1), MathMax(iHigh(_Symbol, Timeframe, 2), iHigh(_Symbol, Timeframe, 3))));

            double currentSL = PositionGetDouble(POSITION_SL);
            double currentTP = PositionGetDouble(POSITION_TP);

            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
                double newStopLoss = minLow - SL_Points * _Point;
                trade.PositionModify(ticket, newStopLoss, currentTP); // 使用当前止盈值
            }
            else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            {
                double newStopLoss = maxHigh + SL_Points * _Point;
                trade.PositionModify(ticket, newStopLoss, currentTP); // 使用当前止盈值
            }
        }
    }
}

//+------------------------------------------------------------------+
//| 检查进场信号                                                     |
//+------------------------------------------------------------------+
void CheckEntrySignals()
{
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
                    double stopLossPrice = 0; // 先设为0，等待star K线结束前10秒设置止损
                    double takeProfitPrice = EnableTakeProfit ? high[2] + TP_Points * _Point : 0;

                    if (trade.Buy(Lots, _Symbol, askPrice, stopLossPrice, takeProfitPrice, "Buy after 3 bearish candles"))
                    {
                        starSet = true;
                        stopLossSet = false; // 进场后重置止损设置标记
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
                    double stopLossPrice = 0; // 先设为0，等待star K线结束前10秒设置止损
                    double takeProfitPrice = EnableTakeProfit ? low[2] - TP_Points * _Point : 0;

                    if (trade.Sell(Lots, _Symbol, bidPrice, stopLossPrice, takeProfitPrice, "Sell after 3 bullish candles"))
                    {
                        starSet = true;
                        stopLossSet = false; // 进场后重置止损设置标记
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
                    double newStopLoss = previousLow - PriceBufferPoints * _Point;
                    trade.PositionModify(ticket, newStopLoss, currentTP); // 保持止盈
                    starHigh = previousHigh; // 更新star值
                }
            }
            else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            {
                // 移动止损逻辑（做空）
                if (previousClose < starLow)
                {
                    double newStopLoss = previousHigh + PriceBufferPoints * _Point;
                    trade.PositionModify(ticket, newStopLoss, currentTP); // 保持止盈
                    starLow = previousLow; // 更新star值
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| 交易事件处理函数                                                 |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
    // 检查是否有订单关闭
    if (trans.type == TRADE_TRANSACTION_DEAL_ADD && 
        (trans.deal_type == DEAL_REASON_SL || trans.deal_type == DEAL_REASON_TP))
    {
        isOrderClosedThisBar = true; // 当前K线内订单被止盈或止损
    }
}
//+------------------------------------------------------------------+
