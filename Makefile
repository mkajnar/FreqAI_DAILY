# ============================================================================
# FreqTrade Kubernetes Makefile - DailyBuyStrategy3_5_JPA PERPETUAL FUTURES Edition
# Optimalizován pro PERPETUAL FUTURES Trading (BTC/USDT:USDT, ETH/USDT:USDT)
# Bot: daily_5m, daily_15m, daily_1h, daily_4h, daily_1d
# Strategie: DailyBuyStrategy3_5_JPA
# ============================================================================

# Defaultní proměnné
DATA_START?=20260101
DATA_END?=20260125
HYPEROPT_START?=20260101
HYPEROPT_END?=20260110
BACKTEST_START?=20260110
BACKTEST_END?=20260125
TIMEFRAME?=5m
CONFIG?=/tmp/backtest_config.json
STRATEGY?=DailyBuyStrategy3_5_JPA
EPOCHS?=1000
PAIR?=BTC/USDT:USDT
PAIRS?=BTC/USDT:USDT ETH/USDT:USDT
NAMESPACE?=default

DOCKER_IMAGE?=freqtradeorg/freqtrade:latest
DOCKER_BUILD_IMAGE?=freqtrade-daily:latest
DOCKERFILE?=Dockerfile
DOCKER_CONTAINER?=freqtrade-daily
DOCKER_USER?=1000:1000
DOCKER_WORKDIR?=/freqtrade

GREEN=\033[0;32m
YELLOW=\033[0;33m
RED=\033[0;31m
NC=\033[0m

.PHONY: help all \
	docker-pull docker-build docker-build-push docker-run-shell docker-hyperopt \
	prepare-docker prepare-docker-hyperopt download-data \
	backtest backtest-docker hyperopt hyperopt-docker \
	deploy stop restart status logs shell \
	daily-workflow daily-deploy daily-stop daily-status

# ============================================================================
# HELP
# ============================================================================

help:
	@echo ""
	@echo "🤖 FreqTrade Daily Strategy Makefile"
	@echo "====================================="
	@echo ""
	@echo "DOSTUPNÉ CÍLE:"
	@echo "  make help                 - Zobraz tuto nápovědu"
	@echo "  make docker-pull          - Stáhni Docker image"
	@echo "  make docker-build         - Buildni vlastní Docker image"
	@echo "  make docker-build-push    - Buildni a pushni do registry"
	@echo "  make docker-run-shell     - Spusť interaktivní shell v Dockeru"
	@echo ""
	@echo "  make prepare-docker       - Připrav Docker (config + strategie)"
	@echo "  make download-data        - Stáhni tržní data pro hyperopt"
	@echo ""
	@echo "  make backtest             - Lokální backtest"
	@echo "  make backtest-docker      - Backtest v Dockeru"
	@echo ""
	@echo "  make hyperopt             - Lokální hyperopt"
	@echo "  make hyperopt-docker      - Hyperopt v Dockeru"
	@echo ""
	@echo "  make deploy               - Generuj a nasad' Daily boty na K8S"
	@echo "  make stop                 - Zastav a smaž Daily boty z K8S"
	@echo "  make status               - Zobraz stav Daily botů"
	@echo "  make logs                 - Zobraz logy botů"
	@echo "  make shell                - Připoj se k bota"
	@echo ""
	@echo "  make daily-workflow       - Kompletní workflow: hyperopt -> backtest -> deploy"
	@echo ""
	@echo "PROMĚNNÉ:"
	@echo "  TIMEFRAME=$(TIMEFRAME)    - Timeframe (5m, 15m, 1h, 4h, 1d)"
	@echo "  STRATEGY=$(STRATEGY)      - Název strategie"
	@echo "  PAIRS=$(PAIRS)            - Trading pairs"
	@echo "  EPOCHS=$(EPOCHS)          - Počet epochs pro hyperopt"
	@echo ""

# ============================================================================
# DOCKER TARGETS
# ============================================================================

docker-pull:
	@echo "$(YELLOW)Stahování FreqTrade Docker image...$(NC)"
	@docker pull $(DOCKER_IMAGE)
	@echo "$(GREEN)Image stažen: $(DOCKER_IMAGE)$(NC)"

docker-build:
	@echo "$(YELLOW)Build Docker image $(DOCKER_BUILD_IMAGE)...$(NC)"
	@docker build -t $(DOCKER_BUILD_IMAGE) -f $(DOCKERFILE) .
	@echo "$(GREEN)Image vytvořen: $(DOCKER_BUILD_IMAGE)$(NC)"

docker-build-push: docker-build
	@echo "$(YELLOW)Push Docker image do registry...$(NC)"
	@docker tag $(DOCKER_BUILD_IMAGE) $(DOCKER_BUILD_IMAGE)
	@docker push $(DOCKER_BUILD_IMAGE) || echo "$(YELLOW)Push selhal - pravděpodobně není přihlášení do registry$(NC)"
	@echo "$(GREEN)Image pushnut: $(DOCKER_BUILD_IMAGE)$(NC)"

docker-run-shell:
	@echo "$(YELLOW)Spouštění Docker kontejneru...$(NC)"
	@docker run --rm -it \
		-v $(PWD)/user_data:/freqtrade/user_data \
		-v $(PWD):/freqtrade/current \
		--user $(DOCKER_USER) \
		$(DOCKER_IMAGE) bash

docker-hyperopt:
	@echo "$(YELLOW)Příprava Docker pro hyperopt...$(NC)"
	@docker run --rm -it \
		-v $(PWD)/user_data:/freqtrade/user_data \
		-v $(PWD):/freqtrade/current \
		--user $(DOCKER_USER) \
		$(DOCKER_IMAGE) bash -c "echo 'Docker připraven pro hyperopt'"

prepare-docker:
	@echo "$(YELLOW)Příprava prostředí (config + strategie)...$(NC)"
	@mkdir -p user_data/strategies
	@mkdir -p user_data/hyperopts
	@cp DailyBuyStrategy3_5_JPA_TEMPLATE.py user_data/strategies/DailyBuyStrategy3_5_JPA_TEMPLATE.py
	@if [ -f "DailyBuyStrategy3_5_JPA.json" ]; then \
		cp DailyBuyStrategy3_5_JPA.json user_data/; \
	fi
	@echo "$(GREEN)prostředí připraveno$(NC)"

prepare-docker-hyperopt: prepare-docker
	@echo "$(YELLOW)Příprava hyperopt configu...$(NC)"
	@python3 generate_hyperopt_config.py ./user_data/config.json "$(PAIRS)" || true

download-data:
	@echo "$(YELLOW)Stahování dat ($(PAIRS), TF=$(TIMEFRAME))...$(NC)"
	@docker run --rm \
		-v $(PWD)/user_data:/freqtrade/user_data \
		--user $(DOCKER_USER) \
		$(DOCKER_IMAGE) \
		download-data \
		--exchange bybit \
		--pairs $(PAIRS) \
		--timerange $(HYPEROPT_START)-$(HYPEROPT_END) \
		--timeframe $(TIMEFRAME) \
		-c /freqtrade/user_data/config.json || true
	@echo "$(GREEN)Data stažena$(NC)"

# ============================================================================
# BACKTEST TARGETS
# ============================================================================

backtest:
	@echo "$(YELLOW)Spouštění backtestu ($(STRATEGY), TF=$(TIMEFRAME))...$(NC)"
	@python3 -m freqtrade backtesting \
		--config user_data/config.json \
		--strategy $(STRATEGY) \
		--strategy-path user_data/strategies \
		--timeframe $(TIMEFRAME) \
		--timerange $(BACKTEST_START)-$(BACKTEST_END) \
		--export-trades || true

backtest-docker:
	@echo "$(YELLOW)Spouštění backtestu v Dockeru...$(NC)"
	@docker run --rm \
		-v $(PWD)/user_data:/freqtrade/user_data \
		-v $(PWD):/freqtrade/current \
		--user $(DOCKER_USER) \
		$(DOCKER_IMAGE) \
		backtesting \
		--config /freqtrade/user_data/config.json \
		--strategy $(STRATEGY) \
		--strategy-path /freqtrade/user_data/strategies \
		--timeframe $(TIMEFRAME) \
		--timerange $(BACKTEST_START)-$(BACKTEST_END) \
		--export-trades || true

# ============================================================================
# HYPEROPT TARGETS
# ============================================================================

hyperopt:
	@echo "$(YELLOW)Spouštění hyperoptu ($(STRATEGY), TF=$(TIMEFRAME), epochs=$(EPOCHS))...$(NC)"
	@python3 -m freqtrade hyperopt \
		--config user_data/config.json \
		--strategy $(STRATEGY) \
		--strategy-path user_data/strategies \
		--timeframe $(TIMEFRAME) \
		--timerange $(HYPEROPT_START)-$(HYPEROPT_END) \
		--epochs $(EPOCHS) \
		--hyperopt-loss ShortHyperOptLoss \
		--min-trades 3 || true

hyperopt-docker:
	@echo "$(YELLOW)Spouštění hyperoptu v Dockeru...$(NC)"
	@docker run --rm \
		-v $(PWD)/user_data:/freqtrade/user_data \
		-v $(PWD):/freqtrade/current \
		--user $(DOCKER_USER) \
		$(DOCKER_IMAGE) \
		hyperopt \
		--config /freqtrade/user_data/config.json \
		--strategy $(STRATEGY) \
		--strategy-path /freqtrade/user_data/strategies \
		--timeframe $(TIMEFRAME) \
		--timerange $(HYPEROPT_START)-$(HYPEROPT_END) \
		--epochs $(EPOCHS) \
		--hyperopt-loss ShortHyperOptLoss \
		--min-trades 3 || true

# ============================================================================
# KUBERNETES TARGETS
# ============================================================================

deploy:
	@echo "$(YELLOW)Generování a nasazení Daily botů...$(NC)"
	@chmod +x autogen_daily.sh
	@./autogen_daily.sh

deploy-dry:
	@echo "$(YELLOW)Generování YAML bez nasazení...$(NC)"
	@DEPLOY=false ./autogen_daily.sh

stop:
	@echo "$(YELLOW)Zastavování Daily botů...$(NC)"
	@chmod +x stop_bots_daily.sh
	@./stop_bots_daily.sh

restart: stop deploy
	@echo "$(GREEN)Daily boty restartovány$(NC)"

status:
	@echo "$(YELLOW)Stav Daily botů...$(NC)"
	@kubectl get pods -n $(NAMESPACE) -l 'app.kubernetes.io/name~^daily' 2>/dev/null || echo "kubectl nenalezen nebo žádné boty"
	@kubectl get svc -n $(NAMESPACE) 2>/dev/null | grep daily || echo ""

logs:
	@echo "$(YELLOW)Logy Daily botů...$(NC)"
	@kubectl logs -n $(NAMESPACE) -l 'app.kubernetes.io/name~^daily' --tail=50 2>/dev/null || echo ""

shell:
	@echo "$(YELLOW)Připojování k shellu bota...$(NC)"
	@POD_NAME=$$(kubectl get pods -n $(NAMESPACE) -l 'app.kubernetes.io/name=daily_5m' -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -n "$$POD_NAME" ]; then \
		kubectl exec -it $$POD_NAME -n $(NAMESPACE) -- /bin/bash; \
	else \
		echo "Bot daily_5m nenalezen"; \
	fi

# ============================================================================
# WORKFLOW TARGETS
# ============================================================================

daily-workflow: prepare-docker download-data hyperopt-docker backtest-docker deploy
	@echo ""
	@echo "$(GREEN)════════════════════════════════════════════════════════════════$(NC)"
	@echo "$(GREEN)✓ DAILY WORKFLOW DOKONČEN$(NC)"
	@echo "$(GREEN)════════════════════════════════════════════════════════════════$(NC)"
