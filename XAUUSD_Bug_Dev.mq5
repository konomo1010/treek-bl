#include <Trade\Trade.mqh>

// 输入参数
input double Lots = 0.05;                      // 每次下单的手数
input ENUM_TIMEFRAMES Timeframe = PERIOD_M5;   // 选择的时间周期，默认5分钟
input int SL_Points1 = 50;                     // 初始止损点数（基点）
input int SL_Points2 = 30;                     // 动态调整止损点数（基点）
input int StartDelay = 10;                     // 当前K线开盘后延迟秒数
input int PriceRangeMin = 250;                 // 收盘价与最低价的最小基点范围
input int PriceRangeMax = 700;                 // 收盘价与最低价的最大基点范围

CTrade trade;

double starHigh = 0;
double starLow = 0;
double starClose = 0;
double starOpen = 0;
bool starSet = true;
bool firstCondition = true; // 第一次止损条件标识
datetime OrderOpenTime = 0; // 记录开仓开盘价
double thirdCandleHigh = 0; // 记录第3根K线的最高价
bool loss = false;          // 止损是否被打掉
datetime lossOpenTime = 0;  // 记录止损被打掉所处K线开仓时间
bool canOpenNewOrder = true; // 是否可以开新单

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
    // 检查是否存在未平仓订单
    if (PositionsTotal() > 0)
    {
        if (OrderOpenTime != iTime(NULL, Timeframe, 0) && !starSet)
        {
            starLow = iLow(_Symbol, Timeframe, 1);
            starHigh = iHigh(_Symbol, Timeframe, 1);
            starClose = iClose(_Symbol, Timeframe, 1);
            starOpen = iOpen(_Symbol, Timeframe, 1);
            starSet = true;
            Print("OrderOpenTime: ", OrderOpenTime, " now: ", iTime(NULL, Timeframe, 0));
            Print(">>>> starHigh: ", iHigh(_Symbol, Timeframe, 1), " , starLow: ", iLow(_Symbol, Timeframe, 1));
        }

        // 如果存在订单，动态调整止损
        double currentClose = iClose(_Symbol, Timeframe, 1);
        double currentLow = iLow(_Symbol, Timeframe, 1);
        double currentHigh = iHigh(_Symbol, Timeframe, 1);

        Print("=============> ", starHigh, " , ", thirdCandleHigh);

        // 首次止损移动条件
        if (firstCondition && currentClose > MathMax(starClose, thirdCandleHigh))
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
        // 后续止损移动条件
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
        return;
    }

    if (loss)
    {
        if (lossOpenTime == iTime(NULL, Timeframe, 0))
        {
            Print("》》》》》 未走完 ", lossOpenTime, "  ", iTime(NULL, Timeframe, 0));
            return;
        }
        Print("》》》》》 已走完");
        loss = false;
        canOpenNewOrder = true; // 恢复开新单状态
    }

    // 确保至少有4根K线（1根当前K线 + 3根已完成K线）
    if (iBars(_Symbol, Timeframe) < 4)
        return;  // 如果不足4根K线数据，退出

    // 获取最近的3根已经完成的K线数据（注意这里用的是 [1], [2], [3]）
    double high[3], low[3], close[3], open[3];

    for (int i = 0; i < 3; i++)
    {
        high[i] = iHigh(_Symbol, Timeframe, i + 1);
        low[i] = iLow(_Symbol, Timeframe, i + 1);
        close[i] = iClose(_Symbol, Timeframe, i + 1);
        open[i] = iOpen(_Symbol, Timeframe, i + 1);
    }

    // 检查连续3根K线是否满足做多条件
    if (open[2] < open[1] && open[1] < open[0] &&    // 开盘价逐步升高
        close[2] < close[1] && close[1] < close[0])  // 收盘价逐步升高
    {
        double body3 = MathAbs(open[0] - close[0]);
        double upperShadow3 = MathAbs(high[0] - MathMax(open[0], close[0]));
        double lowestLow = MathMin(low[0], MathMin(low[1], low[2]));
        double priceRange = close[0] - lowestLow;

        // 第3根K线的实体部分要比上影线长，并且第3根K线的最高价为3根K线的最高价
        if (body3 > upperShadow3 && high[0] > high[1] && high[0] > high[2] &&
            priceRange >= PriceRangeMin * _Point && priceRange <= PriceRangeMax * _Point)
        {
            // 记录第3根K线的最高价
            thirdCandleHigh = high[0];

            // 确保在当前K线开盘后10秒执行
            static datetime lastOrderTime = 0;
            if (canOpenNewOrder && TimeCurrent() - lastOrderTime > 60 && TimeCurrent() - iTime(_Symbol, Timeframe, 0) > StartDelay)
            {
                lastOrderTime = TimeCurrent();
                OrderOpenTime = iTime(NULL, Timeframe, 0);
                Print("获取下单开盘时间：", OrderOpenTime, "  ", lossOpenTime);

                // 获取当前的买价（Ask）
                double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

                // 计算止损价格
                double stopLossPrice = MathMin(low[0], MathMin(low[1], low[2])) - 20 * _Point;

                // 做多操作并设置止损
                if (trade.Buy(Lots, _Symbol, askPrice, stopLossPrice, 0, "Buy after 3 bullish candles"))
                {
                    firstCondition = true; // 设置为初始状态
                    starSet = false;
                    canOpenNewOrder = false; // 设置为不允许开新单状态
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
                    Print("Warning: Order ", ticket, " was closed due to a stop loss.", lossOpenTime);
                }
            }
        }
    }
}
//+------------------------------------------------------------------+
