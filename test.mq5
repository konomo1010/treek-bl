#include <Trade\Trade.mqh>

// 输入参数
input double Lots = 0.1;                      // 每次下单的手数
input double RiskPercentage = 1.0;            // 每笔交易的风险百分比
input int FastMAPeriod = 21;                  // 快速均线周期
input int SlowMAPeriod = 55;                  // 慢速均线周期
input int ADXPeriod = 14;                     // ADX周期
input double ADXThreshold = 25.0;             // ADX阈值
input int StopLossPoints = 500;               // 止损点数（基点）
input int TakeProfitPoints = 1000;            // 止盈点数（基点）

CTrade trade;

int fastMAHandle, slowMAHandle, adxHandle;    // 指标句柄
double fastMA[], slowMA[], adx[];             // 用于存储指标值的数组

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // 创建快速移动平均线的句柄
    fastMAHandle = iMA(_Symbol, _Period, FastMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
    if (fastMAHandle == INVALID_HANDLE)
    {
        Print("Error creating fast MA handle: ", GetLastError());
        return INIT_FAILED;
    }

    // 创建慢速移动平均线的句柄
    slowMAHandle = iMA(_Symbol, _Period, SlowMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
    if (slowMAHandle == INVALID_HANDLE)
    {
        Print("Error creating slow MA handle: ", GetLastError());
        return INIT_FAILED;
    }

    // 创建ADX指标的句柄
    adxHandle = iADX(_Symbol, _Period, ADXPeriod);
    if (adxHandle == INVALID_HANDLE)
    {
        Print("Error creating ADX handle: ", GetLastError());
        return INIT_FAILED;
    }

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // 释放指标句柄
    if (fastMAHandle != INVALID_HANDLE) IndicatorRelease(fastMAHandle);
    if (slowMAHandle != INVALID_HANDLE) IndicatorRelease(slowMAHandle);
    if (adxHandle != INVALID_HANDLE) IndicatorRelease(adxHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // 检查指标句柄是否有效
    if (fastMAHandle == INVALID_HANDLE || slowMAHandle == INVALID_HANDLE || adxHandle == INVALID_HANDLE)
    {
        Print("Invalid indicator handle. Exiting OnTick.");
        return;
    }

    // 获取快速均线的当前和前一个值
    if (CopyBuffer(fastMAHandle, 0, 0, 2, fastMA) <= 0)
    {
        Print("Failed to copy fast MA data: ", GetLastError());
        return;
    }

    // 获取慢速均线的当前和前一个值
    if (CopyBuffer(slowMAHandle, 0, 0, 2, slowMA) <= 0)
    {
        Print("Failed to copy slow MA data: ", GetLastError());
        return;
    }

    // 获取ADX的当前和前一个值
    if (CopyBuffer(adxHandle, 0, 0, 2, adx) <= 0)
    {
        Print("Failed to copy ADX data: ", GetLastError());
        return;
    }

    // 如果没有持仓，检查是否有新的交易信号
    if (PositionsTotal() == 0)
    {
        // 买入信号：快速均线上穿慢速均线，且ADX大于阈值
        if (fastMA[1] < slowMA[1] && fastMA[0] > slowMA[0] && adx[0] > ADXThreshold)
        {
            double lotSize = CalculateLotSize();
            double stopLossPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID) - StopLossPoints * _Point;
            double takeProfitPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID) + TakeProfitPoints * _Point;
            trade.Buy(lotSize, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK), stopLossPrice, takeProfitPrice, "Buy Signal");
        }
        // 卖出信号：快速均线下穿慢速均线，且ADX大于阈值
        else if (fastMA[1] > slowMA[1] && fastMA[0] < slowMA[0] && adx[0] > ADXThreshold)
        {
            double lotSize = CalculateLotSize();
            double stopLossPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + StopLossPoints * _Point;
            double takeProfitPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - TakeProfitPoints * _Point;
            trade.Sell(lotSize, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID), stopLossPrice, takeProfitPrice, "Sell Signal");
        }
    }
}

//+------------------------------------------------------------------+
//| 计算每笔交易的手数                                                |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);  // 使用AccountInfoDouble获取账户余额
    double risk = accountBalance * (RiskPercentage / 100.0);
    double lotSize = risk / (StopLossPoints * _Point * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE));
    lotSize = NormalizeDouble(lotSize, 2);  // 保留两位小数
    return lotSize;
}
