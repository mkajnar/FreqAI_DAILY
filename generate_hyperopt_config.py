#!/usr/bin/env python3
"""
Generate minimal hyperopt config for DailyBuyStrategy3_5_JPA
"""
import json
import sys
import os

def generate_config(config_path, pairs):
    config = {
        "max_open_trades": 5,
        "stake_currency": "USDT",
        "stake_amount": 100.0,
        "tradable_balance_ratio": 0.95,
        "fiat_display_currency": "USD",
        "dry_run": True,
        "dry_run_wallet": 10000,
        "cancel_open_orders_on_exit": False,
        "trading_mode": "futures",
        "margin_mode": "isolated",
        "timeframe": "5m",
        "leverage": {
            "BTC/USDT:USDT": 5.0,
            "ETH/USDT:USDT": 5.0
        },
        "check_buy_timeout": 30,
        "check_sell_timeout": 30,
        "entry_pricing": {
            "price_side": "other",
            "use_order_book": True,
            "order_book_top": 1
        },
        "exit_pricing": {
            "price_side": "other",
            "use_order_book": True,
            "order_book_top": 1
        },
        "order_types": {
            "entry": "market",
            "exit": "market",
            "stoploss": "market",
            "stoploss_on_exchange": True
        },
        "exchange": {
            "name": "bybit",
            "key": os.getenv("EXCHANGE_KEY", ""),
            "secret": os.getenv("EXCHANGE_SECRET", ""),
            "ccxt_config": {
                "enableRateLimit": True,
                "options": {
                    "defaultType": "future"
                }
            },
            "pair_whitelist": pairs.split()
        },
        "pairlists": [
            {
                "method": "StaticPairList"
            }
        ],
        "telegram": {
            "enabled": False,
            "token": "dummy_token",
            "chat_id": "0"
        },
        "api_server": {
            "enabled": True,
            "listen_ip": "0.0.0.0",
            "listen_port": 8080
        }
    }

    os.makedirs(os.path.dirname(config_path), exist_ok=True)
    with open(config_path, 'w') as f:
        json.dump(config, f, indent=2)
    print(f"Config generated: {config_path}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: generate_hyperopt_config.py <config_path> [pairs]")
        sys.exit(1)
    
    config_path = sys.argv[1]
    pairs = sys.argv[2] if len(sys.argv) > 2 else "RIVER/USDT BTC/USDT ETH/USDT"
    
    generate_config(config_path, pairs)
