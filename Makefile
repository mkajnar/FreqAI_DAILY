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

KUBECONFIG?=${HOME}/.kube/config
K8S_NODE?=188.165.193.142

DOCKER_IMAGE?=freqtradeorg/freqtrade:latest
DOCKER_BUILD_IMAGE?=freqtrade-daily:latest
DOCKERFILE?=Dockerfile
DOCKER_REGISTRY?=188.165.193.142:5000
DOCKER_REGISTRY_LOCAL?=localhost:5000
DOCKER_CONTAINER?=freqtrade-daily
DOCKER_USER?=1000:1000
DOCKER_WORKDIR?=/freqtrade

GREEN=\033[0;32m
YELLOW=\033[0;33m
RED=\033[0;31m
NC=\033[0m

.PHONY: help all \
	docker-pull docker-build docker-build-push docker-tag-registry docker-push-registry \
	docker-run-shell docker-hyperopt \
	prepare-docker prepare-docker-hyperopt download-data \
	backtest backtest-docker hyperopt hyperopt-docker \
	deploy deploy-dry deploy-5m deploy-15m deploy-1h deploy-4h deploy-1d \
	stop stop-5m stop-15m stop-1h stop-4h stop-1d stop-all \
	restart status logs shell \
	daily-workflow

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
	@echo "  make docker-build-push    - Buildni a pushni do Docker Hub (nutné: docker login)"
	@echo "  make docker-tag-registry  - Otaguje image pro K8S registry"
	@echo "  make docker-push-registry - Pushni image do K8S registry $(DOCKER_REGISTRY)"
	@echo "  make docker-registry-init - Build a push do K8S registry"
	@echo ""
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
	@echo "  make deploy               - Generuj a nasad' všechny Daily boty na K8S"
	@echo "  make deploy-dry           - Generuj YAML bez nasazení"
	@echo "  make deploy-5m            - Generuj a nasad' dailybuy-5m bota"
	@echo "  make deploy-15m           - Generuj a nasad' dailybuy-15m bota"
	@echo "  make deploy-1h            - Generuj a nasad' dailybuy-1h bota"
	@echo "  make deploy-4h            - Generuj a nasad' dailybuy-4h bota"
	@echo "  make deploy-1d            - Generuj a nasad' dailybuy-1d bota"
	@echo ""
	@echo "  make stop                - Zastav a smaž všechny Daily boty z K8S"
	@echo "  make stop-5m             - Zastav dailybuy-5m bota"
	@echo "  make stop-15m            - Zastav dailybuy-15m bota"
	@echo "  make stop-1h             - Zastav dailybuy-1h bota"
	@echo "  make stop-4h             - Zastav dailybuy-4h bota"
	@echo "  make stop-1d             - Zastav dailybuy-1d bota"
	@echo "  make stop-all            - Zastav všechny dailybuy boty"
	@echo ""
	@echo "  make status              - Zobraz stav Daily botů"
	@echo "  make logs                - Zobraz logy botů"
	@echo "  make shell               - Připoj se k bota"
	@echo ""
	@echo "  make daily-workflow       - Kompletní workflow: hyperopt -> backtest -> deploy"
	@echo ""
	@echo "PROMĚNNÉ:"
	@echo "  TIMEFRAME=$(TIMEFRAME)             - Timeframe (5m, 15m, 1h, 4h, 1d)"
	@echo "  STRATEGY=$(STRATEGY)              - Název strategie"
	@echo "  PAIRS=$(PAIRS)                    - Trading pairs"
	@echo "  EPOCHS=$(EPOCHS)                  - Počet epochs pro hyperopt"
	@echo "  K8S_NODE=$(K8S_NODE)             - K8S node (188.165.193.142)"
	@echo "  KUBECONFIG=$(KUBECONFIG)          - Cesta ke kubeconfigu"
	@echo "  DOCKER_REGISTRY=$(DOCKER_REGISTRY) - K8S Docker registry"
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
	@echo "$(YELLOW)Push Docker image do Docker Hub...$(NC)"
	@docker tag $(DOCKER_BUILD_IMAGE) $(DOCKER_BUILD_IMAGE)
	@docker push $(DOCKER_BUILD_IMAGE) || echo "$(YELLOW)Push selhal - musíš být přihlášený: docker login$(NC)"
	@echo "$(GREEN)Image $(DOCKER_BUILD_IMAGE) pushnut do Docker Hub$(NC)"

docker-tag-registry:
	@echo "$(YELLOW)Tagování image pro lokální registry $(DOCKER_REGISTRY)...$(NC)"
	@docker tag $(DOCKER_BUILD_IMAGE) $(DOCKER_REGISTRY)/$(DOCKER_BUILD_IMAGE)
	@docker tag $(DOCKER_BUILD_IMAGE) $(DOCKER_REGISTRY_LOCAL)/$(DOCKER_BUILD_IMAGE)
	@echo "$(GREEN)Image otagován pro registry$(NC)"

docker-push-registry:
	@echo "$(YELLOW)Push do lokální registry $(DOCKER_REGISTRY)...$(NC)"
	@docker push $(DOCKER_REGISTRY)/$(DOCKER_BUILD_IMAGE) || echo "$(YELLOW)Push selhal - zkontroluj připojení k registry$(NC)"
	@docker push $(DOCKER_REGISTRY_LOCAL)/$(DOCKER_BUILD_IMAGE) 2>/dev/null || echo "$(YELLOW)Local registry push skipped (možná běží jen na K8S)$(NC)"
	@echo "$(GREEN)Image pushnut do registry$(NC)"

docker-registry-init: docker-build
	@echo "$(YELLOW)Inicializace a push do K8S registry $(DOCKER_REGISTRY)...$(NC)"
	@docker tag $(DOCKER_BUILD_IMAGE) $(DOCKER_REGISTRY)/$(DOCKER_BUILD_IMAGE)
	@docker push $(DOCKER_REGISTRY)/$(DOCKER_BUILD_IMAGE)
	@echo "$(GREEN)Image $(DOCKER_BUILD_IMAGE) je nyní dostupný jako $(DOCKER_REGISTRY)/$(DOCKER_BUILD_IMAGE)$(NC)"

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
	@cp DailyBuyStrategy3_5_JPA_TEMPLATE.py user_data/strategies/
	@sed -i 's/{{CLASS_NAME}}/$(STRATEGY)/g' user_data/strategies/DailyBuyStrategy3_5_JPA_TEMPLATE.py
	@sed -i 's/{{LEVERAGE}}/10/g' user_data/strategies/DailyBuyStrategy3_5_JPA_TEMPLATE.py
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
		--export trades || true

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
		--export trades || true

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
		--hyperopt-loss SharpeHyperOptLoss \
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
		--hyperopt-loss SharpeHyperOptLoss \
		--min-trades 3 || true

# ============================================================================
# KUBERNETES TARGETS
# ============================================================================

deploy:
	@echo "$(YELLOW)Generování a nasazení všech Daily botů...$(NC)"
	@chmod +x autogen_daily.sh
	@./autogen_daily.sh

deploy-dry:
	@echo "$(YELLOW)Generování YAML bez nasazení...$(NC)"
	@DEPLOY=false ./autogen_daily.sh

deploy-5m:
	@echo "$(YELLOW)Generování a nasazení dailybuy-5m...$(NC)"
	@chmod +x autogen_daily.sh
	@TIMEFRAME=5m ./autogen_daily.sh

deploy-15m:
	@echo "$(YELLOW)Generování a nasazení dailybuy-15m...$(NC)"
	@chmod +x autogen_daily.sh
	@TIMEFRAME=15m ./autogen_daily.sh

deploy-1h:
	@echo "$(YELLOW)Generování a nasazení dailybuy-1h...$(NC)"
	@chmod +x autogen_daily.sh
	@TIMEFRAME=1h ./autogen_daily.sh

deploy-4h:
	@echo "$(YELLOW)Generování a nasazení dailybuy-4h...$(NC)"
	@chmod +x autogen_daily.sh
	@TIMEFRAME=4h ./autogen_daily.sh

deploy-1d:
	@echo "$(YELLOW)Generování a nasazení dailybuy-1d...$(NC)"
	@chmod +x autogen_daily.sh
	@TIMEFRAME=1d ./autogen_daily.sh

stop:
	@echo "$(YELLOW)Zastavování Daily botů...$(NC)"
	@chmod +x stop_bots_daily.sh
	@./stop_bots_daily.sh

stop-5m:
	@echo "$(YELLOW)Zastavování dailybuy-5m...$(NC)"
	@chmod +x stop_bots_daily.sh
	@./stop_bots_daily.sh dailybuy-5m

stop-15m:
	@echo "$(YELLOW)Zastavování dailybuy-15m...$(NC)"
	@chmod +x stop_bots_daily.sh
	@./stop_bots_daily.sh dailybuy-15m

stop-1h:
	@echo "$(YELLOW)Zastavování dailybuy-1h...$(NC)"
	@chmod +x stop_bots_daily.sh
	@./stop_bots_daily.sh dailybuy-1h

stop-4h:
	@echo "$(YELLOW)Zastavování dailybuy-4h...$(NC)"
	@chmod +x stop_bots_daily.sh
	@./stop_bots_daily.sh dailybuy-4h

stop-1d:
	@echo "$(YELLOW)Zastavování dailybuy-1d...$(NC)"
	@chmod +x stop_bots_daily.sh
	@./stop_bots_daily.sh dailybuy-1d

stop-all:
	@echo "$(YELLOW)Zastavování všech dailybuy botů...$(NC)"
	@chmod +x stop_bots_daily.sh
	@./stop_bots_daily.sh all

restart: stop deploy
	@echo "$(GREEN)Daily boty restartovány$(NC)"

status:
	@echo "$(YELLOW)Stav Daily botů na $(K8S_NODE)...$(NC)"
	@KUBECONFIG=$(KUBECONFIG) kubectl get pods -n $(NAMESPACE) -l 'app in (dailybuy-5m,dailybuy-15m,dailybuy-1h,dailybuy-4h,dailybuy-1d)' 2>/dev/null || echo "kubectl nenalezen nebo žádné boty"
	@KUBECONFIG=$(KUBECONFIG) kubectl get svc -n $(NAMESPACE) 2>/dev/null | grep dailybuy || echo ""

logs:
	@echo "$(YELLOW)Logy Daily botů na $(K8S_NODE)...$(NC)"
	@KUBECONFIG=$(KUBECONFIG) kubectl logs -n $(NAMESPACE) -l 'app in (dailybuy-5m,dailybuy-15m,dailybuy-1h,dailybuy-4h,dailybuy-1d)' --tail=50 2>/dev/null || echo ""

shell:
	@echo "$(YELLOW)Připojování k shellu bota na $(K8S_NODE)...$(NC)"
	@POD_NAME=$$(KUBECONFIG=$(KUBECONFIG) kubectl get pods -n $(NAMESPACE) -l 'app=dailybuy-5m' -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -n "$$POD_NAME" ]; then \
		KUBECONFIG=$(KUBECONFIG) kubectl exec -it $$POD_NAME -n $(NAMESPACE) -- /bin/bash; \
	else \
		echo "Bot dailybuy-5m nenalezen"; \
	fi

# ============================================================================
# WORKFLOW TARGETS
# ============================================================================

daily-workflow: prepare-docker download-data hyperopt-docker backtest-docker deploy
	@echo ""
	@echo "$(GREEN)════════════════════════════════════════════════════════════════$(NC)"
	@echo "$(GREEN)✓ DAILY WORKFLOW DOKONČEN$(NC)"
	@echo "$(GREEN)════════════════════════════════════════════════════════════════$(NC)"
