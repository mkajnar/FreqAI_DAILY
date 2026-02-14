# FreqAI Daily Trading Bot

Automatizovaný trading bot pro FreqTrade s Kubernetes nasazením.

## Požadavky

- Kubernetes cluster (k3s)
- FreqTrade Operator nainstalovaný v clusteru
- kubectl nakonfigurovaný pro přístup ke clusteru

## Nasazení Botů

### 1. Příprava - Cordon vps uzlu

Protože FreqTrade operátor ignoruje `nodeSelector`, musíme ručně zabránit schedulování na `vps` uzel:

```bash
kubectl cordon vps
```

### 2. Spuštění deploymentu

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
TIMEFRAME=5m ./autogen_daily.sh
```

Dostupné timeframy: `5m`, `15m`, `1h`, `4h`, `1d`

### 3. Povolení vps uzlu (po nasazení)

```bash
kubectl uncordon vps
```

### 4. Ověření

```bash
kubectl get pods -l app.kubernetes.io/name=dailybuy-5m
kubectl logs -l app.kubernetes.io/name=dailybuy-5m --tail=20
```

## Důležité Poznámky

- **NodeSelector nefunguje**: FreqTrade operátor ignoruje `nodeSelector` v Bot CRD
- **Perzistentní data**: Databáze se ukládá do `/mnt/ft/<bot-name>` na uzlu `debian`
- **Pokud bot běží na vps**: Smažte pod, Kubernetes ho znovu vytvoří na `debian`
- **Data se nesynchronizují**: Vždy používejte `kubectl cordon vps` před nasazením

## Zastavení Botů

```bash
./stop_bots_daily.sh all
```

## URL Botů

Po nasazení jsou boty dostupné na:
- dailybuy-5m: http://127.0.0.1:30400/trade
- dailybuy-15m: http://127.0.0.1:30401/trade
- dailybuy-1h: http://127.0.0.1:30402/trade
- dailybuy-4h: http://127.0.0.1:30403/trade
- dailybuy-1d: http://127.0.0.1:30404/trade

## Konfigurace

- `autogen_daily.sh` - Hlavní deployment skript
- `stop_bots_daily.sh` - Zastavení botů
- `Makefile` - Hyperopt a backtesting příkazy

## Workflow Orchestration

Viz [AGENTS.md](AGENTS.md) pro podrobné workflow guidelines.
