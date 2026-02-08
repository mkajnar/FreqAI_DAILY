#!/usr/bin/env bash

# Stops (deletes) Kubernetes resources defined in each subdirectory of the
# provided bots_daily_* directory by running `kubectl delete -f <subdir>`.
#
# Usage:
#   ./stop_bots_daily.sh               # uses default pattern "bots_daily_*"
#   ./stop_bots_daily.sh /path/to/bots_daily_5m # specify custom directory

set -uo pipefail

BOTS_DIR_PATTERN="${1:-bots_daily_*}"
KUBECONFIG=${KUBECONFIG:-$HOME/.kube/config}
K8S_NODE=${K8S_NODE:-188.165.193.142}

# Find all matching directories
mapfile -t BOT_DIRS < <(find "${SCRIPT_DIR:-.}" -maxdepth 1 -mindepth 1 -type d -name "$BOTS_DIR_PATTERN" | sort)

if [ ${#BOT_DIRS[@]} -eq 0 ]; then
  echo "Chyba: Nenalezeny žádné složky odpovídající vzoru: $BOTS_DIR_PATTERN" >&2
  exit 1
fi

processed=0
success=0
failed=0
any=false

for dir in "${BOT_DIRS[@]}"; do
  any=true
  ((processed++))
  echo "Mazání prostředků ve složce: $dir"
  if KUBECONFIG="${KUBECONFIG}" kubectl delete -f "$dir" 2>/dev/null; then
    ((success++))
  else
    echo "⚠️ Neúspěšné/neexistující mazání ve složce: $dir" >&2
    ((failed++))
  fi
  echo
done

if [[ "$any" == false ]]; then
  echo "Ve složce '$BOTS_DIR_PATTERN' nebyly nalezeny žádné podsložky." >&2
  exit 1
fi

echo "Zpracováno podsložek: $processed | Úspěšně: $success | Chyby: $failed"

if [[ $failed -gt 0 ]]; then
  exit 1
fi
exit 0
