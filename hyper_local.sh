#!/bin/bash
# DailyBuyStrategy3_5_JPA Hyperopt - 5m timeframe
# Usage: ./hyper_local.sh [epochs] [timerange]

EPOCHS=${1:-1000}
TIMERANGE=${2:-20260101-20260131}
STRATEGY="DailyBuyStrategy3_5_JPA"
TIMEFRAME="5m"
CONFIG="user_data/config_dailybuy_5m.json"

echo "Starting hyperopt..."
echo "  Strategy: $STRATEGY"
echo "  Timeframe: $TIMEFRAME"
echo "  Timerange: $TIMERANGE"
echo "  Epochs: $EPOCHS"

cd /mnt/c/Sources/FreqAIGen

# Copy strategy to user_data/strategies before hyperopt
cp DailyBuyStrategy3_5_JPA.py user_data/strategies/
cp DailyBuyStrategy3_5_JPA.py user_data/strategies/DailyBuyStrategy3_5_JPA.py.backup 2>/dev/null || true

docker run --rm \
  -v $(pwd)/user_data:/freqtrade/user_data \
  --user 1000:1000 \
  freqtradeorg/freqtrade:latest \
  hyperopt \
  --random-state 100 \
  --hyperopt-loss OnlyProfitHyperOptLoss \
  --strategy $STRATEGY \
  --strategy-path /freqtrade/user_data/strategies \
  --timeframe $TIMEFRAME \
  -c $CONFIG \
  --space buy sell roi stoploss trailing \
  --timerange $TIMERANGE \
  -e $EPOCHS \
  -j 24

echo "Hyperopt complete."
