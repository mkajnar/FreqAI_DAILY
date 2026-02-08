#!/usr/bin/env bash

# Stops (deletes) Kubernetes resources for Daily boty
# Usage:
#   ./stop_bots_daily.sh               # deletes all dailybuy-* bots from K8S

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG=${KUBECONFIG:-$HOME/.kube/config}
K8S_NODE=${K8S_NODE:-188.165.193.142}
NAMESPACE=${NAMESPACE:-default}

echo "Zastavování Daily botů na ${K8S_NODE}..."

# Delete all dailybuy-* deployments
processed=0
success=0
failed=0

# Get all dailybuy pods
for bot in dailybuy-5m dailybuy-15m dailybuy-1h dailybuy-4h dailybuy-1d; do
    ((processed++))
    echo "Mazání prostředků pro: $bot"

    # Delete deployment/namespace
    if KUBECONFIG="$KUBECONFIG" kubectl delete -n "$NAMESPACE" "deploy/$bot" --ignore-not-found=true 2>/dev/null; then
        ((success++))
    else
        echo "⚠️ Deployment $bot neexistuje nebo chyba"
    fi

    # Delete service
    if KUBECONFIG="$KUBECONFIG" kubectl delete -n "$NAMESPACE" "svc/${bot}-service" --ignore-not-found=true 2>/dev/null; then
        :
    fi

    # Delete secret
    if KUBECONFIG="$KUBECONFIG" kubectl delete -n "$NAMESPACE" "secret/${bot}-secret" --ignore-not-found=true 2>/dev/null; then
        :
    fi

    echo ""
done

echo "Zpracováno: $processed | Úspěšně: $success"

if [[ $failed -gt 0 ]]; then
    exit 1
fi
exit 0
