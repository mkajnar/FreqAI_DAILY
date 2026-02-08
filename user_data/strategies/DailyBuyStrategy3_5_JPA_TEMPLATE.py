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


class DailyBuyStrategy3_5_JPA(IStrategy):
    INTERFACE_VERSION = 3

    minimal_roi = {
        "0": 0.03
    }

    leverage_value = 10

    timeframe_hierarchy = {
        '1m': '5m',
        '5m': '15m',
        '15m': '1h',
        '1h': '4h',
        '4h': '1d',
        '1d': '1w',
        '1w': '1M'
    }

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

    dca_attempts = {}
    position_adjustment_enable = True
    candle_open_prices = {}
    last_dca_candle_index = {}

    last_dca_price = {}
    dca_order_table = None
    csl = {}
    thresholds = {}

    new_sl_coef = DecimalParameter(0.3, 0.9, default=0.75, space='sell', optimize=False)
    lookback_length = IntParameter(1, 30, default=15, space='buy', optimize=True)
    upper_trigger_level = IntParameter(1, 300, default=100, space='buy', optimize=True)
    lower_trigger_level = IntParameter(-300, -1, default=-100, space='sell', optimize=True)
    swing_window = IntParameter(10, 50, default=50, space='buy', optimize=False)
    swing_min_periods = IntParameter(1, 10, default=10, space='buy', optimize=False)
    buy_ema_short = IntParameter(5, 50, default=10, space='buy', optimize=True)
    buy_ema_long = IntParameter(50, 200, default=50, space='buy', optimize=True)
    dca_candles_modulo = IntParameter(1, 100, default=3, space='buy', optimize=False)
    dca_threshold = DecimalParameter(0.01, 0.5, default=0.01, space='buy', optimize=False)
    max_dca_count = IntParameter(1, 10, default=10, space='buy', optimize=False)
    dca_inc = DecimalParameter(1.2, 3.0, default=1.5, space='buy', optimize=True)

    def generate_dca_orders(self, total_amount: float, num_currencies: int, num_dca_positions: int,
                            increment: float = 1.25, minimal_stake: float = 0) -> List[float]:
        try:
            def find_initial_order(total_amount: float, increment: float, num_dca_positions: int,
                                   num_currencies: int) -> float:
                orders = [1]
                for _ in range(1, num_dca_positions + 1):
                    orders.append(orders[-1] * increment)
                total_cost_per_currency = sum(orders)
                initial_order = total_amount / (total_cost_per_currency * num_currencies)
                return max(round(initial_order, 2), minimal_stake)

            initial_order = find_initial_order(total_amount, increment, num_dca_positions, num_currencies)
            orders = [initial_order]
            for _ in range(1, num_dca_positions + 1):
                next_order = round(orders[-1] * increment, 2)
                orders.append(max(next_order, minimal_stake))
            return orders
        except Exception as e:
            logging.info(f"Exception occurred: {e}")
            return [max(1.25 ** i, minimal_stake) for i in range(num_dca_positions)]

    def leverage(self, pair: str, current_time: datetime, current_rate: float,
                 proposed_leverage: float, max_leverage: float, entry_tag: Optional[str],
                 side: str, **kwargs) -> float:
        try:
            atr_percent = getattr(self, 'current_atr_percent', 1.0)

            if atr_percent < 0.5:
                return 3.0
            elif atr_percent < 1.5:
                return 2.0
            else:
                return 1.0

        except Exception as e:
            logging.error(f"Error in leverage: {e}")
            return 2.0

    def calculate_swing(self, dataframe):
        swing_low = pd.Series(
            dataframe['low'].rolling(window=self.swing_window.value, min_periods=self.swing_min_periods.value).min(),
            index=dataframe.index
        )
        swing_high = pd.Series(
            dataframe['high'].rolling(window=self.swing_window.value, min_periods=self.swing_min_periods.value).max(),
            index=dataframe.index
        )
        return swing_low, swing_high

    def calculate_pivots(self, dataframe: DataFrame) -> Tuple[Series, Series, Series]:
        dataframe['pp'] = (dataframe['high'].shift(1) + dataframe['low'].shift(1) + dataframe['close'].shift(1)) / 3
        dataframe['r1'] = 2 * dataframe['pp'] - dataframe['low'].shift(1)
        dataframe['s1'] = 2 * dataframe['pp'] - dataframe['high'].shift(1)
        return dataframe['pp'], dataframe['r1'], dataframe['s1']

    def custom_stake_amount(self, **kwargs) -> float:
        try:
            balance = self.wallets.get_total_stake_amount()
            risk_balance = balance * 0.50
            per_currency = risk_balance / 2.0
            num_positions = self.max_dca_count.value + 1
            per_position = per_currency / num_positions
            min_stake = self.config.get("min_stake_amount", 30)
            return max(per_position, min_stake)
        except Exception as e:
            logging.error(f"Error in custom_stake_amount: {e}")
            return self.config.get("min_stake_amount", 30)

    def populate_indicators(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe['rsi'] = ta.RSI(dataframe, timeperiod=14)
        macd = ta.MACD(dataframe)
        dataframe['macd'] = macd['macd']
        dataframe['macdsignal'] = macd['macdsignal']
        dataframe['ema_short'] = ta.EMA(dataframe, timeperiod=self.buy_ema_short.value)
        dataframe['ema_long'] = ta.EMA(dataframe, timeperiod=self.buy_ema_long.value)
        dataframe['previous_close'] = dataframe['close'].shift(1)
        dataframe['max_since_buy'] = dataframe['high'].cummax()
        dataframe['atr'] = ta.ATR(dataframe, timeperiod=14)

        pp, r1, s1 = self.calculate_pivots(dataframe)
        dataframe['pivot_point'] = pp
        dataframe['resistance_1'] = r1
        dataframe['support_1'] = s1

        swing_low, swing_high = self.calculate_swing(dataframe)
        dataframe['swing_low'] = swing_low
        dataframe['swing_high'] = swing_high

        dataframe['res_signal_breaked'] = ((dataframe['close'] > dataframe['resistance_1']) & (
                dataframe['close'] > dataframe['previous_close']))

        bollinger = qtpylib.bollinger_bands(qtpylib.typical_price(dataframe), window=20, stds=2)
        dataframe['bb_lowerband'] = bollinger['lower']
        dataframe['bb_middleband'] = bollinger['mid']
        dataframe['bb_upperband'] = bollinger['upper']

        dataframe['hh'] = dataframe['close'].rolling(window=self.lookback_length.value).max()
        dataframe['ll'] = dataframe['close'].rolling(window=self.lookback_length.value).min()

        dataframe['buyPower'] = dataframe['hh'] - dataframe['ll'].shift(self.lookback_length.value)
        dataframe['sellPower'] = dataframe['hh'].shift(self.lookback_length.value) - dataframe['ll']

        dataframe['ttf'] = 200 * (dataframe['buyPower'] - dataframe['sellPower']) / (
                dataframe['buyPower'] + dataframe['sellPower'])

        close_price = dataframe['close'].iloc[-1]
        atr_value = dataframe['atr'].iloc[-1]

        if close_price > 0:
            self.current_atr_percent = (atr_value / close_price) * 100
        else:
            self.current_atr_percent = 1.0

        return dataframe

    def populate_entry_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        conditions = []

        level = self.timeframe_hierarchy[self.timeframe]
        informative = self.dp.get_pair_dataframe(pair=metadata['pair'], timeframe=level)

        if not informative.empty:
            informative = informative.reindex(dataframe.index, method='nearest')
            conditions.append(dataframe['close'] < informative['close'].shift(1))
        else:
            logging.info(f"No data available for {metadata['pair']} in '{level}' timeframe. Skipping this condition.")

        conditions.append(
            (
                    (dataframe['volume'] > 0)
            )
        )

        final_condition = np.logical_and.reduce(conditions)
        dataframe.loc[final_condition, ['enter_long', 'enter_tag']] = (1, 'ALL_BUY')
        return dataframe

    def populate_exit_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        conditions = [
            (
                    (dataframe['close'] > dataframe['swing_high']) |
                    (
                            (dataframe['macd'] < dataframe['macdsignal']) &
                            (dataframe['ema_short'] < dataframe['ema_long'])
                    ) |
                    (dataframe['ttf'] < self.lower_trigger_level.value)
            ),
            (dataframe['volume'] > 0)
        ]
        exit_condition = np.logical_and.reduce([cond.values for cond in conditions if isinstance(cond, pd.Series)])
        dataframe.loc[exit_condition, ['exit_long', 'exit_tag']] = (1, 'macd_ema_exit')
        return dataframe

    def confirm_trade_exit(self, pair: str, trade: Trade, order_type: str, amount: float,
                          rate: float, time_in_force: str, exit_reason: str,
                          current_time: datetime, **kwargs) -> bool:

        profit_ratio = trade.calc_profit_ratio(rate)
        dataframe, _ = self.dp.get_analyzed_dataframe(pair, self.timeframe)

        if ('macd_ema_exit' in exit_reason) and (profit_ratio >= 0.005):
            if pair in self.thresholds.keys():
                self.thresholds.pop(pair)
            return True

        if (('trailing' in exit_reason) or ('roi' in exit_reason)) and (profit_ratio >= 0.005):
            if pair in self.thresholds.keys():
                self.thresholds.pop(pair)
            return True

        if 'force' in exit_reason or 'trigger' in exit_reason:
            if pair in self.thresholds.keys():
                self.thresholds.pop(pair)
            return True

        return False

    def custom_exit(self, pair: str, trade: Trade, current_time: datetime, current_rate: float,
                    current_profit: float, **kwargs) -> Optional[Union[str, bool]]:
        sl = self.get_mk_sl(trade)
        if (current_rate <= sl
                or current_rate <= trade.liquidation_price * 1.1):
            return f"custom_stop_loss_{sl}"
        pass

    def informative_pairs(self):
        pairs = self.dp.current_whitelist()
        informative_pairs = [(pair, timeframe) for pair in pairs for timeframe in self.timeframe_hierarchy.keys()]
        return informative_pairs

    def calculate_dca_amount_and_threshold(self, max_funds, last_threshold):
        initial_percentage = 0.2
        initial_threshold = 1

        if last_threshold < initial_threshold / 100:
            raise ValueError("Last threshold cannot be less than the initial threshold.")

        dca_level = (last_threshold * 100 - initial_threshold) // 2

        initial_amount = max_funds * initial_percentage
        dca_amount = initial_amount * (0.8 ** dca_level)
        new_threshold = (initial_threshold + (2 * (dca_level + 1))) / 100

        return dca_amount, new_threshold

    def adjust_trade_position(self, trade: Trade, current_time: datetime,
                              current_rate: float, current_profit: float,
                              min_stake: Optional[float], max_stake: float,
                              current_entry_rate: float, current_exit_rate: float,
                              current_entry_profit: float, current_exit_profit: float,
                              **kwargs) -> Optional[float]:

        dcas = self.get_dca_list(trade)
        if len(dcas) > 0 and current_rate >= (dcas[-1] * 0.99):
            return None

        last_threshold = self.thresholds.get(trade.pair, 0.01)
        if current_profit >= -last_threshold:
            return None

        dataframe, _ = self.dp.get_analyzed_dataframe(trade.pair, self.timeframe)
        if dataframe.empty:
            return None

        last_candle = dataframe.iloc[-1]
        last_index = dataframe.index[-1]

        dca_list = self.get_dca_list(trade)
        if dca_list and current_rate > dca_list[-1]:
            logging.info(
                f"Actual price {current_rate} is higher than last DCA price {dca_list[-1]}. DCA will not applied.")
            return None

        if (last_index % self.dca_candles_modulo.value != 0):
            return None

        if last_candle['res_signal_breaked']:
            self.confirm_dca(current_rate, trade)
            try:
                available_stake_amount = self.wallets.get_available_stake_amount()
                new_dca_amount, new_threshold = self.calculate_dca_amount_and_threshold(available_stake_amount,
                                                                                        last_threshold)
                self.thresholds[trade.pair] = new_threshold
                return new_dca_amount
            except Exception as e:
                logging.error(f"Exception occurred: {e}")

        return None

    def get_dca_list(self, trade):
        try:
            dcas = CustomDataWrapper.get_custom_data(trade_id=trade.id, key="DCA")[0].value
            return dcas
        except Exception as ex:
            pass
        return []

    def get_mk_sl(self, trade):
        try:
            sl = CustomDataWrapper.get_custom_data(trade_id=trade.id, key="SL")[0].value
            return sl
        except Exception as ex:
            pass
        return trade.stop_loss

    def set_mk_sl(self, trade, current_rate):
        sl = current_rate * self.new_sl_coef.value
        CustomDataWrapper.set_custom_data(trade_id=trade.id, key="SL", value=sl)

    def confirm_dca(self, current_rate, trade):
        dcas = self.get_dca_list(trade)
        dcas.append(current_rate)
        self.set_mk_sl(trade, current_rate)
        CustomDataWrapper.set_custom_data(trade_id=trade.id, key="DCA", value=dcas)
