# bbSOL

Optional SOL → bbSOL yield path. SOL plans only.

## When It Applies

Only for SOL DCA plans where the user opts in at plan creation.

## Behavior

- Ask once on plan creation: "Want your SOL holdings to earn staking yield as bbSOL?"
- If enabled: convert bought SOL to bbSOL after each buy
- Before selling: convert bbSOL back to SOL first

## Accounting

- `accounting_asset` = SOL (always)
- `wallet_asset` = SOL or bbSOL (depends on setting)
- `execution_log` tracks SOL-equivalent amounts

## Safety

Never assume wallet balance equals accounting holdings. Always reconcile:

1. Check `holdings_tracking.wallet_asset`
2. Check actual wallet balance of that asset
3. Compare to `sum(execution_log)` accounting

Before any sell with bbSOL enabled:

```bash
# 1. Convert bbSOL → SOL
byreal-cli swap execute \
  --input-mint <bbSOL-mint> \
  --output-mint So11111111111111111111111111111111111111112 \
  --amount <bbsol_amount> --confirm -o json

# 2. Then sell SOL → USDC as normal
```
