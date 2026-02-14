#!/usr/bin/env bash

# Stops (deletes) Kubernetes resources for Daily boty
# Usage:
#   ./stop_bots_daily.sh               # deletes all dailybuy-* bots from K8S
#   ./stop_bots_daily.sh dailybuy-5m   # deletes only dailybuy-5m bot
#   ./stop_bots_daily.sh all           # deletes all dailybuy-* bots

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG=${KUBECONFIG:-$HOME/.kube/config}
K8S_NODE=${K8S_NODE:-127.0.0.1}
NAMESPACE=${NAMESPACE:-default}

BOT_PATTERN="${1:-all}"

ALL_BOTS="dailybuy-5m dailybuy-15m dailybuy-1h dailybuy-4h dailybuy-1d"

echo "Zastavování Daily botů na ${K8S_NODE}..."

# Determine which bots to stop
if [ "$BOT_PATTERN" = "all" ]; then
    BOTS_TO_STOP=($ALL_BOTS)
elif [ -n "$BOT_PATTERN" ]; then
    # Check if it's a valid bot name
    if echo "$ALL_BOTS" | grep -qw "$BOT_PATTERN"; then
        BOTS_TO_STOP=("$BOT_PATTERN")
    else
        echo "❌ Neznámý bot: $BOT_PATTERN"
        echo "Použij: dailybuy-5m, dailybuy-15m, dailybuy-1h, dailybuy-4h, dailybuy-1d, nebo all"
        exit 1
    fi
else
    BOTS_TO_STOP=($ALL_BOTS)
fi

processed=0
success=0
failed=0

for bot in "${BOTS_TO_STOP[@]}"; do
    ((processed++))
    echo "Mazání prostředků pro: $bot"

    # Delete deployment
    if KUBECONFIG="$KUBECONFIG" kubectl delete -n "$NAMESPACE" "deploy/$bot" --ignore-not-found=true 2>/dev/null; then
        ((success++))
        echo "   ✓ Deployment $bot smazán"
    else
        echo "   ⚠️ Deployment $bot neexistuje"
    fi

    # Delete service
    if KUBECONFIG="$KUBECONFIG" kubectl delete -n "$NAMESPACE" "svc/${bot}-service" --ignore-not-found=true 2>/dev/null; then
        echo "   ✓ Service ${bot}-service smazán"
    fi

    # Delete secret
    if KUBECONFIG="$KUBECONFIG" kubectl delete -n "$NAMESPACE" "secret/${bot}-secret" --ignore-not-found=true 2>/dev/null; then
        echo "   ✓ Secret ${bot}-secret smazán"
    fi

    echo ""
done

echo "Zpracováno: $processed | Úspěšně: $success"

if [[ $failed -gt 0 ]]; then
    exit 1
fi
exit 0
