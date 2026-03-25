# Config Schema

Plan config used by `byreal-dca`. One file per plan.

- Smart DCA: `~/.config/byreal/dca/<TOKEN>.json` (one per token)
- Basic DCA: `~/.config/byreal/dca/<plan_id>.json`

## Schema

```json
{
  "schema_version": 1,
  "plan_id": "sol-20260324-1000",
  "token": "SOL",
  "display_symbol": "SOL",
  "token_mint": "So11111111111111111111111111111111111111112",
  "mode": "standard|aggressive|defensive|basic",
  "mode_params": {
    "aggressive_step": 0,
    "last_buy_price": null
  },
  "total_budget": 1000,
  "amount_per_buy": 20,
  "frequency": "daily",
  "bbsol_enabled": false,
  "holdings_tracking": {
    "accounting_asset": "SOL",
    "wallet_asset": "SOL|bbSOL",
    "wallet_balance": 0
  },
  "idle_yield": {
    "pool_address": "HrWp3QR3hNeVy6tEZtcpsjwEiGgKJuL1NDP84EaaU2Nh",
    "position_id": "pos-abc123"
  },
  "plan_state": {
    "status": "active|paused|attention_required|holding_only|completed|cancelled",
    "consecutive_failures": 0,
    "pending_action": null,
    "last_error": null
  },
  "market_regime": {
    "checked_at": "2026-03-25T10:00:00Z",
    "price": 148.20,
    "ma": 142.50,
    "ma_window": 200,
    "signal": "above|below|unavailable"
  },
  "schedule": {
    "last_run_at": "2026-03-25T10:00:00Z",
    "interval_days": 1
  },
  "budget_tracking": {
    "invested_usdc": 20,
    "remaining_usdc": 980,
    "realized_usdc": 0,
    "avg_entry_price": 148.20
  },
  "exit": {
    "mode": "smart|manual",
    "state": "inactive|tracking|selling|paused|completed",
    "tp_threshold": 0.50,
    "ts_threshold": 0.20,
    "dca_out_periods": 14,
    "trend_ma": 200,
    "peak_value": null,
    "sells_completed": 0
  },
  "created_at": "2026-03-25T10:00:00Z",
  "execution_log": [
    {
      "date": "2026-03-25T10:00:00Z",
      "action": "buy|sell|missed|skipped",
      "amount_usdc": 20,
      "amount_token": 0.135,
      "wallet_asset": "SOL|bbSOL",
      "price": 148.20,
      "txid": "5K7x..."
    }
  ]
}
```

## Mode Params by Mode

**Aggressive**: `{"factor": 1.2, "max_steps": 3, "reserve": 26.58, "aggressive_step": 0, "last_buy_price": null}`

**Defensive**: `{"sma_window": 200, "below_fraction": 0.3}`

**Standard / Basic**: `{}` or omitted.

## Rules

- Do not use generic wallet token balance as source of truth for plan accounting.
- `plan_holdings = sum(execution_log buys) - sum(execution_log sells)`.
- `budget_tracking.remaining_usdc` is the source of truth for budget remaining and only decreases by confirmed buy spend.
- When `remaining_usdc <= 0` and holdings remain, move plan to `holding_only` so exit monitoring can continue.
- `idle_yield.position_id`, if present, is optional parking for leftover funds, not a per-cycle withdraw mechanism.
- LP withdraw/reopen friction and wallet buffer are cash-management effects; do not subtract them from DCA budget.
- One Smart DCA plan per token.
