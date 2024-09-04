//+------------------------------------------------------------------+
//| 检查进场信号                                                     |
//+------------------------------------------------------------------+
void CheckEntrySignals()
{
    if (PositionsTotal() > 0 || stopLossHitThisBar)
        return;

    double ma1Values[4], ma2Values[4];
    if (CopyBuffer(maHandle1, 0, 0, 4, ma1Values) < 4 || CopyBuffer(maHandle2, 0, 0, 4, ma2Values) < 4)
    {
        Print("无法复制MA数据");
        return;
    }

    double high[4], low[4], close[4], open[4];
    for (int i = 0; i < 4; i++)
    {
        high[i] = iHigh(_Symbol, Timeframe, i + 1);
        low[i] = iLow(_Symbol, Timeframe, i + 1);
        close[i] = iClose(_Symbol, Timeframe, i + 1);
        open[i] = iOpen(_Symbol, Timeframe, i + 1);
    }

    // 检查上一根K线的实体大小
    double previousCandleBodySize = MathAbs(open[1] - close[1]) / _Point;
    if (previousCandleBodySize > MaxCandleBodySizePoints)
    {
        Print("上一根K线实体大小超过限制，放弃交易。");
        return;
    }

    // 根据用户选择的交易方向检查多头或空头信号
    if (TradeDirection == TRADE_BUY_ONLY || TradeDirection == TRADE_BOTH)
    {
        if (!longSignalConfirmed && CheckLongEntrySignal(high, low, close, open, ma1Values, ma2Values))
        {
            maxHigh = MathMax(high[0], high[1]);
            trailingMaxHigh = maxHigh;
            trailingMinLow = low[0];
            longSignalConfirmed = true;
            isSignalValid = true;
            Print("多头信号已确认");

            signalBarIndex = iBarShift(_Symbol, Timeframe, iTime(_Symbol, Timeframe, 2));
        }
    }

    if (TradeDirection == TRADE_SELL_ONLY || TradeDirection == TRADE_BOTH)
    {
        if (!shortSignalConfirmed && CheckShortEntrySignal(high, low, close, open, ma1Values, ma2Values))
        {
            minLow = MathMin(low[0], low[1]);
            trailingMinLow = minLow;
            trailingMaxHigh = high[0];
            shortSignalConfirmed = true;
            isSignalValid = true;
            Print("空头信号已确认");

            signalBarIndex = iBarShift(_Symbol, Timeframe, iTime(_Symbol, Timeframe, 2));
        }
    }
}

//+------------------------------------------------------------------+
//| 检查多头进场信号                                                 |
//+------------------------------------------------------------------+
bool CheckLongEntrySignal(double &high[], double &low[], double &close[], double &open[], double &ma1Values[], double &ma2Values[])
{
    if (ma1Values[0] < ma2Values[0] &&
        open[0] < ma1Values[0] && close[0] > ma2Values[0] &&
        MathAbs(open[0] - close[0]) >= MinBodyPoints * _Point &&
        MathAbs(open[0] - close[0]) <= MaxBodyPoints * _Point)
    {
        signalHigh = high[0];
        signalLow = low[0];
        printf("信号高点: %.5f, 信号低点: %.5f", signalHigh, signalLow);
        // signalBarIndex = iBarShift(_Symbol, Timeframe, iTime(_Symbol, Timeframe, 1));
        return true;
    }

    if (ma1Values[1] < ma2Values[1] && ma1Values[0] < ma2Values[0] &&
        open[1] < ma1Values[1] && close[1] > ma1Values[1] && close[1] < ma2Values[1] &&
        close[0] > ma2Values[0] && open[0] < ma2Values[0] && open[0] > ma1Values[0] && 
        high[1] < close[0] && low[0] > open[1] &&
        MathAbs(open[1] - close[1]) >= MinBodyPoints * _Point && MathAbs(open[1] - close[1]) <= MaxBodyPoints * _Point &&
        MathAbs(open[0] - close[0]) >= MinBodyPoints * _Point && MathAbs(open[0] - close[0]) <= MaxBodyPoints * _Point)
    {
        signalHigh = MathMax(high[0], high[1]);
        signalLow = MathMin(low[0], low[1]);
        printf("信号高点: %.5f, 信号低点: %.5f", signalHigh, signalLow);
        // signalBarIndex = iBarShift(_Symbol, Timeframe, iTime(_Symbol, Timeframe, 2));
        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| 检查空头进场信号                                                 |
//+------------------------------------------------------------------+
bool CheckShortEntrySignal(double &high[], double &low[], double &close[], double &open[], double &ma1Values[], double &ma2Values[])
{
    if (ma1Values[0] > ma2Values[0] &&
        open[0] > ma1Values[0] && close[0] < ma2Values[0] &&
        MathAbs(open[0] - close[0]) >= MinBodyPoints * _Point &&
        MathAbs(open[0] - close[0]) <= MaxBodyPoints * _Point)
    {
        signalHigh = high[0];
        signalLow = low[0];
        printf("信号高点: %.5f, 信号低点: %.5f", signalHigh, signalLow);
        // signalBarIndex = iBarShift(_Symbol, Timeframe, iTime(_Symbol, Timeframe, 1));
        return true;
    }

    if (ma1Values[1] > ma2Values[1] && ma1Values[0] > ma2Values[0] &&
        open[1] > ma1Values[1] && close[1] < ma1Values[1] && close[1] > ma2Values[1] &&
        close[0] < ma2Values[0] && open[0] > ma2Values[0] && open[0] < ma1Values[0] &&
        low[1] > close[0] && high[0] < open[1] &&
        MathAbs(open[1] - close[1]) >= MinBodyPoints * _Point && MathAbs(open[1] - close[1]) <= MaxBodyPoints * _Point &&
        MathAbs(open[0] - close[0]) >= MinBodyPoints * _Point && MathAbs(open[0] - close[0]) <= MaxBodyPoints * _Point)
    {
        signalHigh = MathMax(high[0], high[1]);
        signalLow = MathMin(low[0], low[1]);
        printf("信号高点: %.5f, 信号低点: %.5f", signalHigh, signalLow);
        // signalBarIndex = iBarShift(_Symbol, Timeframe, iTime(_Symbol, Timeframe, 2));
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
        return;

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

    // 检查上一根K线的实体大小
    double previousCandleBodySize = MathAbs(lastCompletedOpen - lastCompletedClose) / _Point;
    if (previousCandleBodySize > MaxCandleBodySizePoints)
    {
        Print("上一根K线实体大小超过限制，放弃交易。");
        ResetSignalState(); // 信号无效，重置状态
        return;
    }

    if (longSignalConfirmed)
    {

        if (lastCompletedClose < maValue[0])
        {
            ResetSignalState();
            Print("多头信号无效: 上一根已完成K线的收盘价低于MA144");
        }
        else if (lastCompletedClose > maxHigh)
        {
            Print("多头信号确认，准备进场");
            Sleep(StartDelay * 1000);
            OpenBuyOrder(signalHigh, signalLow);
        }
        if (lastCompletedHigh > maxHigh)
        {
            printf("更新最高点: %.5f", lastCompletedHigh);
            maxHigh = lastCompletedHigh;
        }
    }
    else if (shortSignalConfirmed)
    {
        if (lastCompletedClose > maValue[0])
        {
            ResetSignalState();
            Print("空头信号无效: 上一根已完成K线的收盘价高于MA144");
        }
        else if (lastCompletedClose < minLow)
        {
            Print("空头信号确认，准备进场");
            Sleep(StartDelay * 1000);
            OpenSellOrder(signalHigh, signalLow);
        }

        if (lastCompletedLow < minLow)
        {
            printf("更新最低点: %.5f", lastCompletedLow);
            minLow = lastCompletedLow;
        }
    }
}
