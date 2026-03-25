---
name: byreal-dca
description: |
  Recurring buy manager for Byreal DEX (Solana). Set up, execute, and manage Dollar-Cost Averaging plans via byreal-cli. Use when the user wants to DCA into a token, set up recurring buys, check plan status, pause/resume/cancel a plan, adjust amount or frequency, add funds, or exit a DCA position.
metadata:
  openclaw:
    emoji: "📈"
    requires:
      bins: [byreal-cli, python3, jq, bc]
    install:
      - kind: node
        package: "@byreal-io/byreal-cli"
        global: true
---

# Byreal DCA

Recurring buy manager for Byreal. Simple by default, recommendation-first, verify before claiming success, ask before any sell.

Two modes: **Smart DCA** (whitelist tokens — auto strategy, exit monitoring) and **Basic DCA** (non-whitelist token / mint / manual params).

- Whitelist token + budget → Smart DCA
- Non-whitelist token, mint address, or manual-control intent → Basic DCA

### Whitelist Tokens

| Token | Ticker (yfinance) | Category |
|-------|------------------|----------|
| BTC | BTC-USD | Crypto |
| SOL | SOL-USD | Crypto |
| wETH | ETH-USD | Crypto |
| XAUt0 | GC=F | Gold |
| SPYx | SPY | US Equity Index |
| QQQx | QQQ | US Equity Index |
| NVDAx | NVDA | US Stock |
| GOOGLx | GOOGL | US Stock |
| TSLAx | TSLA | US Stock |
| AMZNx | AMZN | US Stock |
| CRCLx | CRCL | US Stock |
| COINx | COIN | US Stock |

Only these tokens get auto mode selection (SMA check), Smart Exit monitoring, and recommended defaults. Any other token/mint → Basic DCA.

---

## Prerequisites

```bash
# Check installation
which byreal-cli && byreal-cli --version
python3 -c "import yfinance; print('yfinance ok')"

# Wallet (required for all write operations)
byreal-cli wallet address
# → returns address → ready
# → WALLET_NOT_CONFIGURED → tell user to run `byreal-cli setup`

# Load full CLI documentation
byreal-cli skill
```

---

## Available Tools

### 1. Market Regime Check

**Use when**: Creating a new plan, or cron needs to determine buy mode.

```bash
python3 {baseDir}/references/sma_check.py SOL --ma 200
```

Output:
```json
{"token": "SOL", "ticker": "SOL-USD", "price": 148.20, "ma": 142.50, "ma_window": 200, "signal": "above"}
```

| Signal | Mode |
|--------|------|
| `above` | Standard — fixed daily amount |
| `below` | Defensive — 30% of daily amount |
| `unavailable` | Standard (fallback) |

Default regime check (buy mode) always uses `--ma 200`. Exit trend checks use the duration buckets in the Exit thresholds section below.

Cache: one check per day per plan. See `references/sma_check.py` for ticker mapping.

### 2. Swap

**Use when**: Executing a buy (USDC → token) or sell (token → USDC).

```bash
# Preview (always do this first)
byreal-cli swap execute \
  --input-mint EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v \
  --output-mint So11111111111111111111111111111111111111112 \
  --amount 20 --dry-run -o json

# Execute
byreal-cli swap execute \
  --input-mint EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v \
  --output-mint So11111111111111111111111111111111111111112 \
  --amount 20 --confirm -o json
```

`--amount` is UI format (20 = $20 USDC). CLI auto-resolves decimals.

After `--confirm`, MUST check response: `data.confirmed === true`. If `false`, tx was submitted but not confirmed on-chain — treat as failed, do NOT record in execution_log. Tell user the buy will be retried on the next cron run. If this happens during plan creation, still save the config and register cron, but keep `remaining_usdc = total_budget` because no confirmed buy occurred.

### 3. Stable Pool Position

**Use when**: Parking idle USDC (plan creation), withdrawing USDC before a cron buy, or closing on cancel/complete.

Idle USDC earns yield in a stable pool. Only use for plans with budget ≥ $1,000. For smaller plans, leave USDC in wallet.

The CLI only supports full close — no partial withdraw. Use `references/withdraw_usdc.sh` to withdraw a specific amount (close → consolidate to USDC → reopen with remainder).

```bash
# Open position (park idle funds — stable pool needs price bounds around 1.0)
byreal-cli positions open --pool <pool-addr> --amount-usd <idle_amount> \
  --price-lower 0.99 --price-upper 1.01 --confirm -o json

# Withdraw USDC for a cron buy (close → swap USDT→USDC → reopen with rest)
bash {baseDir}/references/withdraw_usdc.sh <nft-mint> <pool-addr> <amount>
# Output: {"success": true, "withdrawn_usdc": 20.00, "new_position_id": "...", "remaining_parked": 960.00}
# → Update idle_yield.position_id with new_position_id in config

# Full close (cancel/complete — no reopen)
byreal-cli positions close --nft-mint <position-addr> --confirm -o json
# → Returns USDC + USDT. Swap USDT → USDC after if needed.
```

Stable pools require BOTH USDC and USDT. Before opening:
1. Check wallet USDT balance via `byreal-cli wallet balance -o json`
2. If USDT insufficient → swap half of idle amount: USDC → USDT
3. Then open position

Use the pool with higher TVL (check via `byreal-cli pools info <pool-addr> -o json`).

**Accounting rule**: `budget_tracking.remaining_usdc` is the budget source of truth and only decreases by confirmed buy spend (`execution_log.amount_usdc` for `action="buy"`). Do NOT decrease it by LP withdrawal amount. Position actual balance will drift from this due to yield gains, close/reopen friction, and wallet buffer leftover from withdrawals. Do NOT try to reconcile them during the plan. On plan completion, close position and report the difference as net idle yield plus cash-management drift.

### 4. Config Manager

**Use when**: Creating, reading, or updating plan state.

```
Smart DCA: ~/.config/byreal/dca/<TOKEN>.json  (one per token)
Basic DCA: ~/.config/byreal/dca/<plan_id>.json
```

Read config → determine plan state, schedule, budget remaining.
Write config → update after each buy/sell, status change, or user modification.

Key fields for quick status:
- `plan_state.status` — drives cron and agent behavior:

| Status | Cron does | User sees |
|--------|----------|-----------|
| `active` | Execute buy | "On Track" |
| `paused` | Skip | "Paused" |
| `attention_required` | Skip, notify | "Needs Attention" + reason |
| `holding_only` | Skip buy, monitor exit | "Holding (no more buys)" |
| `completed` | Skip | "Completed" |
| `cancelled` | Skip | "Cancelled" |
- `budget_tracking` — invested_usdc, remaining_usdc, avg_entry_price
- `schedule.last_run_at` — when cron last ran
- `execution_log` — array of all buys/sells with txid

Source of truth:
- holdings → `execution_log` (sum buys - sum sells)
- remaining budget → `budget_tracking.remaining_usdc` (actual budget left for future buys)
- parked idle funds → `idle_yield.position_id` (optional, budget ≥ $1k only)
- position actual balance ≠ remaining_usdc (yield + friction drift + wallet buffer — reconcile only at plan end)

Full schema: `references/config-schema.md`.

---

## Quick Start Workflows

### Example: "DCA into SOL with $1000"

```
1. Prerequisites     → byreal-cli wallet address
2. Token lookup      → byreal-cli tokens list -o json → SOL supported → Smart DCA
3. Pre-flight        → ls ~/.config/byreal/dca/SOL.json → no existing plan
4. Market check      → python3 {baseDir}/references/sma_check.py SOL --ma 200 → signal: above → Standard
5. Calculate          → $1000 → $20/day × ~50 days
6. Confirm            → show plan summary (see Response Formats), one question
7. Execute Phase 4    → dry-run → buy → park idle funds if ≥$1k → save config → register cron
```

### Example: "Pause my DCA" / "Sell my SOL"

```
1. Read config        → check status, holdings, exit state, return
2. Pause path         → set status=paused, confirm plan is paused
3. Sell path          → recommend one default option based on current state
4. Wait               → user must confirm before any sell
5. Execute            → sell flow (see Exit workflow)
```

---

## Workflow: Create Plan

### Phase 1 — Pre-flight

Check `~/.config/byreal/dca/` for existing config for the same token.

- Active plan exists → **do NOT create a second one**. Offer: add funds / modify / cancel and start fresh.
- No active plan → proceed.

Check prerequisites (wallet, byreal-cli, yfinance). If wallet not configured → stop, tell user to run `byreal-cli setup`.

### Phase 2 — Gather

**When user provides token + budget** → go directly to step 1 below.

**When user intent is vague** ("I want to DCA", "help me DCA", no token/budget specified):
Do NOT ask 4 separate questions. Instead, auto-recommend:

```
1. Check wallet USDC balance  → byreal-cli wallet balance -o json
2. Get token prices            → byreal-cli tokens list -o json
3. Pick default recommendation:
   → Token: SPYx or XAUt0 (stable long-term assets; prefer SPYx for equity exposure, XAUt0 for gold hedge — pick based on user context, default SPYx)
   → Budget: 80% of wallet USDC (round down to nearest $5, leave buffer for gas)
   → Daily amount: from budget table below
   → Mode: from SMA check
4. Present ONE recommendation with rationale → go to Phase 3 Confirm
   Example: "You have $42 USDC. Recommended: SOL DCA, $40 budget, $5/day × 8 days, Standard mode. Confirm?"
   User can adjust any parameter in their reply.
```

**Smart DCA** — token + total budget known:

```
1. Identify token     → byreal-cli tokens list -o json
                         Whitelist token → Smart DCA
                         Non-whitelist token or mint address → Basic DCA
2. Market check       → python3 {baseDir}/references/sma_check.py <TOKEN> --ma 200
                         above → Standard | below → Defensive
3. Daily amount:
   | Budget       | Amount/Day |
   |-------------|-----------|
   | < $100      | $5        |
   | $100–500    | $10       |
   | $500–2,000  | $20       |
   | $2,000–10k  | $50       |
   | $10,000+    | $100      |
4. For SOL → ask once if user wants bbSOL yield on holdings
```

**Basic DCA** — user provides mint/token + amount + frequency:

```
1. Collect: token or mint + amount + frequency
2. If incomplete → ask ONE question: "How much and how often? e.g. $20/day or $100/week"
3. No auto mode, no Smart Exit
```

### Phase 3 — Confirm

Show plan summary. Ask for ONE confirmation. See Response Formats: Plan Confirmation.

Defensive: show both amounts — "Base: $20/day, Defensive (current): $6/day — price is below SMA200."
Aggressive (only if user requests): show reserve calculation.

### Phase 4 — Execute

On confirmation, execute ALL steps in order. Do NOT skip any.

```bash
# 1. Dry-run first buy from wallet USDC
byreal-cli swap execute \
  --input-mint EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v \
  --output-mint <token-mint> \
  --amount <daily_amount> --dry-run -o json
# → Check priceImpactPct: > 1% → STOP, report; > 0.2% → warn

# 2. Execute first buy
byreal-cli swap execute \
  --input-mint EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v \
  --output-mint <token-mint> \
  --amount <daily_amount> --confirm -o json
# → MUST verify data.confirmed === true



# 3. If bbSOL enabled (SOL only)
byreal-cli swap execute \
  --input-mint So11111111111111111111111111111111111111112 \
  --output-mint <bbSOL-mint> \
  --amount <bought_sol> --confirm -o json

# 4. Park idle funds (only if total_budget ≥ $1,000)
#    idle_amount = total_budget - daily_amount
#    (swap half to USDT first if needed)
byreal-cli positions open --pool <pool-addr> --amount-usd <idle_amount> \
  --price-lower 0.99 --price-upper 1.01 --confirm -o json
# → Save returned position address as idle_yield.position_id
# → If fails → plan stays active, funds remain in wallet, idle_yield.position_id = null
# → If budget < $1,000 → skip this step, funds stay in wallet

# 5. Save config to ~/.config/byreal/dca/<TOKEN>.json

# 6. Register cron if not already registered (see below)
```

Config write rules:
- If first buy confirmed: `remaining_usdc = total_budget - actual_buy_spend_usdc`, and append the confirmed buy to `execution_log`
- If first buy not confirmed: `remaining_usdc = total_budget`, and leave `execution_log` empty
- LP parking amount does not reduce `remaining_usdc`

### Phase 5 — Verify

```
1. Read back saved config → confirm it parses correctly
2. Check cron → openclaw cron list --json | grep byreal-dca
3. Report: "Plan created. First buy: 0.135 SOL at $148.20. Next buy: Mar 26, 2026 10:00 UTC."
```

### Cron Registration

One cron serves ALL plans. Register on first plan creation only.

```bash
# Check first — NEVER create a duplicate
openclaw cron list --json | grep -q byreal-dca

# Register if not found
openclaw cron add \
  --name byreal-dca \
  --every 1h \
  --session isolated \
  --timeout-seconds 600 \
  --announce \
  --to <user_telegram_id> \
  --message "DCA executor. FIRST read the skill file at ~/.openclaw/workspace/skills/byreal-dca/SKILL.md — follow the 'Workflow: Daily Execution (Cron)' section exactly, including retry logic and exit monitoring. Read all ~/.config/byreal/dca/*.json. For each active plan: execute the full cron workflow from the skill. Report results."
```

---

## Workflow: Daily Execution (Cron)

For each active config in `~/.config/byreal/dca/*.json`:

```
 1. Check if due        → skip if already executed today (or < interval)
 2. Check budget        → remaining_usdc ≤ 0 → if holdings > 0 set `holding_only`, otherwise go to Completion Flow
 3. Determine amount:
    Standard:   fixed amount_per_buy
    Defensive:  python3 {baseDir}/references/sma_check.py <TOKEN> --ma 200
                → above: 100% | below: 30%
    Aggressive: base × 1.2^step (cap at remaining, persist step in mode_params)
    Basic:      fixed amount_per_buy
 4. Get USDC for this buy:
    a. If idle_yield.position_id exists → ALWAYS withdraw from position:
       → bash {baseDir}/references/withdraw_usdc.sh <nft-mint> <pool-addr> <buy_amount>
       → verify `withdrawn_usdc >= buy_amount`
       → Update idle_yield.position_id with new_position_id from output
       → If withdraw fails → status=attention_required, STOP
       (Wallet USDC belongs to the user, not to the plan. Never spend it directly.)
    b. If no position → check wallet USDC balance:
       → wallet USDC ≥ buy amount → proceed to step 5
       → wallet USDC < buy amount → status=attention_required, STOP
 5. Dry-run quote
    → priceImpactPct > 1% → status=attention_required, STOP
    → route fails → log, skip, notify
 6. Record pre-buy token balance (byreal-cli wallet balance -o json)
 7. Execute swap (byreal-cli swap execute ... --confirm -o json)
 8. Check result:
    → data.confirmed === true → SUCCESS, go to step 9
    → confirmed === false OR swap error → RETRY FLOW:
      a. Wait 5 minutes
      b. Check token balance again
      c. Balance increased → buy actually landed, treat as SUCCESS
      d. Balance unchanged → safe to retry, execute swap again
      e. Retry also fails → record as missed, go to step 9 (failure path)
    ⚠ NEVER retry without the balance check — risk of double buy
 9. If bbSOL enabled → SOL → bbSOL
10. Update config:
    Success:
    → execution_log: append buy record with txid
    → budget_tracking.remaining_usdc -= actual_buy_spend_usdc
    → budget_tracking.invested_usdc += actual_buy_spend_usdc
    → plan_state.consecutive_failures = 0
    → schedule.last_run_at = now
    Failure (step 8e):
    → execution_log: append record with action="missed", reason
    → plan_state.consecutive_failures += 1
    → if consecutive_failures ≥ 3 → status=attention_required
    → schedule.last_run_at = now
11. Check exit conditions (Smart DCA only — see Exit workflow)
12. Report: one line per token (see Response Formats: Daily Report)
```

No catch-up logic by default.

### Completion Flow

When `remaining_usdc <= 0`:

```
1. If holdings > 0:
   → set plan_state.status = holding_only
   → keep Smart Exit monitoring active
   → notify user: buy budget is exhausted, plan is now holding and monitoring exits
   → STOP
2. If idle_yield.position_id exists:
   → byreal-cli positions close --nft-mint <position-addr> --confirm -o json
   → swap returned USDT → USDC if needed
   → compare recovered idle funds vs budget remainder (= 0)
   → report difference as net idle yield / cash-management drift
   → set idle_yield.position_id = null
3. Set plan_state.status = completed
4. Set schedule.last_run_at = now
5. Notify user with final invested amount, holdings, and recovered idle funds
```

---

## Workflow: Management

| User says | Action |
|-----------|--------|
| "DCA status" | Read all configs, show state-first status report |
| "Pause DCA" | Set status=paused. Position stays earning yield. |
| "Resume DCA" | Set status=active. |
| "Cancel DCA" | Stop buying. Ask: (1) sell all now, (2) sell gradually, (3) keep holding. Close position when done. |
| "Add $500 more" | Increase total_budget and remaining_usdc. If position exists, deposit additional funds to position. |
| "Make it $10/day" | Change amount_per_buy, recalculate duration, confirm. |
| "Switch to aggressive" | Change mode, calculate reserve, confirm. |
| "Run now" | Execute buy immediately (same as cron step 3-12). |
| "Skip today" | Log as skipped in execution_log. |

When answering status, lead with state → progress → next action → return.

---

## Workflow: Exit (Smart DCA Only)

Smart Exit **monitors** automatically but **always asks before selling**.

### Thresholds

Plan duration buckets are based on the planned schedule:
- `planned_days = ceil(total_budget / amount_per_buy)`
- 1–3 mo = 30–89 days
- 3–6 mo = 90–179 days
- 6–12 mo = 180–364 days
- 12+ mo = 365+ days

| Plan Duration | Take Profit | Trailing Stop | DCA-out Days | Trend MA |
|--------------|------------|---------------|-------------|----------|
| 1–3 mo | +20% | -10% | 4–7 | 50 |
| 3–6 mo | +40% | -15% | 7–14 | 50 |
| 6–12 mo | +50% | -20% | 14–21 | 200 |
| 12+ mo | +100% | -25% | 21–28 | 200 |

### State Machine

```
inactive → return ≥ TP
  → "tracking" — notify user, record peak, NO sell

tracking → drawdown from peak ≥ TS
  → ASK user (see Response Formats: Exit Recommendation)
  → Approved → "selling" | Declined → stay in tracking

selling → each cron run:
  1. Trend check: python3 {baseDir}/references/sma_check.py <TOKEN> --ma <trend_ma>
     → price above trend MA → pause, notify
  2. Adaptive sell: (holdings / remaining_periods) × (price / avg_cost)
     bounded 0.5×–2.0× base amount
  3. If bbSOL → convert to SOL first
  4. Execute sell (swap token → USDC), deposit proceeds to position

paused → trend reverts below MA → resume
       → timeout → ask user

completed → close position, final report
```

| User says | Action |
|-----------|--------|
| "Sell my SOL" | Show exit state, recommend one option |
| "Sell over N days" | Manual DCA-out with adaptive sizing + trend pause |
| "Turn off auto exit" | Set exit.mode=manual |
| "Emergency sell" | Full sell at market, require confirmation |

Full exit policy details: `references/exit-policy.md`.

---

## Response Formats

### Plan Confirmation

```text
DCA Plan for SOL
━━━━━━━━━━━━━━━━
Budget:     $1,000 USDC
Schedule:   $20/day × ~50 days
Mode:       Standard (price above SMA200)
Idle funds: Wallet or stable pool parking
Exit:       Smart Exit monitors, asks before any sell
First buy:  now

Confirm? (yes / adjust amount / change mode)
```

### Status Report

```text
SOL DCA — On Track
━━━━━━━━━━━━━━━━━━
Budget:    $200 / $1,000 invested (20%)
Holdings:  1.35 SOL (~$200.50)
Return:    +$0.50 (+0.25%)
Avg cost:  $148.15
Next buy:  $20 on Mar 26, 2026 10:00 UTC
Mode:      Standard
```

If `pending_action` or `last_error` exists, surface it first:
```text
SOL DCA — Needs Attention
━━━━━━━━━━━━━━━━━━━━━━━━━
⚠ Insufficient USDC — wallet and position both empty.
   Deposit USDC to continue.
```

### Daily Report (Cron)

```text
DCA Daily Report
━━━━━━━━━━━━━━━━
SOL: bought $20 → 0.133 SOL @ $150.20 | 10/50 buys | +1.2% return
BTC: skipped (price impact 1.8%) | 5/30 buys | -0.5% return
```

### Exit Recommendation

```text
SOL has dropped 22% from its recent peak ($185 → $144).

Recommendation: sell gradually over 14 days.

Options:
1. Approve gradual exit (recommended)
2. Keep holding
3. Sell all now at market
```

---

## Hard Constraints

1. First buy requires user confirmation — never execute without approval.
2. All sells require user confirmation — buys auto-execute after plan approval, sells never.
3. Dry-run before every swap — first buy and every cron buy.
4. Verify `data.confirmed === true` after every `--confirm` swap — if false, treat as failed, do NOT record in execution_log.
5. Price impact > 1% → abort, set status=attention_required. Price impact > 0.2% → warn but proceed.
6. Never claim success without txid proof.
7. Never display private keys — keypair paths only.
8. Track plan holdings from execution_log — never use raw wallet balance as plan holdings. `plan_holdings = sum(buys) - sum(sells)`.
9. `budget_tracking.remaining_usdc` only decreases by confirmed buy spend. Never decrease it by LP withdrawal amount, wallet buffer changes, or parking operations.
10. One Smart DCA plan per token — check before creating.
11. Failure → log, skip, notify. No blind retry.

---

## Troubleshooting

| Error | Cause | Action |
|-------|-------|--------|
| `WALLET_NOT_CONFIGURED` | No keypair set up | Stop. Tell user: `byreal-cli setup` |
| `INSUFFICIENT_BALANCE` | Wallet USDC < buy amount and withdraw failed, returned too little, or no position exists | Set attention_required, notify user to deposit USDC |
| withdraw_usdc.sh fails | Position close or reopen failed | Funds may be in wallet as USDC+USDT; set attention_required, report state |
| priceImpactPct > 1% | Low liquidity | Skip this buy, retry next cycle |
| Route not found | No swap path on Byreal DEX | Log, skip, notify — do not retry |
| `data.confirmed === false` | TX submitted but not confirmed on-chain | Treat as failed, do not record |
| yfinance timeout | SMA data unavailable | Default to Standard mode |
| Config JSON parse error | Corrupted config file | Set attention_required, do not execute |
| Position open fails | Stable pool issue or insufficient funds | Keep plan active with funds in wallet, report idle-yield setup failed |
| Duplicate cron | `openclaw cron list` shows existing byreal-dca | Skip registration, proceed normally |

---

## CLI Quick Reference

| Operation | Command |
|-----------|---------|
| Wallet check | `byreal-cli wallet address` |
| Wallet balance | `byreal-cli wallet balance -o json` |
| List tokens | `byreal-cli tokens list -o json` |
| Swap dry-run | `byreal-cli swap execute --input-mint <in> --output-mint <out> --amount <n> --dry-run -o json` |
| Swap execute | `byreal-cli swap execute --input-mint <in> --output-mint <out> --amount <n> --confirm -o json` |
| Open position | `byreal-cli positions open --pool <pool> --amount-usd <n> --price-lower 0.99 --price-upper 1.01 --confirm -o json` |
| Close position | `byreal-cli positions close --nft-mint <addr> --confirm -o json` |
| List positions | `byreal-cli positions list -o json` |
| Pool info | `byreal-cli pools info <pool-addr> -o json` |
| Full CLI docs | `byreal-cli skill` |

Use `references/withdraw_usdc.sh` for per-buy position withdraw (close → consolidate → reopen).

### Known Addresses

| Token | Mint |
|-------|------|
| USDC | `EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v` |
| USDT | `Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB` |
| SOL | `So11111111111111111111111111111111111111112` |

### Stable Pools

| Pool | Address |
|------|---------|
| Pool A | `HrWp3QR3hNeVy6tEZtcpsjwEiGgKJuL1NDP84EaaU2Nh` |
| Pool B | `23XoPQqGw9WMsLoqTu8HMzJLD6RnXsufbKyWPLJywsCT` |

Use the pool with higher TVL.

---

## References

| File | Content | Load when |
|------|---------|-----------|
| `references/sma_check.py` | MA market check script with ticker mapping | Creating plan or cron needs mode check |
| `references/withdraw_usdc.sh` | Position withdraw: close → consolidate USDC → reopen | Cron buy when wallet USDC insufficient |
| `references/config-schema.md` | Full plan config JSON schema | Creating or updating plan config |
| `references/exit-policy.md` | Exit state machine, adaptive sell formula | Exit monitoring triggers or user asks about selling |
| `references/bbsol.md` | SOL→bbSOL conversion, accounting rules | SOL plan with bbSOL enabled |

For broader CLI details beyond the quick reference above: `byreal-cli skill`.
