"""
DailyBuyStrategy3_5_JPA - Multi-timeframe Daily Buy Bot
======================================================

Template for generating timeframe-specific variants.
This is NOT meant to be used directly as a strategy.

Available variants:
- DailyBuyStrategy3_5_JPA_5m (5-minute candles)
- DailyBuyStrategy3_5_JPA_15m (15-minute candles)
- DailyBuyStrategy3_5_JPA_1h (hourly candles)
- DailyBuyStrategy3_5_JPA_4h (4-hour candles)
- DailyBuyStrategy3_5_JPA_1d (daily candles)

Each variant has identical logic but optimized leverage and parameters
based on timeframe volatility characteristics.
"""

__version__ = "3.5"
__author__ = "JPA"
__timeframe__ = "{TIMEFRAME}"
__leverage__ = {LEVERAGE}
