#include <Trade\Trade.mqh>
#include "SignalCheck.mqh"
#include "OrderManagement.mqh"
#include "StopLossManagement.mqh"
#include "UtilityFunctions.mqh"

// 定义止盈方式的枚举
enum ENUM_TAKE_PROFIT_METHOD
{
    TP_NONE,           // 不设止盈
    TP_FIXED           // 固定止盈
};

// 定义止损方式的枚举
enum ENUM_STOP_LOSS_METHOD
{
    SL_NONE,           // 不设止损
    SL_FIXED,          // 固定止损
    SL_DYNAMIC         // 动态止损
};

// 定义交易方向的枚举
enum ENUM_TRADE_DIRECTION
{
    TRADE_BUY_ONLY,   // 只做多
    TRADE_SELL_ONLY,  // 只做空
    TRADE_BOTH        // 多空都做
};



// 输入参数

input ENUM_TRADE_DIRECTION TradeDirection = TRADE_BOTH; // 默认多空都做
input string AllowedMonths = "2,3,4,5,6,7,8,9,10,11"; // 允许交易的月份（用逗号分隔）
input int TradeStartHour = 0;                         // 允许交易的开始时间（小时）
input int TradeEndHour = 24;                          // 允许交易的结束时间（小时）
input ENUM_TIMEFRAMES Timeframe = PERIOD_M5;          // 交易时间周期，默认5分钟
input double Lots = 0.05;                             // 初始下单手数
input int MA1_Period = 144;                           // 移动平均线1周期
input int MA2_Period = 169;                           // 移动平均线2周期
input ENUM_MA_METHOD MA_Method = MODE_SMA;            // 移动平均线方法
input ENUM_APPLIED_PRICE Applied_Price = PRICE_CLOSE; // 移动平均线应用价格

input int MinBodyPoints = 50;                         // 信号K线最小实体大小（基点）
input int MaxBodyPoints = 300;                        // 信号K线最大实体大小（基点）

input int StartDelay = 10;                            // 当前K线结束前等待时间（秒）

input int MaxCandleBodySizePoints = 500;              // 信号确认后最大允许的K线实体大小（基点）

input ENUM_STOP_LOSS_METHOD StopLossMethod = SL_DYNAMIC;   // 默认使用动态止损方式
input int SL_Points_Buffer = 50;                      // 动态止损初始缓存基点
input int DynamicSL_Buffer = 100;                     // 动态止损移动缓存基点
input int FixedSLPoints = 200;                        // 固定止损点数（基点）

input ENUM_TAKE_PROFIT_METHOD TakeProfitMethod = TP_NONE; // 默认使用不设止盈方式
input int FixedTPPoints = 200;                        // 固定止盈点数（基点）


CTrade trade;

// 全局变量声明和初始化
datetime lastCloseTime = 0;
bool isOrderClosedThisBar = false;
double aBarHigh, aBarLow;
datetime aBarTime;
bool orderOpened = false;
int signalBarIndex = -1;
bool stopLossHitThisBar = false;
int maHandle1, maHandle2;
int maHandleMA144;
double maxHigh, minLow;
double signalHigh, signalLow;
bool isSignalValid = false;
bool longSignalConfirmed = false;
bool shortSignalConfirmed = false;
datetime entryTime = 0;
double trailingMaxHigh, trailingMinLow;


// 用于记录当前K线的时间
datetime currentBarTime = 0;

// 新增均线、ATR和RSI指标的句柄
int ema576Handle, ema676Handle, atrHandle, rsiHandle;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    maHandle1 = iMA(_Symbol, Timeframe, MA1_Period, 0, MA_Method, Applied_Price);
    maHandle2 = iMA(_Symbol, Timeframe, MA2_Period, 0, MA_Method, Applied_Price);
    maHandleMA144 = iMA(_Symbol, Timeframe, 144, 0, MA_Method, Applied_Price);

    // 创建EMA576和EMA676均线句柄
    ema576Handle = iMA(_Symbol, Timeframe, 576, 0, MODE_EMA, PRICE_CLOSE);
    ema676Handle = iMA(_Symbol, Timeframe, 676, 0, MODE_EMA, PRICE_CLOSE);

    // 创建ATR14指标句柄
    atrHandle = iATR(_Symbol, Timeframe, 14);

    // 创建RSI21指标句柄
    rsiHandle = iRSI(_Symbol, Timeframe, 21, PRICE_CLOSE);

    if (maHandle1 == INVALID_HANDLE || maHandle2 == INVALID_HANDLE || maHandleMA144 == INVALID_HANDLE ||
        ema576Handle == INVALID_HANDLE || ema676Handle == INVALID_HANDLE || atrHandle == INVALID_HANDLE ||
        rsiHandle == INVALID_HANDLE)
    {
        Print("无法创建指标句柄");
        return (INIT_FAILED);
    }

    // 初始化当前K线的时间
    currentBarTime = iTime(_Symbol, Timeframe, 0);

    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    IndicatorRelease(maHandle1);
    IndicatorRelease(maHandle2);
    IndicatorRelease(maHandleMA144);
    IndicatorRelease(ema576Handle);
    IndicatorRelease(ema676Handle);
    IndicatorRelease(atrHandle);
    IndicatorRelease(rsiHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    if (!IsWithinTradingHours(TradeStartHour, TradeEndHour) || !IsMonthAllowed(AllowedMonths))
        return;

    // 获取当前K线的时间
    datetime newBarTime = iTime(_Symbol, Timeframe, 0);

    // 判断是否是新K线开始
    if (newBarTime != currentBarTime)
    {
        currentBarTime = newBarTime;  // 更新当前K线的时间
        isOrderClosedThisBar = false; // 重置标记，表示新K线开始
        stopLossHitThisBar = false;   // 重置止损状态

        // 只有在新K线开始时，才更新信号有效性和检查进场信号
        UpdateSignalValidity();
        CheckEntrySignals();
    }

    // 显示EMA、ATR和RSI指标
    DisplayIndicators();

    if (PositionsTotal() > 0)
    {
        if (StopLossMethod == SL_DYNAMIC)
            ManageTrailingStop();
    }
}

//+------------------------------------------------------------------+
//| 显示指标函数                                                     |
//+------------------------------------------------------------------+
void DisplayIndicators()
{
    double ema576Value[1], ema676Value[1], atrValue[1], rsiValue[1];

    // 复制指标值
    if (CopyBuffer(ema576Handle, 0, 0, 1, ema576Value) < 0 ||
        CopyBuffer(ema676Handle, 0, 0, 1, ema676Value) < 0 ||
        CopyBuffer(atrHandle, 0, 0, 1, atrValue) < 0 ||
        CopyBuffer(rsiHandle, 0, 0, 1, rsiValue) < 0)
    {
        Print("无法获取指标数据");
        return;
    }

    // 打印均线、ATR和RSI值
    Print("EMA576: ", ema576Value[0], " EMA676: ", ema676Value[0], " ATR14: ", atrValue[0], " RSI21: ", rsiValue[0]);

    // 绘制RSI水平线
    ObjectCreate(0, "RSI_Level_30", OBJ_HLINE, 0, TimeCurrent(), 30);
    ObjectSetInteger(0, "RSI_Level_30", OBJPROP_COLOR, clrRed);
    ObjectCreate(0, "RSI_Level_70", OBJ_HLINE, 0, TimeCurrent(), 70);
    ObjectSetInteger(0, "RSI_Level_70", OBJPROP_COLOR, clrRed);
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
                    Print("注意: 订单 ", ticket, " 已经被关闭 ", orderReason == ORDER_REASON_SL ? "止损" : "止盈", ".");
                    trailingMaxHigh = 0;
                    trailingMinLow = 0;
                    ResetSignalState(); // 重置信号状态
                }
            }
        }
    }
}

//+------------------------------------------------------------------+