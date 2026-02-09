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

    stoploss = -0.5  # Basic stop loss

    use_exit_signal = True
    exit_profit_only = False

    # Trailing stoploss
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
    stake_amount_coef = DecimalParameter(0.1, 1.0, default=1.0, space='buy', optimize=True)
    lev_koef = DecimalParameter(0.1, 0.9, default=0.5, space='buy', optimize=True)

    # buy_rsi = IntParameter(25, 60, default=55, space='buy', optimize=False)
    # sell_rsi = IntParameter(50, 70, default=70, space='sell', optimize=False)
    # atr_multiplier = DecimalParameter(1.0, 3.0, default=1.5, space='stoploss', optimize=False)
    # swing_buffer = DecimalParameter(0.01, 0.1, default=0.03, space='buy', optimize=False)
    # buy_macd = DecimalParameter(-0.02, 0.02, default=0.00, space='buy', optimize=False)
    # sell_macd = DecimalParameter(-0.02, 0.02, default=-0.005, space='sell', optimize=False)
    # sell_ema_short = IntParameter(5, 50, default=10, space='sell', optimize=False)
    # sell_ema_long = IntParameter(50, 200, default=50, space='sell', optimize=False)

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
        """
        Dynamický leverage dle ATR volatility (1-5x) násobený hyperopt koeficientem.

        Logika ATR:
        - ATR < 0.5% Close → base leverage 5x (velmi nízká volatilita)
        - ATR 0.5% - 1.0% Close → base leverage 4x (nízká volatilita)
        - ATR 1.0% - 1.5% Close → base leverage 3x (normální)
        - ATR 1.5% - 2.0% Close → base leverage 2x (vyšší volatilita)
        - ATR > 2.0% Close → base leverage 1x (vysoká volatilita)
        
        Finální leverage = base_leverage * lev_koef (0.1-0.9)
        
        Příklady:
        - Nízka volatilita (ATR 0.3%) → 5x * 0.5 = 2.5x
        - Normální (ATR 1.2%) → 3x * 0.5 = 1.5x
        - Vysoká (ATR 2.5%) → 1x * 0.5 = 0.5x
        """
        try:
            # Načti poslední ATR % ze self (uloženo v populate_indicators)
            atr_percent = getattr(self, 'current_atr_percent', 1.0)

            # Logika pro přiřazení base leveragu dle volatility (1-5x)
            if atr_percent < 0.5:
                base_leverage = 5.0  # Velmi nízká volatilita
            elif atr_percent < 1.0:
                base_leverage = 4.0  # Nízká volatilita
            elif atr_percent < 1.5:
                base_leverage = 3.0  # Normální volatilita
            elif atr_percent < 2.0:
                base_leverage = 2.0  # Vyšší volatilita
            else:
                base_leverage = 1.0  # Vysoká volatilita

            # Aplikuj hyperopt koeficient (0.1-0.9)
            final_leverage = base_leverage * self.lev_koef.value
            
            # Omez na maximum
            final_leverage = min(final_leverage, max_leverage)

            return final_leverage

        except Exception as e:
            logging.error(f"Error in leverage: {e}")
            return 1.5  # Fallback: konzervativní mid leverage

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
        # Calculate the pivot point (PP)
        dataframe['pp'] = (dataframe['high'].shift(1) + dataframe['low'].shift(1) + dataframe['close'].shift(1)) / 3
        # Calculate the first resistance (R1)
        dataframe['r1'] = 2 * dataframe['pp'] - dataframe['low'].shift(1)
        # Calculate the first support (S1)
        dataframe['s1'] = 2 * dataframe['pp'] - dataframe['high'].shift(1)
        return dataframe['pp'], dataframe['r1'], dataframe['s1']

    def custom_stake_amount(self, **kwargs) -> float:
        """
        Dynamická velikost sázky s optimálním money managementem a hyperoptovatelným koeficientem.

        Výpočet:
        - 50% walletu se alokuje na trading (50% buffer)
        - Zbylých 50% se dělí mezi 2 měny (25% per měnu)
        - 25% per měnu se dělí mezi všechny DCA pozice (initial + max_dca_count)
        - Výsledek se násobí stake_amount_coef pro hyperopt optimalizaci

        Příklad (5000 USDT wallet, stake_amount_coef=0.5):
        - Risk: 5000 * 0.50 = 2500 USDT
        - Per měnu: 2500 / 2 = 1250 USDT
        - Per pozici (bez coef): 1250 / 11 = 113.64 USDT
        - Per pozici (s coef): 113.64 * 0.5 = 56.82 USDT ← 50% nižší!
        """
        try:
            balance = self.wallets.get_total_stake_amount()

            # Risk management: 50% walletu na trading, 50% buffer
            risk_balance = balance * 0.50

            # Rozdělení mezi 2 měny (25% per měnu)
            per_currency = risk_balance / 2.0

            # Rozdělení mezi všechny DCA pozice (initial + max_dca_count)
            num_positions = self.max_dca_count.value + 1
            per_position = per_currency / num_positions

            # Aplikuj hyperoptovatelný koeficient
            adjusted_position = per_position * self.stake_amount_coef.value

            # Minimální sázka (exchange minimum je ~11-30 USDT)
            min_stake = self.config.get("min_stake_amount", 30)

            return max(adjusted_position, min_stake)
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

        # Calculate Pivot Points and Resistance/Support Levels
        pp, r1, s1 = self.calculate_pivots(dataframe)
        dataframe['pivot_point'] = pp
        dataframe['resistance_1'] = r1
        dataframe['support_1'] = s1

        swing_low, swing_high = self.calculate_swing(dataframe)
        dataframe['swing_low'] = swing_low
        dataframe['swing_high'] = swing_high

        # Add a resistance signal (for example, price approaching or crossing R1)
        dataframe['res_signal_breaked'] = ((dataframe['close'] > dataframe['resistance_1']) & (
                dataframe['close'] > dataframe['previous_close']))

        bollinger = qtpylib.bollinger_bands(qtpylib.typical_price(dataframe), window=20, stds=2)
        dataframe['bb_lowerband'] = bollinger['lower']
        dataframe['bb_middleband'] = bollinger['mid']
        dataframe['bb_upperband'] = bollinger['upper']
        # CustomDataWrapper.set_custom_data(trade_id=40, key='test', value='ahoj')
        # t = CustomDataWrapper.get_custom_data(trade_id=40, key='test')[0].value

        # Calculate highest and lowest
        dataframe['hh'] = dataframe['close'].rolling(window=self.lookback_length.value).max()
        dataframe['ll'] = dataframe['close'].rolling(window=self.lookback_length.value).min()

        # Calculate buy and sell power
        dataframe['buyPower'] = dataframe['hh'] - dataframe['ll'].shift(self.lookback_length.value)
        dataframe['sellPower'] = dataframe['hh'].shift(self.lookback_length.value) - dataframe['ll']

        # Calculate TTF
        dataframe['ttf'] = 200 * (dataframe['buyPower'] - dataframe['sellPower']) / (
                dataframe['buyPower'] + dataframe['sellPower'])

        # Calculate ATR percentage for dynamic leverage (5m timeframe)
        # ATR % = (ATR / Close) * 100
        close_price = dataframe['close'].iloc[-1]
        atr_value = dataframe['atr'].iloc[-1]

        if close_price > 0:
            self.current_atr_percent = (atr_value / close_price) * 100
        else:
            self.current_atr_percent = 1.0  # Fallback na normální volatilitu

        return dataframe

    def populate_entry_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        conditions = []

        # Získání dat vyššího časového rámce pro analýzu na více časových rámcích
        level = self.timeframe_hierarchy[self.timeframe]
        informative = self.dp.get_pair_dataframe(pair=metadata['pair'], timeframe=level)

        if not informative.empty:
            # Ujistěte se, že 'informative' je zarovnán s hlavním dataframe
            informative = informative.reindex(dataframe.index, method='nearest')
            # Nyní bezpečně porovnávejte uzavírací ceny, protože jsou zarovnané
            conditions.append(dataframe['close'] < informative['close'].shift(1))
        else:
            logging.info(f"No data available for {metadata['pair']} in '{level}' timeframe. Skipping this condition.")

        conditions.append(
            (
                    (dataframe['volume'] > 0)
                    # &
                    # (dataframe['close'] < dataframe['open']) # &
                    # (dataframe['macd'] > dataframe['macdsignal']) & (dataframe['ema_short'] > dataframe['ema_long'])
            )
        )

        final_condition = np.logical_and.reduce(conditions)
        dataframe.loc[final_condition, ['enter_long', 'enter_tag']] = (1, 'ALL_BUY')
        return dataframe

        # Conditions list can be used to store various buying conditions
        conditions = [
            # Basic condition: MACD crossover and EMA crossover
            (dataframe['macd'] > dataframe['macdsignal']) & (dataframe['ema_short'] > dataframe['ema_long']) |
            (dataframe['res_signal_breaked']) & (dataframe['volume'] > 0) |
            (dataframe['ttf'] > self.upper_trigger_level.value)
        ]

        # Check if all conditions are pandas Series and apply logical AND reduction to get the final condition
        if all(isinstance(cond, pd.Series) for cond in conditions):
            final_condition = np.logical_and.reduce(conditions)
            dataframe.loc[final_condition, ['enter_long', 'enter_tag']] = (1, 'multi_timeframe_cross')
        else:
            logging.error("Not all conditions are pandas Series.")

        return dataframe

    def populate_exit_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        # Příprava podmínek
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
            # logging.info(f"[CTE] {pair}, Exit reason {exit_reason}, confirmed profit: {profit_ratio}")
            if pair in self.thresholds.keys():
                self.thresholds.pop(pair)
            return True

        if (('trailing' in exit_reason) or ('roi' in exit_reason)) and (profit_ratio >= 0.005):
            # logging.info(f"[CTE] {pair}, Exit reason {exit_reason}, confirmed profit: {profit_ratio}")
            if pair in self.thresholds.keys():
                self.thresholds.pop(pair)
            return True

        if 'force' in exit_reason or 'trigger' in exit_reason:
            if pair in self.thresholds.keys():
                self.thresholds.pop(pair)
            return True

        # if 'stop_loss' in exit_reason:
        #    if len(self.get_dca_list(trade)) < 10:
        #        return False  # Pokračování v obchodování
        #    else:
        #        return True  # Ukončení obchodu po 3 pokusech
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
        """
        Vypočítá novou částku pro DCA a nový threshold pro start dalšího DCA.

        :param max_funds: Maximální výše volných prostředků pro jednu pozici.
        :param last_threshold: Poslední použitý threshold pro DCA.
        :return: Tuple (nová částka pro DCA, nový threshold pro start dalšího DCA)
        """
        # Počáteční hodnoty
        initial_percentage = 0.2
        initial_threshold = 1

        # Vypočítání aktuální úrovně DCA na základě posledního thresholdu
        if last_threshold < initial_threshold / 100:
            raise ValueError("Last threshold cannot be less than the initial threshold.")

        dca_level = (last_threshold * 100 - initial_threshold) // 2

        # Vypočítat částku pro počáteční nákup
        initial_amount = max_funds * initial_percentage

        # Výpočet částky pro aktuální DCA
        dca_amount = initial_amount * (0.8 ** dca_level)

        # Výpočet nového thresholdu
        new_threshold = (initial_threshold + (2 * (dca_level + 1))) / 100

        return dca_amount, new_threshold

    def adjust_trade_position(self, trade: Trade, current_time: datetime,
                              current_rate: float, current_profit: float,
                              min_stake: Optional[float], max_stake: float,
                              current_entry_rate: float, current_exit_rate: float,
                              current_entry_profit: float, current_exit_profit: float,
                              **kwargs) -> Optional[float]:

        # Kontrola, jestli není current_rate nad definovaným stop loss
        # if current_rate > self.get_mk_sl(trade):
        #     return None

        dcas = self.get_dca_list(trade)
        if len(dcas) > 0 and current_rate >= (dcas[-1] * 0.99):
            return None

        # Získání posledního thresholdu pro daný kryptoměnový pár
        last_threshold = self.thresholds.get(trade.pair, 0.01)  # Výchozí hodnota thresholdu v procentech
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
                # Vypočítání nové částky pro DCA a nového thresholdu
                available_stake_amount = self.wallets.get_available_stake_amount()
                new_dca_amount, new_threshold = self.calculate_dca_amount_and_threshold(available_stake_amount,
                                                                                        last_threshold)
                # Uložení nového thresholdu do slovníku
                self.thresholds[trade.pair] = new_threshold

                logging.info(
                    f"{current_time} - DCA triggered for {trade.pair}. Adjusting position with additional stake {new_dca_amount}")
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
