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
input int      slBarCount = 4; // 前面几个 K 线的极致作为参考
input float      tpFactor = 1; // 盈亏比

// 一些常量



// 保存指标的句柄
int EMAHandler;
//--- 用于存储ATR指标句柄
int RSIHandler;
// 用于存储 MACD 指标句柄
int MACDHandler;
//--- 用于存储 ATR 指标句柄
int ATRHandler;
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
    
    MACDHandler = iMACD(_Symbol, _Period, 12, 26, 9, PRICE_CLOSE);
    if (MACDHandler == INVALID_HANDLE) {
        PrintFormat("%s: failed to create MACD, error code %d", __FUNCTION__, GetLastError());
        return(INIT_FAILED);
    }
    
    ATRHandler = iATR(_Symbol, _Period, 14);
    if (ATRHandler == INVALID_HANDLE) {
        PrintFormat("%s: failed to create ATR, error code %d", __FUNCTION__, GetLastError());
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
    checkRSIOverlod();
    int signal = getSignal();
    if (signal != 0) {
        // PrintFormat("%s: getSignal %d. Send OpenOrder", __FUNCTION__, signal);
        SendOpenOrder(signal > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
    }

    checkTpFromBarAndEMA();
}

int getSignal() {
    int emaSignal = checkEMASignal();
    if (emaSignal == 0) {
        return 0;
    }

    // int pinbarSignal = getSignalPinbar(emaSignal);
    // if (pinbarSignal != 0) {
    //     return pinbarSignal;
    // }

    // int crossSignal = getSignalCross(emaSignal);
    // if (crossSignal != 0) {
    //     return crossSignal;
    // }

    int macdSignal = getSignalMacd(emaSignal, RSI_OVER_LOAD_STATUS);
    if (macdSignal != 0) {
        RSI_OVER_LOAD_STATUS = 0;
        return macdSignal;
    }

    return 0;
}

// RSI + PinBar 策略：当 RSI 超过阈值，并且 K 线是 pinbar，则直接开单
int getSignalPinbar(int emaSignal) {
    // 当前 K 线的主要趋势
    int currentBarDirection = -emaSignal;

    double rsiBuffer[];
    if (CopyBuffer(RSIHandler, 0, 1, 3, rsiBuffer) == -1) {
        return 0;
    }

    double lastRsi = rsiBuffer[rsiBuffer.Size() - 1];
    if (lastRsi < rsiTop && lastRsi > rsiBottom) {
        return 0;
    }

    MqlRates rates[];
    if (CopyRates(Symbol(), Period(), 1, 3, rates) == -1) {
        return 0;
    }
    double atr[];
    if (CopyBuffer(ATRHandler, 0, 1, 2, atr) == -1) {
        return 0;
    }

    MqlRates lastBar = rates[rates.Size() - 1];
    if (!isReversePinBar(lastBar) || getBarFullHeight(lastBar) < atr[atr.Size() - 1]) {
        return 0;
    }

    int signal = 0;
    if (currentBarDirection > 0 && lastRsi >= rsiTop && isUpBar(lastBar)) {
        signal = -1;
    } else if (currentBarDirection < 0 && lastRsi <= rsiBottom && isDownBar(lastBar)) {
        signal = 1;
    }

    return signal;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int getSignalCross(int emaSignal)
{
// 当价格远离均线，出现反转形态，RSI 超卖，做空
    int rsiSignal = checkRSISignal();
    if (rsiSignal == 0) {
        return 0;
    }
    
//    bool allowedBar = checkBarStatus(emaSignal);
   
//    if (!allowedBar) {
//        return 0;
//    }
//    
//    bool allowedMACD = checkMACDStatus(rsiSignal);
//    if (!allowedMACD) {
//        return 0;
//    }
//    
    //bool allowedATR = checkATRStatus();
    //if (!allowedATR) {
    //    return 0;
    //}
    
    
    return rsiSignal == emaSignal ? rsiSignal : 0;
}

int getSignalMacd(int emaSignal, int rsiOverLoadStatus) 
{

    if (rsiOverLoadStatus == 0) {
        return 0;
    }

    //cretaing an array for prices for MACD main line
   double macdSignalBar[];
   //Storing results after defining MA, line, current data
   if(CopyBuffer(MACDHandler,0,1,5,macdSignalBar) == -1) {
      return 0;
   }

   // 最后的几个MACD 出现柱缩量

   int macdSignal = 0;
//    for (int i = 1; i < macdSignalBar.Size() - 1; i++) {
//         // 当前是 RSI 超买状态，做空
//         if (rsiOverLoadStatus > 0 && macdSignalBar[i] < macdSignalBar[i - 1]) {
//             macdSignal = -1;
//             break;
//         } else if (rsiOverLoadStatus < 0 && macdSignalBar[i] > macdSignalBar[i - 1] ) {
//             macdSignal = 1;
//             break;
//         }
//    }

    int lastIndex = macdSignalBar.Size() - 1;
    if (rsiOverLoadStatus > 0 && macdSignalBar[lastIndex] < macdSignalBar[lastIndex - 1] && macdSignalBar[lastIndex - 1] > macdSignalBar[lastIndex - 2]) {
        macdSignal = -1;
    } else if (rsiOverLoadStatus < 0 && macdSignalBar[lastIndex] > macdSignalBar[lastIndex - 1] && macdSignalBar[lastIndex - 1] < macdSignalBar[lastIndex - 2]) {
        macdSignal = 1;
    }

    return macdSignal;
}

static int RSI_OVER_LOAD_STATUS = 0;
void checkRSIOverlod() {
    double rsiBuffer[];
    if (CopyBuffer(RSIHandler, 0, 0, 3, rsiBuffer) == -1) {
        return;
    }

    if (RSI_OVER_LOAD_STATUS == 0) {
        // 到 50 就不在状态了
        for (int i = rsiBuffer.Size() - 1; i >= 0; --i) {
            // 其中一个超过了 70，则是超买
            if (rsiBuffer[i] > rsiTop) {
                RSI_OVER_LOAD_STATUS = 1;
            } else if (rsiBuffer[i] < rsiBottom) {
                RSI_OVER_LOAD_STATUS = -1;
            }
        }
        return;
    // 上穿 50 和 下穿 50，置为 0
    } else if (RSI_OVER_LOAD_STATUS > 0 && rsiBuffer[rsiBuffer.Size() - 1] < 50) {
        RSI_OVER_LOAD_STATUS = 0;
    } else if (RSI_OVER_LOAD_STATUS < 0 && rsiBuffer[rsiBuffer.Size() - 1] > 50) {
        RSI_OVER_LOAD_STATUS = 0;
    }
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
    if (rsiBuffer[0] > rsiTop && rsiBuffer[1] <= rsiTop) {
        return -1;
    }

// 上穿做多
    if (rsiBuffer[0] < rsiBottom && rsiBuffer[1] >= rsiBottom) {
        return 1;
    }

    return 0;
}

// 怎么定义远离？选取 X 根  K线，第1根和最后1根的收盘价都在 EMA之上，二者之差超过一定的阈值 Y
// 1 是一定时间的下跌趋势，需要开反转的多单
// -1 是一定时间的上跌趋势，需要开反转的空单
int checkEMASignal()
{
    double emaBuffer[];
    if (CopyBuffer(EMAHandler, 0, 1, emaRange, emaBuffer) == -1) {
        return 0;
    }
    double startEma = emaBuffer[0];
    double endEma = emaBuffer[emaRange - 1];

    MqlRates rates[];
    if (CopyRates(Symbol(), Period(), 1, emaRange, rates) == -1) {
        return 0;
    }

    double startClose = rates[0].close;
    double endClose = rates[emaRange - 1].close;
   // 所有价格都要在 ema 之上或之下，并且第一根 K 线的差值要比最后一根的小

    int direacton = endClose > endEma ? 1 : -1;
    if (MathAbs(startClose - startEma) >= MathAbs(endClose - endEma)) {
        return 0;
    }

    for (int i = 0; i < emaRange; i++) {
        // 过滤没有数据的时刻，比如元旦的3天
        if (isNoDataBar(rates[i])) {
            return 0;
        }

        if (direacton > 0) {
            if (rates[i].close < emaBuffer[i]) {
                return 0;
            }
        } else if (direacton < 0) {
            if (rates[i].close > emaBuffer[i]) {
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
    
    double atr[];
   if (CopyBuffer(ATRHandler, 0, 0, 2, atr) == -1) {
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
      // 检测 2：中间不许出现大幅跳空导致的指标异常，幅度超过 5 倍 ATR
      if (i > 0 && MathAbs(rates[i - 1].close - rates[i].open) > 5 * atr[0]) {
         return false;
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

// bool checkBarEntityHeightS

bool checkATRStatus() {

//   MqlRates rates[];
// if (CopyRates(Symbol(), Period(), 1, emaRange, rates) == -1) {
//     return false;
// }
// 
//   double sum = 0;
//   for (int i = 0; i < rates.Size(); i++) {
//      sum += MathAbs(rates[i].open - rates[i].close);
//   }
//   double avg = sum / (rates.Size() - 1);
//   if (avg < 0.05) {
//      return false;
//   }

   double atr[];
   if (CopyBuffer(ATRHandler, 0, 0, 2, atr) == -1) {
      return false;
   }
   
   return atr[0] > 0.15 && atr[1] > 0.15;
}

// MACD 此时需要是缩量状态
bool checkMACDStatus(int orderDirection) {
   //cretaing an array for prices for MACD main line
   double MACDMainLine[];
   //Storing results after defining MA, line, current data
   if(CopyBuffer(MACDHandler,0,0,4,MACDMainLine) == -1) {
      return false;
   }
   
   // prevent atr too small
   //for (int i = 0; i < 4; i++) {
   //   if (MathAbs(MACDMainLine[i]) > 0.2) {
   //      continue;
   //   }
   //   return false;
   //}
   
   // all data of MACD main value must be lower
   //for (int i = 1; i < 4; i++) {
   //   if (MathAbs(MACDMainLine[i]) > MathAbs(MACDMainLine[i - 1])) {
   //      continue;
   //   }
   //   return true;
   //}
   
   return true;
   
}

// 当有多头持仓，价格如果在止盈线之前，已经触碰到 EMA 均线，则提前止盈
void checkTpFromBarAndEMA() {

   int total = PositionsTotal(); // 当前持仓数量
   if (total == 0) {
      return; 
   }

   double emaBuffer[];
    if (CopyBuffer(EMAHandler, 0, 0, emaRange, emaBuffer) == -1) {
        return;
    }


    double rates[];
    if (CopyClose(Symbol(), Period(), 0, emaRange, rates) == -1) {
        return;
    }
    

    for (int i = total - 1; i >= 0; --i) {
        // 获取当前的订单
        //--- 持仓参数
        ulong position_ticket = PositionGetTicket(i);
        string position_symbol = PositionGetString(POSITION_SYMBOL);
        int position_magic = PositionGetInteger(POSITION_MAGIC);
        int position_type = PositionGetInteger(POSITION_TYPE);
        double position_sl = PositionGetDouble(POSITION_SL);
        double position_tp = PositionGetDouble(POSITION_TP);

        if(position_magic != EXPERT_MAGIC || position_symbol != Symbol()) {
            continue;
        }

         
        // 如果 tp 超过 ema，则取 EMA 的值为 tp
        if (
            position_type == POSITION_TYPE_BUY
            && rates[rates.Size() - 1] < emaBuffer[emaBuffer.Size() - 1]
            && position_tp > emaBuffer[emaBuffer.Size() - 1]
        ) {
            ExtTrade.PositionModify(position_ticket, position_sl, emaBuffer[emaBuffer.Size() - 1]);
            continue;
        }
        
        if (
            position_type == POSITION_TYPE_SELL
            && rates[rates.Size() - 1] > emaBuffer[emaBuffer.Size() - 1]
            && position_tp < emaBuffer[emaBuffer.Size() - 1]
        ) {
            ExtTrade.PositionModify(position_ticket, position_sl, emaBuffer[emaBuffer.Size() - 1]);
            continue;
        }
        
         
    }


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
    
    // strategy 1: fixed sl and tp
    //double slValue = symbolPoint * slPoint + spreadValue;
    //double tpValue = symbolPoint * tpPoint + spreadValue;
    //double slPrice = signal == ORDER_TYPE_SELL ? price + slValue : price - slValue;
    //double tpPrice = signal == ORDER_TYPE_SELL ? price - tpValue : price + tpValue;
    
    
    // strategy 2: get max/min value from laseast K, compare with atr valu
    double slMaxValue = getLaseatBarsMaxValue(slBarCount, signal);
    // double slPrice = slMaxValue;
    double slPrice = getMaxValueCompareWithATR(price, signal, slMaxValue);
    //double slPrice = slMaxValue + (signal == ORDER_TYPE_SELL ? 1 : -1) * spreadValue;
    double tpValue = MathAbs(slPrice - price);
    double tpPrice = signal == ORDER_TYPE_SELL ? price - tpValue * tpFactor : price + tpValue * tpFactor;
    
    PrintFormat("%s: openOrder direction %d price %f tp %f sl %f spread %d", __FUNCTION__, signal, price, tpPrice, slPrice, spread);
    return ExtTrade.PositionOpen(Symbol(), signal, preLots,
                                 price,
                                 slPrice, tpPrice);
}

double getLaseatBarsMaxValue(int lastNumber, ENUM_ORDER_TYPE signal) {
    MqlRates rates[];
    if (CopyRates(Symbol(), Period(), 1, lastNumber, rates) == -1) {
        return 0;
    }
    
    double maxValue = signal == ORDER_TYPE_BUY ? rates[0].low : rates[0].high;
    for (int i = 0; i < rates.Size(); i++) {
      maxValue = signal == ORDER_TYPE_BUY ? MathMin(rates[i].low, maxValue) : MathMax(rates[i].high, maxValue);
    }
    
    return maxValue;
}

double getMaxValueCompareWithATR(double currentPrice, ENUM_ORDER_TYPE signal, double barMaxPrice) {
    double atr = getCurrentATRValue();
    if (atr == 0) {
        return barMaxPrice;
    }
    double barDistance = MathAbs(currentPrice - barMaxPrice);
    double slDistance = MathMax(barDistance, atr);
    return signal == ORDER_TYPE_BUY ? currentPrice - slDistance : currentPrice + slDistance;
}

double getCurrentATRValue() {
    double atrs[];
    if (CopyBuffer(ATRHandler, 0, 1, 1, atrs) == -1) {
        return 0;
    }
    return atrs[0];
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

// 属于顶底反转的 pinbar
bool isReversePinBar(MqlRates& bar) {
    bool isUp = isUpBar(bar);
    // 如果是阳线，则取上影线，如果是阴线，则取下影线
    double failLineHeight = isUp ? MathAbs(bar.high - bar.close) : MathAbs(bar.close - bar.low);
    double fullHeight = MathAbs(bar.high - bar.low);
    // 引线比例超过 55%
    return failLineHeight / fullHeight > 0.55;
}

bool isNoDataBar(MqlRates& bar) {
    return MathAbs(bar.high - bar.low) == 0;
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

double getBarFullHeight(MqlRates& bar) {
    return MathAbs(bar.high - bar.low);
}