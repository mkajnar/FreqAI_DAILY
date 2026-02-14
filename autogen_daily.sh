#!/bin/bash
# -----------------------------------------------------------------------------
# 🤖 AUTO-DEPLOYER: DailyBuyStrategy3_5_JPA EDITION
# Účel: Vygenerovat a NASADIT všechny Daily boty pro různé timeframy.
# Template: DailyBuyStrategy3_5_JPA_TEMPLATE.py
# -----------------------------------------------------------------------------
set -euo pipefail

# K8S konfigurace
KUBECONFIG=${KUBECONFIG:-$HOME/.kube/config}
K8S_NODE=${K8S_NODE:-127.0.0.1}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/DailyBuyStrategy3_5_JPA_TEMPLATE.py"
DB_BASE_HOST_PATH="${DB_BASE_HOST_PATH:-/mnt/ft}"

# Přepínače nasazení
# DEPLOY=true  => provede kubectl apply (výchozí)
# DEPLOY=false => pouze generuje YAML soubory
DEPLOY=${DEPLOY:-true}

# Konstantní credentials (načítají se z prostředí nebo jsou placeholdery)
EXCHANGE_KEY="${EXCHANGE_KEY:-K}"
EXCHANGE_SECRET="${EXCHANGE_SECRET:-S}"
API_PASSWORD="${API_PASSWORD:-freqtrade}"
API_USERNAME="${API_USERNAME:-freqtrade}"

# Základní NodePort
BASE_NODEPORT=30400

# Summary accumulator
SUMMARY=""

echo "========================================"
echo "🤖 DAILY BUY AUTO-DEPLOYER"
echo "   Generuji a ${DEPLOY:+nasazuji }boty pro DailyBuyStrategy..."
echo "========================================"

# --- VALIDACE ---
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "❌ ERROR: Nenalezen soubor šablony: $TEMPLATE_FILE"
    exit 1
fi

# Konfigurace timeframe - složka pro každý timeframe
declare -A TIMEFRAME_CONFIG
TIMEFRAME_CONFIG["bots_dailybuy_5m"]="5m"
TIMEFRAME_CONFIG["bots_dailybuy_15m"]="15m"
TIMEFRAME_CONFIG["bots_dailybuy_1h"]="1h"
TIMEFRAME_CONFIG["bots_dailybuy_4h"]="4h"
TIMEFRAME_CONFIG["bots_dailybuy_1d"]="1d"

# Filtr pro specifický timeframe (pokud je nastaven)
TIMEFRAME_FILTER=${TIMEFRAME:-all}

# --- HELPER FUNKCE ---
b64encode() { echo -n "$1" | base64 -w 0; }

# Injektáž hyperopt parametrů do dočasného souboru strategie
inject_params_into_temp() {
    local temp_strategy=$1
    local params_json=$2
    
    if [ ! -f "$params_json" ]; then
        return 0
    fi
    
    python3 - <<PYSCRIPT
import json
import sys
import re

try:
    with open("$params_json", 'r') as f:
        data = json.load(f)
        params_data = data.get('parameters', data.get('params', {}))
except Exception as e:
    sys.exit(0)

if not params_data:
    sys.exit(0)

try:
    with open("$temp_strategy", 'r') as f:
        content = f.read()
except Exception as e:
    sys.exit(1)

buy_params = params_data.get("buy", {})
sell_params = params_data.get("sell", {})
roi_params = params_data.get("roi", {})

if roi_params:
    roi_dict = "{" + ", ".join(
        f'"{k}": {v}' for k, v in sorted(roi_params.items())
    ) + "}"
    pattern = r'minimal_roi\s*=\s*\{[^}]*\}'
    replacement = f'minimal_roi = {roi_dict}'
    content = re.sub(pattern, replacement, content)

if buy_params:
    for param_name, param_value in buy_params.items():
        pattern = (
            rf'({re.escape(param_name)}\s*=\s*'
            r'(?:Decimal|Int|Categorical)Parameter\([^)]*'
            r'default\s*=\s*)[^,\)]+(\s*[,\)])'
        )
        replacement = rf'\g<1>{param_value}\g<2>'
        content = re.sub(pattern, replacement, content)

if sell_params:
    for param_name, param_value in sell_params.items():
        pattern = (
            rf'({re.escape(param_name)}\s*=\s*'
            r'(?:Decimal|Int|Categorical)Parameter\([^)]*'
            r'default\s*=\s*)[^,\)]+(\s*[,\)])'
        )
        replacement_value = str(param_value)
        if isinstance(param_value, str):
            replacement_value = f'"{param_value}"'
        replacement = rf'\g<1>{replacement_value}\g<2>'
        content = re.sub(pattern, replacement, content)

with open("$temp_strategy", 'w') as f:
    f.write(content)
PYSCRIPT
}

PORT_OFFSET=0

for BOT_DIR_NAME in "${!TIMEFRAME_CONFIG[@]}"; do
    BOT_DIR_PATH="${SCRIPT_DIR}/${BOT_DIR_NAME}"
    TIMEFRAME="${TIMEFRAME_CONFIG[$BOT_DIR_NAME]}"
    BOT_NAME="dailybuy-${TIMEFRAME}"

    # Filtr pro specifický timeframe
    if [ "$TIMEFRAME_FILTER" != "all" ] && [ "$TIMEFRAME_FILTER" != "$TIMEFRAME" ]; then
        continue
    fi

    if [ ! -d "$BOT_DIR_PATH" ]; then
        echo "   ⚠️  Složka neexistuje: $BOT_DIR_PATH - vytvářím..."
        mkdir -p "$BOT_DIR_PATH"
    fi

    echo "----------------------------------------"
    echo "🔍 Zpracovávám: $BOT_NAME (TF=$TIMEFRAME)"

    # Konfigurace pro PERPETUAL FUTURES
    NAMESPACE="default"
    STAKE_AMOUNT="unlimited"
    FIAT_DISPLAY="USD"
    PAIRS_INPUT="BTC/USDT:USDT,ETH/USDT:USDT"
    MAX_OPEN_TRADES=5
    BALANCE_RATIO=0.95
    MARGIN_MODE="isolated"
    STOPLOSS_ON_EXCHANGE="true"
    USE_EXIT_SIGNAL="true"
    TRADING_MODE="futures"
    
    STARTUP_CANDLES=100

    # LEVERAGE pro PERPETUAL FUTURES (vyšší pro futures)
    case "$TIMEFRAME" in
        5m) LEVERAGE=10 ;;
        15m) LEVERAGE=10 ;;
        1h) LEVERAGE=10 ;;
        4h) LEVERAGE=5 ;;
        1d) LEVERAGE=3 ;;
        *) LEVERAGE=10 ;;
    esac

    echo "   ⚙️  Parametry: TF=$TIMEFRAME, LEV=$LEVERAGE"

    # Přiřazení portu podle pořadí
    CURRENT_NODEPORT=$((BASE_NODEPORT + PORT_OFFSET))

    JWT_SECRET=$(openssl rand -hex 32)
    SECRET_NAME="${BOT_NAME}-secret"

    # pair_whitelist YAML blok
    PAIRS_YAML=""
    IFS=',' read -ra PAIRS_ARRAY <<< "$PAIRS_INPUT"
    for pair in "${PAIRS_ARRAY[@]}"; do
        PAIRS_YAML+="        - ${pair}\n"
    done

    INCLUDE_TIMEFRAMES_YAML="          - ${TIMEFRAME}"

    # 3) PŘÍPRAVA STRATEGIE (dočasný soubor)
    TEMP_STRATEGY_FILE="${BOT_DIR_PATH}/temp_strategy_gen.py"
    cp "$TEMPLATE_FILE" "$TEMP_STRATEGY_FILE"

    # Injekce hyperopt parametrů (pokud existuje)
    HYPEROPT_PARAMS_FILE="${SCRIPT_DIR}/DailyBuyStrategy3_5_JPA.json"
    if [ -f "$HYPEROPT_PARAMS_FILE" ]; then
        inject_params_into_temp "$TEMP_STRATEGY_FILE" "$HYPEROPT_PARAMS_FILE"
    fi

    # Nahrazení placeholderů
    sed -i "s|{{LEVERAGE}}|${LEVERAGE}|g" "$TEMP_STRATEGY_FILE"
    sed -i "s|{{CLASS_NAME}}|DailyBuyStrategy3_5_JPA|g" "$TEMP_STRATEGY_FILE"

    STRATEGY_CLASS_NAME=$(grep "class .*\(IStrategy\)" "$TEMP_STRATEGY_FILE" | head -1 | sed 's/class \([a-zA-Z0-9_]*\)(IStrategy).*/\1/') || true
    if [ -z "${STRATEGY_CLASS_NAME:-}" ]; then
        STRATEGY_CLASS_NAME=$(grep -o "class [a-zA-Z0-9_]*" "$TEMP_STRATEGY_FILE" | head -1 | awk '{print $2}') || true
    fi
    if [ -z "${STRATEGY_CLASS_NAME:-}" ]; then
        STRATEGY_CLASS_NAME="DailyBuyStrategy3_5_JPA"
    fi

    # 4) ADRESÁŘE
    mkdir -p "${BOT_DIR_PATH}/data"
    mkdir -p /mnt/ft_etc
    mkdir -p "${DB_BASE_HOST_PATH}/${BOT_NAME}"
    chmod -R 777 "${BOT_DIR_PATH}/data" 2>/dev/null || true
    chmod -R 777 /mnt/ft_etc 2>/dev/null || true
    chmod -R 777 "${DB_BASE_HOST_PATH}/${BOT_NAME}" 2>/dev/null || true

    # 5) GENERACE bot.yaml
     cat > "${BOT_DIR_PATH}/bot.yaml" <<EOF
apiVersion: freqtrade.io/v1alpha1
kind: Bot
metadata:
  name: ${BOT_NAME}
  namespace: ${NAMESPACE}
spec:
  image:
    repository: freqtradeorg/freqtrade
    tag: develop
  pvc:
    enabled: false
  deployment:
    env: []
    nodeSelector:
      kubernetes.io/hostname: debian
    resources:
      requests:
        cpu: "1000m"
        memory: "2Gi"
      limits:
        cpu: "2000m"
        memory: "4Gi"
    volumes:
      - name: user-data
        hostPath:
          path: ${SCRIPT_DIR}/${BOT_DIR_NAME}/data
          type: DirectoryOrCreate
      - name: database-dir
        hostPath:
          path: ${DB_BASE_HOST_PATH}/${BOT_NAME}
          type: DirectoryOrCreate
      - name: dshm
        emptyDir:
          medium: Memory
    volumeMounts:
      - name: user-data
        mountPath: /freqtrade/user_data
      - name: database-dir
        mountPath: /freqtrade/db_persist
      - name: dshm
        mountPath: /dev/shm
  exchange: bybit
  database: sqlite:////freqtrade/db_persist/database.db
  config:
    initial_state: running
    max_open_trades: ${MAX_OPEN_TRADES}
    stake_currency: USDT
    stake_amount: "${STAKE_AMOUNT}"
    tradable_balance_ratio: ${BALANCE_RATIO}
    fiat_display_currency: "${FIAT_DISPLAY}"
    timeframe: ${TIMEFRAME}
    dry_run: true
    dry_run_wallet: 10000
    trading_mode: ${TRADING_MODE}
    margin_mode: ${MARGIN_MODE}
    leverage:
      - side: long
        leverage: ${LEVERAGE}
      - side: short
        leverage: ${LEVERAGE}
    use_exit_signal: ${USE_EXIT_SIGNAL}
    unfilledtimeout:
      entry: 30
      exit: 30
    
    entry_pricing:
      price_side: other
      use_order_book: true
      order_book_top: 1
    exit_pricing:
      price_side: other
      use_order_book: true
      order_book_top: 1
      
    order_types:
      entry: market
      exit: market
      stoploss: market
      stoploss_on_exchange: ${STOPLOSS_ON_EXCHANGE}
      
    exchange:
      pair_whitelist:
$(echo -e "$PAIRS_YAML")
    
    pairlists:
      - method: StaticPairList

    telegram:
      enabled: false

  api:
    enabled: true
    port: 8081
  secrets:
    api:
      username:
        secretKeyRef:
          name: ${SECRET_NAME}
          key: api_username
      password:
        secretKeyRef:
          name: ${SECRET_NAME}
          key: api_password
      wsToken:
        secretKeyRef:
          name: ${SECRET_NAME}
          key: jwt_secret_key
    exchange:
      key:
        secretKeyRef:
          name: ${SECRET_NAME}
          key: exchange_key
      secret:
        secretKeyRef:
          name: ${SECRET_NAME}
          key: exchange_secret

  strategy:
    name: ${STRATEGY_CLASS_NAME}
    source: |
EOF

    # Část 2: Strategie (odsazená a přilepená nakonec)
    sed 's/^[[:space:]]*$//' "$TEMP_STRATEGY_FILE" | sed 's/[[:space:]]*$//' | sed 's/^/      /' >> "${BOT_DIR_PATH}/bot.yaml"

    # Úklid dočasné strategie
    rm -f "$TEMP_STRATEGY_FILE"

    # --- SECRET.YAML ---
    cat > "${BOT_DIR_PATH}/secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: ${NAMESPACE}
data:
  api_password: $(b64encode "$API_PASSWORD")
  api_username: $(b64encode "$API_USERNAME")
  exchange_key: $(b64encode "$EXCHANGE_KEY")
  exchange_secret: $(b64encode "$EXCHANGE_SECRET")
  jwt_secret_key: $(b64encode "$JWT_SECRET")
type: Opaque
EOF

    # --- SERVICE.YAML ---
    cat > "${BOT_DIR_PATH}/service.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${BOT_NAME}-service
  namespace: ${NAMESPACE}
spec:
  type: NodePort
  selector:
    app.kubernetes.io/name: ${BOT_NAME}
  ports:
    - port: 8081
      targetPort: 8081
      nodePort: ${CURRENT_NODEPORT}
EOF

    echo "   ✅ YAML vygenerován: ${BOT_DIR_PATH}"
    BOT_URL="http://${K8S_NODE}:${CURRENT_NODEPORT}/trade"
    SUMMARY+="${BOT_NAME} -> ${BOT_URL}\n"

    # 6) NASAZENÍ (volitelné)
    if [ "${DEPLOY}" = "true" ]; then
        if command -v kubectl >/dev/null 2>&1; then
            echo "   🚀 Nasazuji na ${K8S_NODE} přes kubectl apply -f ${BOT_DIR_PATH}/"
            KUBECONFIG="${KUBECONFIG}" kubectl apply -f "${BOT_DIR_PATH}/"
        else
            echo "   ⚠️ kubectl nenalezen, přeskočeno nasazení."
        fi
    fi

    PORT_OFFSET=$((PORT_OFFSET + 1))

done

echo "========================================"
if [ "${DEPLOY}" = "true" ]; then
  echo "🎉 HOTOVO! Boty byly nasazeny."
else
  echo "✅ HOTOVO! YAML soubory vygenerovány (bez nasazení)."
fi
echo "========================================"

echo -e "\nVygenerované boty a jejich URL:"
if [ -n "$SUMMARY" ]; then
  echo -e "$SUMMARY"
else
  echo "(Žádné boty nenalezeny)"
fi
