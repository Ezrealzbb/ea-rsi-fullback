//+------------------------------------------------------------------+
//|                                                  RsiFallback.mq5 |
//|                                  Copyright 2021, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+

//--- 引入指数平均线
#include <MovingAverages.mqh>
#include <Trade\Trade.mqh>
#include <Expert\Trailing\TrailingFixedPips.mqh>



//--- input parameters
input int      ema = 60;
input int      emaRange = 7;
input int      rsi = 14;
input int      rsiTop = 75;
input int      rsiBottom = 25;
input double   preLots = 0.01; // 交易手数
input ulong    EXPERT_MAGIC = 0; // EA幻数
input int      tpPoint = 20;
input int      slPoint = 20;

// 一些常量



// 保存指标的句柄
int EMAHandler;
//--- 用于存储ATR指标句柄
int RSIHandler;
//--- 用于交易的全局变量
CTrade ExtTrade;
//--- 上一条bar的开始时间
datetime lastbar_timeopen;



//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
//---

    EMAHandler = iMA(_Symbol, _Period, ema, 6, MODE_SMA, PRICE_CLOSE);
    if (EMAHandler == INVALID_HANDLE) {
        PrintFormat("%s: failed to create iEMA, error code %d", __FUNCTION__, GetLastError());
        return(INIT_FAILED);
    }

    RSIHandler = iRSI(_Symbol, _Period, rsi, PRICE_CLOSE);
    if (RSIHandler == INVALID_HANDLE) {
        PrintFormat("%s: failed to create iRSI, error code %d", __FUNCTION__, GetLastError());
        return(INIT_FAILED);
    }

    ExtTrade.SetExpertMagicNumber(EXPERT_MAGIC);
    ExtTrade.SetMarginMode();
    ExtTrade.SetTypeFillingBySymbol(Symbol());

//---
    return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
//---

}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
//---
    if (isNewBar()) {
        onNewBar();
    }

}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void onNewBar()
{
    int signal = getSignal();
    if (signal != 0) {
        // PrintFormat("%s: getSignal %d. Send OpenOrder", __FUNCTION__, signal);
        SendOpenOrder(signal > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
    }



}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int getSignal()
{
// 当价格远离均线，出现反转形态，RSI 超卖，做空
    int rsiSignal = checkRSISignal();
    if (rsiSignal == 0) {
        return 0;
    }

    int emaSignal = checkEMASignal();
    if (emaSignal == 0) {
        return 0;
    }
    
    bool allowed = checkBarStatus(emaSignal);
    
    if (!allowed) {
        return 0;
    }
    
    return rsiSignal == emaSignal ? rsiSignal : 0;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int checkRSISignal()
{
// rsi 的校验
    double rsiBuffer[];
    if (CopyBuffer(RSIHandler, 0, 0, 3, rsiBuffer) == -1) {
        return 0;
    }

// rsi 之间要快速落差
    //if (MathAbs(rsiBuffer[0] - rsiBuffer[1]) < 3) {
        //return 0;
    //}

// rsi 要穿过阈值线
// 下穿做空
    if (rsiBuffer[0] > rsiTop && rsiBuffer[1] < rsiTop) {
        return -1;
    }

// 上穿做多
    if (rsiBuffer[0] < rsiBottom && rsiBuffer[1] > rsiBottom) {
        return 1;
    }

    return 0;
}

// 怎么定义远离？选取 X 根  K线，第1根和最后1根的收盘价都在 EMA之上，二者之差超过一定的阈值 Y
int checkEMASignal()
{
    double emaBuffer[];
    if (CopyBuffer(EMAHandler, 0, 0, emaRange, emaBuffer) == -1) {
        return 0;
    }
    double startEma = emaBuffer[0];
    double endEma = emaBuffer[emaRange - 1];

    double rates[];
    if (CopyClose(Symbol(), Period(), 0, emaRange, rates) == -1) {
        return 0;
    }

    double startClose = rates[0];
    double endClose = rates[emaRange - 1];
// 所有价格都要在 ema 之上或之下，并且第一根 K 线的差值要比最后一根的小

    int direacton = endClose > endEma ? 1 : -1;
    if (MathAbs(startClose - startEma) >= MathAbs(endClose - endEma)) {
        return 0;
    }

    for (int i = 0; i < emaRange; i++) {
        if (direacton > 0) {
            if (rates[i] < emaBuffer[i]) {
                return 0;
            }
        } else if (direacton < 0) {
            if (rates[i] > emaBuffer[i]) {
                return 0;
            }
        }
    }

    return -direacton;

}

bool checkBarStatus(int barDirection) {
   MqlRates rates[];
    if (CopyRates(Symbol(), Period(), 1, emaRange, rates) == -1) {
        return false;
    }
    // 检测 K线的反转形态
    // 1. 阴包阳: 最后一根K线一定是阴线，要比它之前的阳线实体要大
    MqlRates lastBar = rates[rates.Size() - 1];
    
    // 上影线比例不能过高，不超过 30%
    //double topLinePercent = getBarTopLineHeight(lastBar) / getBarEntityHeight(lastBar) * 100;
    //if (topLinePercent > 50) {
    //  return false;
    //}
    
    // 向前寻找第一根反形态的 K 线
    int i = rates.Size() - 2;
    for (; i >= 0; i--) {
      if (barDirection > 0 && isUpBar(lastBar) && isDownBar(rates[i])) {
         break;
      }
      if (barDirection < 0 && isDownBar(lastBar) && isUpBar(rates[i])) {
         break;
      }
    }
    
    // not found
    if(i < 0) {
      return false;
    }
    
    double lastBarEntityHeight = getBarEntityHeight(lastBar);
    double targetBarEntityHeight = getBarEntityHeight(rates[i]);
    
    if (
      lastBarEntityHeight < targetBarEntityHeight
    ) {
      return false;
    }
    
    return true;
    
}

//+------------------------------------------------------------------+
//| Trade function                                                   |
//+------------------------------------------------------------------+
void OnTrade()
{
//---

}
//+------------------------------------------------------------------+
//--- 一些常见的工具函数
//+------------------------------------------------------------------+
//|  当新柱形图出现时返回'true'                                         |
//+------------------------------------------------------------------+
bool isNewBar(const bool print_log = true)
{
    static datetime bartime = 0; //存储当前柱形图的开盘时间
//--- 获得零柱的开盘时间
    datetime currbar_time = iTime(_Symbol, _Period, 0);
//--- 如果开盘时间更改，则新柱形图出现
    if(bartime != currbar_time) {
        bartime = currbar_time;
        lastbar_timeopen = bartime;
        //--- 在日志中显示新柱形图开盘时间的数据
        if(print_log && !(MQLInfoInteger(MQL_OPTIMIZATION) || MQLInfoInteger(MQL_TESTER))) {
            //--- 显示新柱形图开盘时间的信息
            PrintFormat("%s: new bar on %s %s opened at %s", __FUNCTION__, _Symbol,
                        StringSubstr(EnumToString(_Period), 7),
                        TimeToString(TimeCurrent(), TIME_SECONDS));
            //--- 获取关于最后报价的数据
            MqlTick last_tick;
            if(!SymbolInfoTick(Symbol(), last_tick))
                Print("SymbolInfoTick() failed, error = ", GetLastError());
            //--- 显示最后报价的时间，精确至毫秒
            PrintFormat("Last tick was at %s.%03d",
                        TimeToString(last_tick.time, TIME_SECONDS), last_tick.time_msc % 1000);
        }
        //--- 我们有一个新柱形图
        return (true);
    }
//--- 没有新柱形图
    return (false);
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SendOpenOrder(ENUM_ORDER_TYPE signal)
{
// 需要检测当前是否已经有同方向的头寸，如果已经有了，则不需要重新开单
    int total = PositionsTotal();
    for (int i = total - 1; i >= 0; --i) {
        // 获取当前的订单
        //--- 持仓参数
        ulong positionTicket = PositionGetTicket(i);
        string positionSymbol = PositionGetString(POSITION_SYMBOL);
        int positionMagic = PositionGetInteger(POSITION_MAGIC);
        int positionType = PositionGetInteger(POSITION_TYPE);

        if(positionMagic != EXPERT_MAGIC || positionSymbol != Symbol()) {
            continue;
        }

        // 已经存在做多的单，就不需要创建新的订单了
        if (positionType == POSITION_TYPE_BUY && signal == ORDER_TYPE_BUY) {
            return;
        }

        if (positionType == POSITION_TYPE_SELL && signal == ORDER_TYPE_SELL) {
            return;
        }
    }

    openOrder(signal);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool openOrder(ENUM_ORDER_TYPE signal)
{
    int spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
    double price = SymbolInfoDouble(_Symbol, signal == ORDER_TYPE_SELL ? SYMBOL_BID : SYMBOL_ASK);
    double symbolPoint = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    double spreadValue = getSymbolSpreadValue();
    double slValue = symbolPoint * slPoint + spreadValue;
    double tpValue = symbolPoint * tpPoint + spreadValue;

    double slPrice = signal == ORDER_TYPE_SELL ? price + slValue : price - slValue;
    double tpPrice = signal == ORDER_TYPE_SELL ? price - tpValue : price + tpValue;
    PrintFormat("%s: openOrder direction %d price %f tp %f sl %f spread %d", __FUNCTION__, signal, price, tpPrice, slPrice, spread);
    return ExtTrade.PositionOpen(Symbol(), signal, preLots,
                                 price,
                                 slPrice, tpPrice);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double getSymbolSpreadValue()
{
    int spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
    double symbolPoint = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    return spread * symbolPoint;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double getSymbolCurrentPrice(int direacton)
{
    double spreadValue = getSymbolSpreadValue();
    double price = SymbolInfoDouble(_Symbol, direacton < 0 ? SYMBOL_BID : SYMBOL_ASK);
    return direacton < 0 ? price + spreadValue : price - spreadValue;
}
//+------------------------------------------------------------------+
bool isUpBar(MqlRates& bar) {
   return bar.close - bar.open >= 0;
}

bool isDownBar(MqlRates& bar) {
   return bar.close - bar.open < 0;
}

double getBarEntityHeight(MqlRates& bar) {
   return MathAbs(bar.close - bar.open);
}

double getBarTopLineHeight(MqlRates& bar) {
   return isUpBar(bar) ? MathAbs(bar.high - bar.open) : MathAbs(bar.low - bar.close);
}

double getBarBottomLineHeight(MqlRates& bar) {
   return isUpBar(bar) ? MathAbs(bar.low - bar.close) : MathAbs(bar.high - bar.open);
}