# Byreal DCA v7 — Claude Draft

Built from v6-fused skeleton + v4-claude concrete content.

## Design Goals

- Keep v6's structure: When To Use → Available Tools → Quick Start → Workflows → Response Formats → Hard Constraints → Troubleshooting → References
- Restore concrete commands stripped in v6: swap commands with real mint addresses, position commands, cron registration, price impact thresholds
- Available Tools with real "Use when" + executable commands + output examples (from trading-research pattern)
- Phase-based plan creation with real CLI commands at each phase (from nanoclaw pattern)
- Response Formats kept from v6
- References self-contained in this folder (not dependent on parent paths)

## Files

```
SKILL.md                        — main skill definition (~430 lines)
references/
  sma_check.py                  — moving-average market check script
  config-schema.md              — full plan config JSON schema
  exit-policy.md                — exit thresholds, state machine, adaptive sell
  bbsol.md                      — SOL→bbSOL yield conversion rules
```

## What Changed from v6

- "Core Capabilities" → "Available Tools" with real commands and output examples
- Workflows have concrete byreal-cli commands at key steps
- CLI Quick Reference table + mint addresses + stable pool addresses restored
- Hard Constraints have specific thresholds (1% abort, 0.2% warn)
- Troubleshooting has cause column
- Removed design-doc language ("should feel like", "do not front-load")
- References are self-contained (no ../references/ parent paths)
- v7.1 cleanup: MA check is parameterized (`--ma 50|200`), `unavailable` is schema-valid, and the skill no longer assumes undocumented partial position withdraw support
