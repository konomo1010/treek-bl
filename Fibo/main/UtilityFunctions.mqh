
//+------------------------------------------------------------------+
//| 检查当前时间是否在允许的交易时间范围内                           |
//+------------------------------------------------------------------+
bool IsWithinTradingHours(int startHour, int endHour)
{
    MqlDateTime timeStruct;
    TimeToStruct(TimeCurrent(), timeStruct);

    int currentHour = timeStruct.hour;
    return (currentHour >= startHour && currentHour < endHour);
}

//+------------------------------------------------------------------+
//| 检查当前月份是否在允许的交易月份范围内                           |
//+------------------------------------------------------------------+
bool IsMonthAllowed(string allowedMonths)
{
    string months[];
    StringSplit(allowedMonths, ',', months);

    int currentMonth;
    MqlDateTime timeStruct;
    TimeToStruct(TimeCurrent(), timeStruct);
    currentMonth = timeStruct.mon;

    for (int i = 0; i < ArraySize(months); i++)
    {
        if (StringToInteger(months[i]) == currentMonth)
            return true;
    }

    return false;
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
    stopLossHitThisBar = false;
    Print("信号状态已重置，等待新信号...");
}


