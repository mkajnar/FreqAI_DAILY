#!/bin/bash

# Hyperopt Progress Monitor
LOG_FILE=$(ls -t hyperopt_results_*.log 2>/dev/null | head -1)

if [ -z "$LOG_FILE" ]; then
    echo "❌ No hyperopt log file found"
    exit 1
fi

echo "📊 Hyperopt Progress Monitor"
echo "============================="
echo "Log file: $LOG_FILE"
echo ""

# Check if hyperopt is still running
if ps aux | grep -q "freqtrade hyperopt" | grep -v grep; then
    echo "✅ Hyperopt is RUNNING"
else
    echo "⏸️  Hyperopt appears STOPPED"
fi

echo ""
echo "Latest Progress:"
echo "================"

# Get latest epoch count
LATEST=$(tail -5 "$LOG_FILE" | grep -oP '\[\s*\d+/\d+\]' | tail -1)
if [ ! -z "$LATEST" ]; then
    echo "Epochs completed: $LATEST"
fi

# Get best result so far
BEST_PROFIT=$(grep -oP 'Best result:.*Profit: \K[0-9.%+-]+' "$LOG_FILE" | tail -1)
if [ ! -z "$BEST_PROFIT" ]; then
    echo "Best profit found: $BEST_PROFIT"
fi

# Count total lines (roughly proportional to progress)
TOTAL_LINES=$(wc -l < "$LOG_FILE")
echo "Log lines: $TOTAL_LINES"

echo ""
echo "Recent errors/warnings:"
tail -20 "$LOG_FILE" | grep -i "error\|warning" || echo "(none)"
