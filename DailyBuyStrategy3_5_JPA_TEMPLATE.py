import datetime
import logging
from typing import Optional, Union, List, Tuple

import numpy as np
import pandas as pd
import talib.abstract as ta
from pandas import DataFrame, Series

import freqtrade.vendor.qtpylib.indicators as qtpylib
from freqtrade.persistence import Trade, CustomDataWrapper
from freqtrade.strategy import (DecimalParameter, IStrategy, IntParameter)


class {{CLASS_NAME}}(IStrategy):
    INTERFACE_VERSION = 3

    minimal_roi = {
        "0": 0.03
    }

    leverage_value = {{LEVERAGE}}

    order_types = {
        'entry': 'market',
        'exit': 'market',
        'stoploss': 'market',
        'stoploss_on_exchange': False
    }

    stoploss = -0.5

    use_exit_signal = True
    exit_profit_only = False

    trailing_stop = True
    trailing_only_offset_is_reached = True
    trailing_stop_positive = 0.003
    trailing_stop_positive_offset = 0.008

    # RSI parameters
    rsi_timeperiod = IntParameter(5, 50, default=14, space='buy', optimize=True)

    # MACD parameters
    macd_fast = IntParameter(5, 30, default=12, space='buy', optimize=True)
    macd_slow = IntParameter(15, 50, default=26, space='buy', optimize=True)
    macd_signal = IntParameter(3, 20, default=9, space='buy', optimize=True)

    # Bollinger Bands parameters
    bb_window = IntParameter(10, 50, default=20, space='buy', optimize=True)
    bb_stds = DecimalParameter(1.0, 4.0, default=2.0, space='buy', optimize=True)

    # EMA parameters (buy)
    buy_ema_short = IntParameter(5, 50, default=10, space='buy', optimize=True)
    buy_ema_long = IntParameter(50, 200, default=50, space='buy', optimize=True)

    # EMA parameters (sell)
    sell_ema_short = IntParameter(5, 50, default=10, space='sell', optimize=True)
    sell_ema_long = IntParameter(50, 200, default=50, space='sell', optimize=True)

    def populate_indicators(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        # RSI
        dataframe['rsi'] = ta.RSI(dataframe, timeperiod=self.rsi_timeperiod.value)

        # MACD
        macd = ta.MACD(dataframe, fastperiod=self.macd_fast.value, slowperiod=self.macd_slow.value, signalperiod=self.macd_signal.value)
        dataframe['macd'] = macd['macd']
        dataframe['macdsignal'] = macd['macdsignal']
        dataframe['macdhist'] = macd['macdhist']

        # EMA (buy)
        dataframe['ema_short'] = ta.EMA(dataframe, timeperiod=self.buy_ema_short.value)
        dataframe['ema_long'] = ta.EMA(dataframe, timeperiod=self.buy_ema_long.value)

        # EMA (sell)
        dataframe['sell_ema_short'] = ta.EMA(dataframe, timeperiod=self.sell_ema_short.value)
        dataframe['sell_ema_long'] = ta.EMA(dataframe, timeperiod=self.sell_ema_long.value)

        # Bollinger Bands
        bollinger = qtpylib.bollinger_bands(qtpylib.typical_price(dataframe), window=self.bb_window.value, stds=float(self.bb_stds.value))
        dataframe['bb_lowerband'] = bollinger['lower']
        dataframe['bb_middleband'] = bollinger['mid']
        dataframe['bb_upperband'] = bollinger['upper']

        return dataframe

    def populate_entry_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe.loc[
            (
                (dataframe['volume'] > 0) &
                (dataframe['ema_short'] > dataframe['ema_long']) &
                (dataframe['macd'] > dataframe['macdsignal']) &
                (dataframe['rsi'] > 50)
            ),
            ['enter_long', 'enter_tag']
        ] = (1, 'ema_macd_buy')

        return dataframe

    def populate_exit_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe.loc[
            (
                (dataframe['volume'] > 0) &
                (dataframe['sell_ema_short'] < dataframe['sell_ema_long']) &
                (dataframe['macd'] < dataframe['macdsignal']) &
                (dataframe['rsi'] < 50)
            ),
            ['exit_long', 'exit_tag']
        ] = (1, 'ema_macd_sell')

        return dataframe

    def confirm_trade_exit(self, pair: str, trade: Trade, order_type: str, amount: float,
                          rate: float, time_in_force: str, exit_reason: str,
                          current_time: datetime, **kwargs) -> bool:
        return True

    def custom_exit(self, pair: str, trade: Trade, current_time: datetime, current_rate: float,
                    current_profit: float, **kwargs) -> Optional[Union[str, bool]]:
        return None
