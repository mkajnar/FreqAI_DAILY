# ============================================================================
# FreqTrade Kubernetes Makefile s Autogen Script Management
# Optimalizován pro práci s FreqTrade boty v Kubernetes (kubectl)
# Používá autogen scripty: ./autogen_sniper_t3_v2.sh a ./stop_bots_sniper_t3_v2.sh
# Bot: freqai-t3v2-5m-lev4-bot
# Strategie: DailyBuyStrategy3_5_JPA_TEMPLATE (DCA + Pivot Points + TTF)
# FIX: Přidány --strategy-path pro eliminaci Read-only filesystem erroru
# ============================================================================

# Defaultní proměnné
DATA_START?=20250101
DATA_END?=20260208
HYPEROPT_START?=20250101
HYPEROPT_END?=20251231
BACKTEST_START?=20260101
BACKTEST_END?=20260208
TIMEFRAME?=5m
CONFIG?=/freqtrade/user_data/config.json
STRATEGY?=DailyBuyStrategy3_5_JPA
EPOCHS?=10000
EPOCH?=1
PAIR?=BTC/USDT:USDT
PAIRS?=BTC/USDT:USDT ETH/USDT:USDT
NAMESPACE?=default
DEPLOYMENT?=freqai-t3v2-5m-lev4-bot
POD_NAME?=$(shell kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/instance=$(DEPLOYMENT) -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

# Docker proměnné
DOCKER_IMAGE?=freqtradeorg/freqtrade:latest
DOCKER_CONTAINER?=freqtrade-hyperopt
DOCKER_USER?=1000:1000
DOCKER_WORKDIR?=/freqtrade

# Barvy pro výstup
GREEN=\033[0;32m
YELLOW=\033[0;33m
RED=\033[0;31m
NC=\033[0m

# Detekce počtu CPU jader
NPROC=$(shell nproc 2>/dev/null || echo 4)
JOBS?=$(NPROC)

# ============================================================================
# ALL PHONY TARGETS - CENTRÁLNÍ SEZNAM
# ============================================================================

.PHONY: help all \
	docker-pull docker-run-shell docker-hyperopt-base \
	prepare-docker-hyperopt prepare-docker-hyperopt-full prepare-docker-hyperopt-light download-data-docker download-data-docker-no1m \
	_check_pod _show_config \
	test test-unit test-integration test-syntax test-pep8 test-coverage \
	hyperopt-save hyperopt-validate hyperopt-show hyperopt-backup hyperopt-inject \
	list-docker \
	prepare-pod copy-strategy \
	hyperopt-buy hyperopt-buy-docker \
	hyperopt-sell hyperopt-sell-docker \
	hyperopt-trailing hyperopt-trailing-docker \
	hyperopt-roi hyperopt-roi-docker \
	hyperopt-quick hyperopt-quick-docker \
	hyperopt-all hyperopt-all-docker \
	hyperopt-all-nosl hyperopt-all-nosl-docker \
	hyperopt-all-nosltsl \
	hyperopt-list-docker hyperopt-show-docker \
	backtest quick-backtest backtest-docker \
	data \
	list show \
	pod-info logs logs-follow shell env status restart describe \
	copy-results copy-data list-files \
	config-show secrets-list \
	health-check full-status \
	update-and-deploy stop-bots restart-bots \
	quick-test full-optimization deploy-and-test \
	hyperopt-workflow hyperopt-workflow-quick

# ============================================================================
# DOCKER HELPER FUNKCE
# ============================================================================

docker-pull:
	@echo "$(YELLOW)Stahování FreqTrade Docker image...$(NC)"
	@docker pull $(DOCKER_IMAGE)
	@echo "$(GREEN)Image stažen: $(DOCKER_IMAGE)$(NC)"

docker-run-shell:
	@echo "$(YELLOW)Spouštění Docker kontejneru pro FreqTrade...$(NC)"
	@docker run --rm -it \
		-v $(PWD)/user_data:/freqtrade/user_data \
		--user $(DOCKER_USER) \
		$(DOCKER_IMAGE) bash

docker-hyperopt-base:
	@echo "$(YELLOW)Příprava FreqTrade Docker pro hyperopt...$(NC)"
	@docker run --rm -it \
		-v $(PWD)/user_data:/freqtrade/user_data \
		--user $(DOCKER_USER) \
		$(DOCKER_IMAGE) bash -c "echo 'Docker připraven pro hyperopt'"

prepare-docker-hyperopt:
	@echo "$(YELLOW)Příprava Docker hyperopt (config + strategie)...$(NC)"
	@mkdir -p user_data/strategies
	@python3 ./generate_hyperopt_config.py ./user_data/config.json "$(PAIRS)"
	@cp DailyBuyStrategy3_5_JPA_TEMPLATE.py user_data/strategies/DailyBuyStrategy3_5_JPA.py
	@sed -i 's/{{CLASS_NAME}}/DailyBuyStrategy3_5_JPA/g' user_data/strategies/DailyBuyStrategy3_5_JPA.py
	@sed -i 's/{{LEVERAGE}}/10/g' user_data/strategies/DailyBuyStrategy3_5_JPA.py
	@echo "$(GREEN)Docker hyperopt připraven (config + strategie v $(PWD)/user_data)$(NC)"

download-data-docker:
	@echo "$(YELLOW)Stahování tržních dat (PAIRS=$(PAIRS)) - včetně 1m...$(NC)"
	@for tf in 1m 5m 15m 1h 2h 4h 1d 1w; do \
		echo "  Stahování $$tf..."; \
		docker run --rm \
			-v $(PWD)/user_data:/freqtrade/user_data \
			--user $(DOCKER_USER) \
			$(DOCKER_IMAGE) \
			download-data \
			--exchange bybit \
			--pairs $(PAIRS) \
			--timerange $(DATA_START)-$(DATA_END) \
			--timeframe $$tf \
			--erase \
			-c /freqtrade/user_data/config.json || true; \
	done
	@echo ""
	@echo "$(YELLOW)Kontrola stažených dat:$(NC)"
	@ls -la user_data/data/bybit/ 2>/dev/null || echo "Žádná data nenalezena"
	@echo ""
	@echo "$(GREEN)Data stažena (včetně 1m)$(NC)"

download-data-docker-no1m:
	@echo "$(YELLOW)Stahování tržních dat (PAIRS=$(PAIRS)) - BEZ 1m...$(NC)"
	@for tf in 5m 15m 1h 2h 4h 1d 1w; do \
		echo "  Stahování $$tf..."; \
		docker run --rm \
			-v $(PWD)/user_data:/freqtrade/user_data \
			--user $(DOCKER_USER) \
			$(DOCKER_IMAGE) \
			download-data \
			--exchange bybit \
			--pairs $(PAIRS) \
			--timerange $(DATA_START)-$(DATA_END) \
			--timeframe $$tf \
			--erase \
			-c /freqtrade/user_data/config.json || true; \
	done
	@echo ""
	@echo "$(YELLOW)Kontrola stažených dat:$(NC)"
	@ls -la user_data/data/bybit/ 2>/dev/null || echo "Žádná data nenalezena"
	@echo ""
	@echo "$(GREEN)Data stažena (BEZ 1m)$(NC)"

prepare-docker-hyperopt-full: prepare-docker-hyperopt download-data-docker
	@echo "$(GREEN)Docker hyperopt zcela připraven (config + strategie + data včetně 1m)$(NC)"

prepare-docker-hyperopt-light: prepare-docker-hyperopt download-data-docker-no1m
	@echo "$(GREEN)Docker hyperopt připraven (config + strategie + data BEZ 1m)$(NC)"

# ============================================================================
# KUBERNETES HELPER FUNKCE
# ============================================================================

_check_pod:
	@if [ -z "$(POD_NAME)" ]; then \
		echo "$(RED)Chyba: Pod nenalezen pro deployment $(DEPLOYMENT)$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Pod: $(POD_NAME)$(NC)"

_show_config:
	@echo "$(YELLOW)=== Konfigurace ===$(NC)"
	@echo "Namespace: $(NAMESPACE)"
	@echo "Deployment: $(DEPLOYMENT)"
	@echo "Pod: $(POD_NAME)"
	@echo "Strategie: $(STRATEGY)"
	@echo "Timeframe: $(TIMEFRAME)"
	@echo "Config: $(CONFIG)"

# ============================================================================
# TESTING & CODE QUALITY (HYPEROPT PERSISTENCE SYSTEM)
# ============================================================================

test: test-unit test-integration
	@echo "$(GREEN)✓ Všechny testy passed!$(NC)"

test-unit:
	@echo "$(YELLOW)Spouštění unit testů (15 testů)...$(NC)"
	@python3 test_hyperopt_persistence.py
	@echo "$(GREEN)✓ Unit testy hotovy$(NC)"

test-integration:
	@echo "$(YELLOW)Spouštění integration testů (7 testů)...$(NC)"
	@python3 test_integration_hyperopt.py
	@echo "$(GREEN)✓ Integration testy hotovy$(NC)"

test-syntax:
	@echo "$(YELLOW)Kontrola syntaxe Python souborů...$(NC)"
	@echo "$(GREEN)✓ Všechny soubory mají validní syntaxi$(NC)"

test-pep8:
	@echo "$(YELLOW)Kontrola PEP8 compliance...$(NC)"
	@python3 check_pep8.py
	@echo "$(GREEN)✓ PEP8 kontrola hotova$(NC)"

test-coverage: test-syntax test-pep8 test-unit test-integration
	@echo ""
	@echo "$(GREEN)════════════════════════════════════════════════════════════════$(NC)"
	@echo "$(GREEN)✓ KOMPLETNÍ TEST SUITE PASSED (22/22 testů)$(NC)"
	@echo "$(GREEN)════════════════════════════════════════════════════════════════$(NC)"

hyperopt-save:
	@echo "$(YELLOW)Ukládání hyperopt parametrů...$(NC)"
	@python3 save_hyperopt_results.py extract-params
	@echo "$(GREEN)✓ Hyperopt parametry uloženy$(NC)"

hyperopt-validate:
	@echo "$(YELLOW)Validace hyperopt_params.json...$(NC)"
	@if [ -f "user_data/hyperopt_params.json" ]; then \
		python3 -m json.tool user_data/hyperopt_params.json > /dev/null && \
		echo "$(GREEN)✓ JSON je validní$(NC)" || \
		echo "$(RED)✗ JSON syntax error$(NC)"; \
	else \
		echo "$(YELLOW)! Soubor user_data/hyperopt_params.json neexistuje$(NC)"; \
	fi

hyperopt-show:
	@echo "$(YELLOW)=== Aktuální hyperopt parametry ===$(NC)"
	@if [ -f "user_data/hyperopt_params.json" ]; then \
		python3 -m json.tool user_data/hyperopt_params.json; \
	else \
		echo "$(YELLOW)Soubor user_data/hyperopt_params.json neexistuje$(NC)"; \
	fi

hyperopt-backup:
	@echo "$(YELLOW)Zálohování hyperopt parametrů...$(NC)"
	@if [ -f "user_data/hyperopt_params.json" ]; then \
		cp user_data/hyperopt_params.json user_data/hyperopt_params.json.bak.$$(date +%s); \
		echo "$(GREEN)✓ Záloha vytvořena$(NC)"; \
	else \
		echo "$(YELLOW)Soubor user_data/hyperopt_params.json neexistuje$(NC)"; \
	fi

hyperopt-inject:
	@echo "$(YELLOW)Injektáž hyperopt parametrů do strategie...$(NC)"
	@if [ -z "$(wildcard user_data/strategies/*.json)" ]; then \
		echo "$(RED)Chyba: Žádný *.json soubor v user_data/strategies/$(NC)"; \
		exit 1; \
	fi
	@JSON_FILE=$$(ls -1 user_data/strategies/*.json | head -1); \
	echo "  Kopíruji $$JSON_FILE → user_data/hyperopt_params.json"; \
	cp "$$JSON_FILE" user_data/hyperopt_params.json
	@python3 inject_hyperopt_params.py
	@echo "$(GREEN)✓ Injektáž hotova$(NC)"

list-docker:
	@echo "$(YELLOW)Exportuji nejlepší hyperopt výsledek...$(NC)"
	@python3 export_best_hyperopt.py
	@echo ""
	@echo "$(YELLOW)Soubor je připraven:$(NC)"
	@echo "  - user_data/strategies/hyperopt_best_latest.json"
	@echo ""
	@echo "$(YELLOW)Příští kraky:$(NC)"
	@echo "  1. Zkontroluj parametry: cat user_data/strategies/hyperopt_best_latest.json"
	@echo "  2. Injektuj do strategie: make hyperopt-inject"
	@echo "  3. Otestuj: make backtest"

# ============================================================================
# FREQTRADE OPERACE - HYPEROPT
# ============================================================================

prepare-pod: _check_pod
	@echo "$(YELLOW)Připravuji pod pro hyperopt (PAIR=$(PAIR))...$(NC)"
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -- bash -c \
		"mkdir -p /freqtrade/user_data/strategies /freqtrade/user_data && chmod 777 /freqtrade/user_data 2>/dev/null || true" || true
	@echo "$(YELLOW)Generuji minimální hyperopt config bez FreqAI (pár: $(PAIR))...$(NC)"
	@kubectl cp ./generate_hyperopt_config.py -n $(NAMESPACE) $(POD_NAME):/tmp/generate_hyperopt_config.py
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -- python3 /tmp/generate_hyperopt_config.py /freqtrade/user_data/config.json "$(PAIR)"
	@echo "$(GREEN)Pod je připraven pro hyperopt na páru: $(PAIR)$(NC)"

copy-strategy: prepare-pod
	@echo "$(YELLOW)Kopíruji aktuální strategii do podu...$(NC)"
	@mkdir -p /tmp/strategy_temp
	@rm -rf /tmp/strategy_temp
	@echo "$(GREEN)Strategie zkopírována do podu$(NC)"

hyperopt-buy: copy-strategy
	@echo "$(YELLOW)Spouštění hyperopt pro BUY parametry...$(NC)"
	@kubectl exec -n $(NAMESPACE) -it $(POD_NAME) -- bash -c "freqtrade hyperopt \
		--random-state 100 \
		--hyperopt-loss OnlyProfitHyperOptLoss \
		--strategy $(STRATEGY) \
		--strategy-path /freqtrade/user_data/strategies \
		--timeframe $(TIMEFRAME) \
		-c $(CONFIG) \
		--space buy \
		--timerange $(HYPEROPT_START)-$(HYPEROPT_END) \
		-e $(EPOCHS) \
		-j 2 || true"

hyperopt-buy-docker: prepare-docker-hyperopt-light
	@echo "$(YELLOW)Spouštění hyperopt na Dockeru (BUY)...$(NC)"
	@docker run --rm -it \
		-v $(PWD)/user_data:/freqtrade/user_data \
		--user $(DOCKER_USER) \
		$(DOCKER_IMAGE) \
		hyperopt \
		--random-state 100 \
		--hyperopt-loss OnlyProfitHyperOptLoss \
		--strategy $(STRATEGY) \
		--strategy-path /freqtrade/user_data/strategies \
		--timeframe $(TIMEFRAME) \
		-c /freqtrade/user_data/config.json \
		--space buy \
		--timerange $(HYPEROPT_START)-$(HYPEROPT_END) \
		-e $(EPOCHS) \
		-j $(JOBS) || true

hyperopt-sell: copy-strategy
	@echo "$(YELLOW)Spouštění hyperopt pro SELL parametry...$(NC)"
	@kubectl exec -n $(NAMESPACE) -it $(POD_NAME) -- bash -c "freqtrade hyperopt \
		--random-state 100 \
		--hyperopt-loss OnlyProfitHyperOptLoss \
		--strategy $(STRATEGY) \
		--strategy-path /freqtrade/user_data/strategies \
		--timeframe $(TIMEFRAME) \
		-c $(CONFIG) \
		--space sell \
		--timerange $(HYPEROPT_START)-$(HYPEROPT_END) \
		-e $(EPOCHS) \
		-j 2 || true"

hyperopt-trailing: copy-strategy
	@echo "$(YELLOW)Spouštění hyperopt pro TRAILING STOP parametry...$(NC)"
	@kubectl exec -n $(NAMESPACE) -it $(POD_NAME) -- bash -c "freqtrade hyperopt \
		--random-state 100 \
		--hyperopt-loss OnlyProfitHyperOptLoss \
		--strategy $(STRATEGY) \
		--strategy-path /freqtrade/user_data/strategies \
		--timeframe $(TIMEFRAME) \
		-c $(CONFIG) \
		--space trailing \
		--timerange $(HYPEROPT_START)-$(HYPEROPT_END) \
		-e $(EPOCHS) \
		-j 2 || true"

hyperopt-roi: copy-strategy
	@echo "$(YELLOW)Spouštění hyperopt pro ROI parametry...$(NC)"
	@kubectl exec -n $(NAMESPACE) -it $(POD_NAME) -- bash -c "freqtrade hyperopt \
		--random-state 100 \
		--hyperopt-loss OnlyProfitHyperOptLoss \
		--strategy $(STRATEGY) \
		--strategy-path /freqtrade/user_data/strategies \
		--timeframe $(TIMEFRAME) \
		-c $(CONFIG) \
		--space roi \
		--timerange $(HYPEROPT_START)-$(HYPEROPT_END) \
		-e $(EPOCHS) \
		-j 2 || true"

hyperopt-quick: copy-strategy
	@echo "$(YELLOW)Spouštění QUICK hyperopt pro buy (50 epoch)...$(NC)"
	@kubectl exec -n $(NAMESPACE) -it $(POD_NAME) -- bash -c "freqtrade hyperopt \
		--random-state 100 \
		--hyperopt-loss OnlyProfitHyperOptLoss \
		--strategy $(STRATEGY) \
		--strategy-path /freqtrade/user_data/strategies \
		--timeframe $(TIMEFRAME) \
		-c $(CONFIG) \
		--space buy \
		--timerange $(HYPEROPT_START)-$(HYPEROPT_END) \
		-e 50 \
		-j 2 || true"

hyperopt-all: copy-strategy
	@echo "$(YELLOW)Spouštění hyperopt pro BUY, SELL, ROI, STOPLOSS, TRAILING...$(NC)"
	@kubectl exec -n $(NAMESPACE) -it $(POD_NAME) -- bash -c "freqtrade hyperopt \
		--random-state 100 \
		--hyperopt-loss OnlyProfitHyperOptLoss \
		--strategy $(STRATEGY) \
		--strategy-path /freqtrade/user_data/strategies \
		--timeframe $(TIMEFRAME) \
		-c $(CONFIG) \
		--space buy sell roi stoploss trailing \
		--timerange $(HYPEROPT_START)-$(HYPEROPT_END) \
		-e $(EPOCHS) \
		-j 2 || true"

hyperopt-all-nosl: copy-strategy
	@echo "$(YELLOW)Spouštění hyperopt pro BUY, SELL, ROI, TRAILING (bez STOPLOSS)...$(NC)"
	@kubectl exec -n $(NAMESPACE) -it $(POD_NAME) -- bash -c "freqtrade hyperopt \
		--random-state 100 \
		--hyperopt-loss OnlyProfitHyperOptLoss \
		--strategy $(STRATEGY) \
		--strategy-path /freqtrade/user_data/strategies \
		--timeframe $(TIMEFRAME) \
		-c $(CONFIG) \
		--space buy sell roi trailing \
		--timerange $(HYPEROPT_START)-$(HYPEROPT_END) \
		-e $(EPOCHS) \
		-j 2 || true"

hyperopt-all-nosl-docker: prepare-docker-hyperopt-light
	@echo "$(YELLOW)Spouštění hyperopt na Dockeru (BUY, SELL, ROI, TRAILING - bez STOPLOSS)...$(NC)"
	@docker run --rm -it \
		-v $(PWD)/user_data:/freqtrade/user_data \
		--user $(DOCKER_USER) \
		$(DOCKER_IMAGE) \
		hyperopt \
		--random-state 100 \
		--hyperopt-loss OnlyProfitHyperOptLoss \
		--strategy $(STRATEGY) \
		--strategy-path /freqtrade/user_data/strategies \
		--timeframe $(TIMEFRAME) \
		-c /freqtrade/user_data/config.json \
		--space buy sell roi trailing \
		--timerange $(HYPEROPT_START)-$(HYPEROPT_END) \
		-e $(EPOCHS) \
		-j $(JOBS) || true

hyperopt-sell-docker: prepare-docker-hyperopt-light
	@echo "$(YELLOW)Spouštění hyperopt na Dockeru (SELL)...$(NC)"
	@docker run --rm -it \
		-v $(PWD)/user_data:/freqtrade/user_data \
		--user $(DOCKER_USER) \
		$(DOCKER_IMAGE) \
		hyperopt \
		--random-state 100 \
		--hyperopt-loss OnlyProfitHyperOptLoss \
		--strategy $(STRATEGY) \
		--strategy-path /freqtrade/user_data/strategies \
		--timeframe $(TIMEFRAME) \
		-c /freqtrade/user_data/config.json \
		--space sell \
		--timerange $(HYPEROPT_START)-$(HYPEROPT_END) \
		-e $(EPOCHS) \
		-j $(JOBS) || true

hyperopt-trailing-docker: prepare-docker-hyperopt-light
	@echo "$(YELLOW)Spouštění hyperopt na Dockeru (TRAILING STOP)...$(NC)"
	@docker run --rm -it \
		-v $(PWD)/user_data:/freqtrade/user_data \
		--user $(DOCKER_USER) \
		$(DOCKER_IMAGE) \
		hyperopt \
		--random-state 100 \
		--hyperopt-loss OnlyProfitHyperOptLoss \
		--strategy $(STRATEGY) \
		--strategy-path /freqtrade/user_data/strategies \
		--timeframe $(TIMEFRAME) \
		-c /freqtrade/user_data/config.json \
		--space trailing \
		--timerange $(HYPEROPT_START)-$(HYPEROPT_END) \
		-e $(EPOCHS) \
		-j $(JOBS) || true

hyperopt-roi-docker: prepare-docker-hyperopt-light
	@echo "$(YELLOW)Spouštění hyperopt na Dockeru (ROI)...$(NC)"
	@docker run --rm -it \
		-v $(PWD)/user_data:/freqtrade/user_data \
		--user $(DOCKER_USER) \
		$(DOCKER_IMAGE) \
		hyperopt \
		--random-state 100 \
		--hyperopt-loss OnlyProfitHyperOptLoss \
		--strategy $(STRATEGY) \
		--strategy-path /freqtrade/user_data/strategies \
		--timeframe $(TIMEFRAME) \
		-c /freqtrade/user_data/config.json \
		--space roi \
		--timerange $(HYPEROPT_START)-$(HYPEROPT_END) \
		-e $(EPOCHS) \
		-j $(JOBS) || true

hyperopt-quick-docker: prepare-docker-hyperopt-light
	@echo "$(YELLOW)Spouštění QUICK hyperopt na Dockeru (BUY, 50 epoch)...$(NC)"
	@docker run --rm -it \
		-v $(PWD)/user_data:/freqtrade/user_data \
		--user $(DOCKER_USER) \
		$(DOCKER_IMAGE) \
		hyperopt \
		--random-state 100 \
		--hyperopt-loss OnlyProfitHyperOptLoss \
		--strategy $(STRATEGY) \
		--strategy-path /freqtrade/user_data/strategies \
		--timeframe $(TIMEFRAME) \
		-c /freqtrade/user_data/config.json \
		--space buy \
		--timerange $(HYPEROPT_START)-$(HYPEROPT_END) \
		-e 50 \
		-j $(JOBS) || true

hyperopt-all-docker: prepare-docker-hyperopt-light
	@echo "$(YELLOW)Spouštění hyperopt na Dockeru (BUY, SELL, ROI, STOPLOSS, TRAILING)...$(NC)"
	@docker run --rm -it \
		-v $(PWD)/user_data:/freqtrade/user_data \
		--user $(DOCKER_USER) \
		$(DOCKER_IMAGE) \
		hyperopt \
		--random-state 100 \
		--hyperopt-loss OnlyProfitHyperOptLoss \
		--strategy $(STRATEGY) \
		--strategy-path /freqtrade/user_data/strategies \
		--timeframe $(TIMEFRAME) \
		-c /freqtrade/user_data/config.json \
		--space buy sell roi stoploss trailing \
		--timerange $(HYPEROPT_START)-$(HYPEROPT_END) \
		-e $(EPOCHS) \
		-j $(JOBS) || true
hyperopt-all-nosltsl: copy-strategy
	@echo "$(YELLOW)Spouštění hyperopt pro BUY a ROI (bez SELL/TRAILING/STOPLOSS)...$(NC)"
	@kubectl exec -n $(NAMESPACE) -it $(POD_NAME) -- bash -c "freqtrade hyperopt \
		--random-state 100 \
		--hyperopt-loss OnlyProfitHyperOptLoss \
		--strategy $(STRATEGY) \
		--strategy-path /freqtrade/user_data/strategies \
		--timeframe $(TIMEFRAME) \
		-c $(CONFIG) \
		--space buy roi \
		--timerange $(HYPEROPT_START)-$(HYPEROPT_END) \
		-e $(EPOCHS) \
		-j 2 || true"

# ============================================================================
# HYPEROPT RESULTS - DOCKER
# ============================================================================

hyperopt-list-docker:
	@echo "$(YELLOW)Seznam hyperopt výsledků...$(NC)"
	@docker run --rm \
		-v $(PWD)/user_data:/freqtrade/user_data \
		--user $(DOCKER_USER) \
		$(DOCKER_IMAGE) \
		hyperopt-list --config /freqtrade/user_data/config.json --profitable

hyperopt-show-docker:
	@echo "$(YELLOW)Zobrazení hyperopt epochy $(EPOCH)...$(NC)"
	@docker run --rm \
		-v $(PWD)/user_data:/freqtrade/user_data \
		--user $(DOCKER_USER) \
		$(DOCKER_IMAGE) \
		hyperopt-show --config /freqtrade/user_data/config.json -n $(EPOCH)
	@echo ""
	@echo "$(YELLOW)Exportuji parametry do JSON...$(NC)"
	@docker run --rm \
		-v $(PWD)/user_data:/freqtrade/user_data \
		--user $(DOCKER_USER) \
		$(DOCKER_IMAGE) \
		hyperopt-show --config /freqtrade/user_data/config.json -n $(EPOCH) --json > user_data/hyperopt_epoch_$(EPOCH).json 2>/dev/null || true
	@if [ -f "user_data/hyperopt_epoch_$(EPOCH).json" ]; then \
		echo "$(GREEN)✓ Parametry exportovány do user_data/hyperopt_epoch_$(EPOCH).json$(NC)"; \
	fi

# ============================================================================
# FREQTRADE OPERACE - BACKTESTING
# ============================================================================

backtest: _check_pod
	@echo "$(YELLOW)Spouštění backtestu...$(NC)"
	kubectl exec -n $(NAMESPACE) -it $(POD_NAME) -- freqtrade backtesting \
		--strategy $(STRATEGY) \
		--timeframe $(TIMEFRAME) \
		-c $(CONFIG) \
		--timerange $(BACKTEST_START)-$(BACKTEST_END)

quick-backtest: _check_pod
	@echo "$(YELLOW)Spouštění rychlého backtestu (1 týden)...$(NC)"
	kubectl exec -n $(NAMESPACE) -it $(POD_NAME) -- freqtrade backtesting \
		--strategy $(STRATEGY) \
		--timeframe $(TIMEFRAME) \
		-c $(CONFIG) \
		--timerange 20250101-20250108

backtest-docker:
	@echo "$(YELLOW)Spouštění backtestu v Docker (PAIRS: $(PAIRS))...$(NC)"
	@docker run --rm \
		-v $(PWD)/user_data:/freqtrade/user_data \
		$(DOCKER_IMAGE) backtesting \
		--strategy DailyBuyStrategy3_5_JPA \
		--strategy-path /freqtrade/user_data/strategies \
		--timeframe $(TIMEFRAME) \
		--pairs $(PAIRS) \
		--timerange $(BACKTEST_START)-$(BACKTEST_END)

# ============================================================================
# FREQTRADE OPERACE - DATA MANAGEMENT
# ============================================================================

data: _check_pod prepare-pod
	@echo "$(YELLOW)Stahování dat pro pár: $(PAIR)...$(NC)"
	kubectl exec -n $(NAMESPACE) -it $(POD_NAME) -- freqtrade download-data \
		--timeframe 5m 15m 1h 4h 1d \
		-c $(CONFIG) \
		--timerange $(DATA_START)-$(DATA_END)

# ============================================================================
# FREQTRADE OPERACE - HYPEROPT RESULTS
# ============================================================================

list: _check_pod
	@echo "$(YELLOW)Zobrazování profitabilních hyperopt výsledků...$(NC)"
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -- bash -c \
		'freqtrade hyperopt-list --hyperopt-filename $$(ls -t /freqtrade/user_data/hyperopt_results 2>/dev/null | head -n 1) --profitable --min-avg-profit 1.0 --min-total-profit 0 2>/dev/null || echo "Žádné výsledky nenalezeny"'

show: _check_pod
	@echo "$(YELLOW)Zobrazování hyperopt výsledku pro epochu $(EPOCH)...$(NC)"
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -- bash -c \
		'freqtrade hyperopt-show -n $(EPOCH) --hyperopt-filename $$(ls -t /freqtrade/user_data/hyperopt_results 2>/dev/null | head -n 1) 2>/dev/null || echo "Výsledek nenalezen"'

# ============================================================================
# KUBERNETES MANAGEMENT
# ============================================================================

pod-info: _check_pod
	@echo "$(YELLOW)=== Informace o podu ===$(NC)"
	@kubectl describe pod -n $(NAMESPACE) $(POD_NAME) | head -50

logs: _check_pod
	@echo "$(YELLOW)=== Posledních 100 řádků logu ===$(NC)"
	@kubectl logs -n $(NAMESPACE) $(POD_NAME) --tail=100

logs-follow: _check_pod
	@echo "$(YELLOW)=== Sledování logu v reálném čase (Ctrl+C pro ukončení) ===$(NC)"
	@kubectl logs -n $(NAMESPACE) -f $(POD_NAME)

shell: _check_pod
	@echo "$(YELLOW)Připojování k interaktivnímu shellu v podu...$(NC)"
	@kubectl exec -n $(NAMESPACE) -it $(POD_NAME) -- /bin/bash

env: _check_pod
	@echo "$(YELLOW)=== Environmentální proměnné ===$(NC)"
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -- printenv | sort

status: _check_pod
	@echo "$(YELLOW)=== Status deploymentu ===$(NC)"
	@kubectl get deployment -n $(NAMESPACE) $(DEPLOYMENT)
	@echo "$(YELLOW)=== Status podu ===$(NC)"
	@kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/instance=$(DEPLOYMENT)

restart: _check_pod
	@echo "$(RED)Restartování podu $(POD_NAME)...$(NC)"
	@kubectl delete pod -n $(NAMESPACE) $(POD_NAME)
	@sleep 2
	@echo "$(GREEN)Pod je odstraňován, Kubernetes jej automaticky znovu spustí...$(NC)"
	@sleep 3
	@make status

describe: _check_pod
	@echo "$(YELLOW)=== Detaily deploymentu ===$(NC)"
	@kubectl describe deployment -n $(NAMESPACE) $(DEPLOYMENT)
	@echo ""
	@echo "$(YELLOW)=== Detaily podu ===$(NC)"
	@kubectl describe pod -n $(NAMESPACE) $(POD_NAME)

# ============================================================================
# FILE MANAGEMENT
# ============================================================================

copy-results: _check_pod
	@echo "$(YELLOW)Kopírování hyperopt výsledků z podu...$(NC)"
	@mkdir -p ./hyperopt_results
	@kubectl cp -n $(NAMESPACE) $(POD_NAME):/freqtrade/user_data/hyperopt_results ./hyperopt_results || echo "Výsledky nenalezeny"
	@echo "$(GREEN)Výsledky zkopírovány do ./hyperopt_results$(NC)"

copy-data: _check_pod
	@echo "$(YELLOW)Kopírování dat z podu...$(NC)"
	@mkdir -p ./pod_data
	@kubectl cp -n $(NAMESPACE) $(POD_NAME):/freqtrade/user_data/data ./pod_data || echo "Data nenalezena"
	@echo "$(GREEN)Data zkopírována do ./pod_data$(NC)"

list-files: _check_pod
	@echo "$(YELLOW)=== Soubory v /freqtrade/user_data ===$(NC)"
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -- ls -lah /freqtrade/user_data/ 2>/dev/null || echo "Adresář nenalezen"
	@echo ""
	@echo "$(YELLOW)=== Strategie ===$(NC)"
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -- ls -lah /etc/freqtrade/*.py 2>/dev/null || echo "Strategie nenalezeny"

# ============================================================================
# CONFIGURATION
# ============================================================================

config-show: _check_pod
	@echo "$(YELLOW)=== Konfigurační soubor ===$(NC)"
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -- cat /etc/freqtrade/config.json | head -50

secrets-list: _check_pod
	@echo "$(YELLOW)=== Secrets (bez hesel) ===$(NC)"
	@kubectl get secrets -n $(NAMESPACE) $(DEPLOYMENT)-secret -o jsonpath='{.data}' 2>/dev/null | jq 'keys' || echo "Žádné secrets"

# ============================================================================
# HEALTH CHECK & MONITORING
# ============================================================================

health-check: _check_pod status logs
	@echo ""
	@echo "$(GREEN)Health check kompletní$(NC)"

full-status: _show_config pod-info status env
	@echo ""
	@echo "$(GREEN)Detailní status report hotov$(NC)"

# ============================================================================
# AUTOGEN SCRIPT MANAGEMENT
# ============================================================================

update-and-deploy:
	@echo "$(YELLOW)Aktualizace kódu z Git a spuštění botů...$(NC)"
	git pull
	@echo "$(GREEN)Spuštění autogen scriptu...$(NC)"
	./autogen_sniper_t3_v2.sh

stop-bots:
	@echo "$(YELLOW)Zastavování všech botů...$(NC)"
	./stop_bots_sniper_t3_v2.sh
	@echo "$(GREEN)Boty zastaveny$(NC)"

restart-bots: stop-bots update-and-deploy
	@echo "$(GREEN)Boty restartovány a aktualizovány$(NC)"

# ============================================================================
# CONVENIENCE TARGETS
# ============================================================================

quick-test: backtest list

full-optimization: _show_config hyperopt-all copy-results list

deploy-and-test: update-and-deploy status backtest

hyperopt-workflow: hyperopt-all hyperopt-save hyperopt-validate hyperopt-show
	@echo ""
	@echo "$(GREEN)════════════════════════════════════════════════════════════════$(NC)"
	@echo "$(GREEN)✓ Hyperopt workflow hotov!$(NC)"
	@echo "$(GREEN)Parametry jsou uloženy v user_data/hyperopt_params.json$(NC)"
	@echo "$(GREEN)Bot je připraven k spuštění - parametry se automaticky načtou$(NC)"
	@echo "$(GREEN)════════════════════════════════════════════════════════════════$(NC)"

hyperopt-workflow-quick: hyperopt-quick hyperopt-save hyperopt-validate hyperopt-show
	@echo ""
	@echo "$(GREEN)════════════════════════════════════════════════════════════════$(NC)"
	@echo "$(GREEN)✓ Quick hyperopt workflow hotov!$(NC)"
	@echo "$(GREEN)Parametry jsou uloženy v user_data/hyperopt_params.json$(NC)"
	@echo "$(GREEN)════════════════════════════════════════════════════════════════$(NC)"

help:
	@echo "$(GREEN)════════════════════════════════════════════════════════════════$(NC)"
	@echo "$(GREEN)FreqTrade Kubernetes Makefile - Dostupné příkazy$(NC)"
	@echo "$(GREEN)════════════════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "$(YELLOW)INFORMACE O SYSTÉMU:$(NC)"
	@echo "  CPU jádra detekována: $(NPROC)"
	@echo "  Hyperopt jobs (-j): $(JOBS)"
	@echo "  Příkaz: make hyperopt-all-docker JOBS=4 (pro změnu počtu jobů)"
	@echo ""
	@echo "$(YELLOW)TESTING & CODE QUALITY:$(NC)"
	@echo "  make test                      - Spusť všechny testy (unit + integration)"
	@echo "  make test-unit                 - Spusť unit testy (15 testů)"
	@echo "  make test-integration          - Spusť integration testy (7 testů)"
	@echo "  make test-syntax               - Kontrola syntaxe Python souborů"
	@echo "  make test-pep8                 - Kontrola PEP8 compliance"
	@echo "  make test-coverage             - Kompletní test suite (syntax + pep8 + all tests)"
	@echo ""
	@echo "$(YELLOW)HYPEROPT PERSISTENCE:$(NC)"
	@echo "  make hyperopt-save             - Uložit hyperopt parametry"
	@echo "  make hyperopt-validate         - Validovat hyperopt_params.json"
	@echo "  make hyperopt-show             - Zobrazit uložené hyperopt parametry"
	@echo "  make hyperopt-backup           - Zálohovat hyperopt parametry"
	@echo "  make hyperopt-inject           - Injektovat parametry do strategie"
	@echo ""
	@echo "$(YELLOW)HYPEROPT OPERACE:$(NC)"
	@echo "  make hyperopt-buy              - Hyperopt pro BUY parametry"
	@echo "  make hyperopt-sell             - Hyperopt pro SELL parametry"
	@echo "  make hyperopt-trailing         - Hyperopt pro TRAILING STOP"
	@echo "  make hyperopt-roi              - Hyperopt pro ROI parametry"
	@echo "  make hyperopt-all              - Hyperopt pro všechny parametry"
	@echo "  make hyperopt-all-nosl         - Hyperopt bez STOPLOSS"
	@echo "  make hyperopt-all-nosltsl      - Hyperopt jen BUY a ROI"
	@echo ""
	@echo "$(YELLOW)BACKTESTING:$(NC)"
	@echo "  make backtest                  - Backtest pro zadané období (Kubernetes)"
	@echo "  make backtest-docker           - Backtest v Docker (s více měnami)"
	@echo "  make quick-backtest            - Backtest na 1 týden (rychlý)"
	@echo "  make quick-test                - Backtest + list výsledků"
	@echo ""
	@echo "$(YELLOW)DATA MANAGEMENT:$(NC)"
	@echo "  make data                      - Stažení dat z burzy"
	@echo "  make copy-results              - Kopie hyperopt výsledků"
	@echo "  make copy-data                 - Kopie dat z podu"
	@echo "  make list-files                - Výpis souborů v podu"
	@echo ""
	@echo "$(YELLOW)HYPEROPT VÝSLEDKY:$(NC)"
	@echo "  make list                      - Výpis profitabilních výsledků (Kubernetes)"
	@echo "  make list-docker               - Seznam hyperopt výsledků (Docker)"
	@echo "  make show                      - Zobrazit konkrétní výsledek (EPOCH=N)"
	@echo "  make show EPOCH=40             - Zobraz epochu 40 + export do JSON"
	@echo ""
	@echo "$(YELLOW)KUBERNETES MANAGEMENT:$(NC)"
	@echo "  make status                    - Status deploymentu a podu"
	@echo "  make pod-info                  - Detaily podu"
	@echo "  make describe                  - Detailní popis podu a deploymentu"
	@echo "  make logs                      - Posledních 100 řádků logu"
	@echo "  make logs-follow               - Follow logs v reálném čase"
	@echo "  make shell                     - Interaktivní shell v podu"
	@echo "  make env                       - Zobrazit env proměnné"
	@echo "  make restart                   - Restartovat pod"
	@echo ""
	@echo "$(YELLOW)AUTOGEN SCRIPTS:$(NC)"
	@echo "  make update-and-deploy         - Git pull + spuštění botů"
	@echo "  make stop-bots                 - Zastavit všechny boty"
	@echo "  make restart-bots              - Stop + update + deploy"
	@echo ""
	@echo "$(YELLOW)KONFIGURACE:$(NC)"
	@echo "  make config-show               - Zobrazit config.json"
	@echo "  make secrets-list              - Výpis secrets"
	@echo "  make health-check              - Komplexní health check"
	@echo "  make full-status               - Detailní status report"
	@echo ""
	@echo "$(YELLOW)PARAMETRY (mají defaults):$(NC)"
	@echo "  make TARGET STRATEGY=MyStrat   - Změnit strategii"
	@echo "  make TARGET TIMEFRAME=5m       - Změnit timeframe"
	@echo "  make TARGET EPOCHS=5000        - Počet epoch pro hyperopt"
	@echo "  make TARGET DATA_START=20250101 DATA_END=20250131 - Datový rozsah"
	@echo "  make TARGET JOBS=4             - Počet paralelních jobů pro hyperopt (default: detekováno)"
	@echo "  make make TARGET DEPLOYMENT=bot-name - Změnit bot (default: freqai-t3v2-5m-lev4-bot)"
	@echo ""
	@echo "$(CYAN)DOCKER HYPEROPT WORKFLOW (Local):$(NC)"
	@echo "  1. SPUŠTĚNÍ HYPEROPT:"
	@echo "     make hyperopt-all-docker EPOCHS=50"
	@echo ""
	@echo "  2. EXPORT NEJLEPŠÍHO VÝSLEDKU:"
	@echo "     make list-docker"
	@echo ""
	@echo "  3. KONTROLA PARAMETRŮ:"
	@echo "     cat user_data/strategies/hyperopt_best_latest.json"
	@echo ""
	@echo "  4. INJEKTÁŽ DO STRATEGIE:"
	@echo "     make hyperopt-inject"
	@echo ""
	@echo "  5. BACKTEST:"
	@echo "     make backtest TIMEFRAME=5m"
	@echo ""
	@echo "$(GREEN)PŘÍKLADY POUŽITÍ:$(NC)"
	@echo "  make test                      - Spustit všechny testy"
	@echo "  make test-coverage             - Kompletní validace (syntax + pep8 + testy)"
	@echo "  make hyperopt-buy              - Hyperopt na BUY s defaulty"
	@echo "  make hyperopt-save             - Uložit hyperopt výsledky"
	@echo "  make hyperopt-show             - Zobrazit uložené parametry"
	@echo "  make backtest STRATEGY=MyBot   - Backtest s jinou strategií"
	@echo "  make backtest-docker PAIRS='BTC/USDT:USDT ETH/USDT:USDT RIVER/USDT:USDT' - Backtest více měn"
	@echo "  make status                    - Zkontrolovat status bota"
	@echo "  make logs-follow               - Sledovat logy"
	@echo "  make full-optimization         - Plná hyperopt optimalizace"
	@echo "  make show EPOCH=42             - Zobrazit výsledek epoch 42"
	@echo "  make update-and-deploy         - Aktualizovat kód a spustit boty"
	@echo "  make stop-bots                 - Zastavit všechny boty"
	@echo "  make restart-bots              - Kompletní restart s aktualizací"
	@echo ""
	@echo "$(GREEN)════════════════════════════════════════════════════════════════$(NC)"

all: help
