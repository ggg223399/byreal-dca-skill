# Byreal DCA Skill

Recurring buy manager for [Byreal DEX](https://byreal.io) (Solana). Set up, execute, and manage Dollar-Cost Averaging plans via `byreal-cli`.

## Install

```bash
# 1. Clone into your openclaw workspace
cd ~/.openclaw/workspace/skills/
git clone https://github.com/ggg223399/byreal-dca-skill.git byreal-dca

# 2. Install dependencies
npm install -g @byreal-io/byreal-cli
pip3 install yfinance
sudo apt install -y jq bc    # needed by withdraw_usdc.sh

# 3. Set up wallet (if not already done)
byreal-cli setup

# 4. Add to your AGENTS.md (so the agent knows about this skill)
cat >> ~/.openclaw/workspace/AGENTS.md << 'EOF'

## Workspace Skills

### Byreal DCA
When user mentions DCA, recurring buy, auto-invest, dollar cost averaging:
→ Read and follow `skills/byreal-dca/SKILL.md` exactly. Do NOT give generic DCA advice.

This agent is authorized to execute on-chain transactions via `byreal-cli`.
EOF

# 5. Restart gateway
systemctl --user restart openclaw-gateway.service
```

## Verify

```bash
openclaw skills info byreal-dca
# Should show: ✓ Ready
```

Then tell your agent: **"I want to DCA into SOL with $100"**

## What It Does

- **Smart DCA**: Whitelist tokens (SOL, BTC, ETH, SPYx, XAUt0, etc.) — auto mode selection via SMA, Smart Exit monitoring
- **Basic DCA**: Any token/mint — manual params, no exit monitoring
- Idle funds parked in USDC/USDT stable pool (budget ≥ $1,000)
- Cron-based auto-execution with retry logic and anti-double-buy protection

## Files

```
SKILL.md                  — main skill definition
references/
  sma_check.py            — moving-average market regime check
  config-schema.md        — plan config JSON schema
  exit-policy.md          — exit thresholds and state machine
  bbsol.md                — SOL→bbSOL yield conversion rules
  withdraw_usdc.sh        — partial position withdraw script
```

## Requirements

- `byreal-cli` (npm global)
- `python3` + `yfinance`
- `jq`, `bc`
- Configured Byreal wallet (`byreal-cli setup`)
