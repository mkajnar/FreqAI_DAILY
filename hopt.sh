#!/bin/bash

# 🔥 HYPEROPT SCALPORGY STRATEGY
# ========================================
echo "🔥 HYPEROPT SCALPORGY STRATEGY"
echo "========================================="
echo "Strategie:       ScalpOrgyStrategySolid"
echo "Data:            20250101 → 20260207"
echo "Timeframe:       5m"
echo "Páry:            BTC/USDT:USDT ETH/USDT:USDT APT/USDT:USDT XMR/USDT:USDT RIVER/USDT:USDT"
echo "EPOCHS:          10000"
echo "========================================="

# Spuštění hyperopt v Docker
make hyperopt-all-docker \
    STRATEGY=ScalpOrgyStrategySolid \
    EPOCHS=10000 \
    PAIRS="BTC/USDT:USDT ETH/USDT:USDT APT/USDT:USDT XMR/USDT:USDT RIVER/USDT:USDT" \
    DATA_START=20250101 \
    DATA_END=20260207

echo ""
echo "📊 Výsledky hyperopt jsou v: user_data/hyperopt_results/"
echo "📈 Zobrazit výsledky: make list"</content>
<parameter name="filePath">hopt.sh