# Exit Policy

Smart Exit behavior for Smart DCA plans.

## Core Rule

The skill monitors exits automatically but must NOT sell without explicit user confirmation.

## Thresholds by Plan Duration

| Duration | Take Profit (TP) | Trailing Stop (TS) | DCA-out Periods | Trend MA |
|----------|-----------------|-------------------|-----------------|----------|
| 1–3 mo | +20% | -10% | 4–7 days | 50 |
| 3–6 mo | +40% | -15% | 7–14 days | 50 |
| 6–12 mo | +50% | -20% | 14–21 days | 200 |
| 12+ mo | +100% | -25% | 21–28 days | 200 |

## State Machine

```
inactive → tracking    when: current return ≥ TP threshold
tracking → selling     when: drawdown from peak ≥ TS AND user approves
selling  → paused      when: trend turns bullish (price crosses above MA)
paused   → selling     when: trend reverts bearish
selling  → completed   when: all sells executed
```

## State Details

### tracking

- Record peak value after TP threshold is reached.
- Re-check drawdown from peak each cron run.
- Ask user before moving to selling. Show exit recommendation format.

### selling

Each cron run:

1. Trend check via `sma_check.py --ma <trend_ma>` — if price crossed above MA → pause, notify.
2. Calculate adaptive sell amount:
   ```
   base = holdings / remaining_periods
   adjusted = base × (current_price / avg_cost)
   clamped = clamp(adjusted, base × 0.5, base × 2.0)
   ```
3. If bbSOL enabled → convert bbSOL → SOL first.
4. Execute sell: token → USDC.
5. Deposit proceeds to stable pool position.
6. Update exit state in config.

### paused

- Resume when trend weakens again (price drops below MA).
- If paused too long (> remaining_periods days) → ask user whether to resume or force completion.

## User-Facing Recommendation Style

When suggesting a sell:

1. Explain why in one sentence.
2. Recommend one default action.
3. Present alternatives only if relevant.
