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

        // 设置止损
        if (StopLossMethod == SL_FIXED)
        {
            stopLossPrice = askPrice - FixedSLPoints * _Point;
        }
        else if (StopLossMethod == SL_DYNAMIC)
        {
            stopLossPrice = low - SL_Points_Buffer * _Point;
        }

        // 设置止盈
        if (TakeProfitMethod == TP_FIXED)
        {
            takeProfitPrice = askPrice + FixedTPPoints * _Point;
        }

        if (trade.Buy(Lots, _Symbol, askPrice, StopLossMethod != SL_NONE ? stopLossPrice : 0, TakeProfitMethod != TP_NONE ? takeProfitPrice : 0, "Buy Signal"))
        {
            aBarHigh = iHigh(_Symbol, Timeframe, 1);
            aBarLow = iLow(_Symbol, Timeframe, 1);
            aBarTime = iTime(_Symbol, Timeframe, 1);
            isOrderClosedThisBar = false;
            orderOpened = true;
            entryTime = TimeCurrent();

            trailingMaxHigh = aBarHigh;
            trailingMinLow = low;

            Print("做多订单已下单。");
            ResetSignalState();
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

        // 设置止损
        if (StopLossMethod == SL_FIXED)
        {
            stopLossPrice = bidPrice + FixedSLPoints * _Point;
        }
        else if (StopLossMethod == SL_DYNAMIC)
        {
            stopLossPrice = high + SL_Points_Buffer * _Point;
        }

        // 设置止盈
        if (TakeProfitMethod == TP_FIXED)
        {
            takeProfitPrice = bidPrice - FixedTPPoints * _Point;
        }

        if (trade.Sell(Lots, _Symbol, bidPrice, StopLossMethod != SL_NONE ? stopLossPrice : 0, TakeProfitMethod != TP_NONE ? takeProfitPrice : 0, "Sell Signal"))
        {
            aBarHigh = iHigh(_Symbol, Timeframe, 1);
            aBarLow = iLow(_Symbol, Timeframe, 1);
            aBarTime = iTime(_Symbol, Timeframe, 1);
            isOrderClosedThisBar = false;
            orderOpened = true;
            entryTime = TimeCurrent();

            trailingMaxHigh = high;
            trailingMinLow = aBarLow;

            Print("做空订单已下单。");
            ResetSignalState();
        }
    }
}
