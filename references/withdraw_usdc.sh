#!/usr/bin/env bash
# withdraw_usdc.sh — Withdraw a specific USDC amount from a stable pool position.
#
# Since byreal-cli does not support partial liquidity removal, this script:
#   1. Closes the entire position (receives USDC + USDT)
#   2. Swaps all USDT → USDC (consolidate to single currency)
#   3. Keeps the requested withdraw amount in wallet
#   4. Reopens a position with the remainder (if > $10)
#
# Usage:
#   bash withdraw_usdc.sh <nft-mint> <pool-addr> <withdraw-amount-usd>
#
# Example:
#   bash withdraw_usdc.sh 7Kz...abc HrWp...2Nh 20
#
# Output (JSON):
#   {"success": true, "withdrawn_usdc": 20.00, "new_position_id": "8Lm...def", "remaining_parked": 960.00}
#   {"success": false, "error": "...", "recovered": true}
#
# Requirements:
#   - byreal-cli with configured wallet
#   - jq

set -euo pipefail

NFT_MINT="${1:?Usage: withdraw_usdc.sh <nft-mint> <pool-addr> <withdraw-amount-usd>}"
POOL_ADDR="${2:?Usage: withdraw_usdc.sh <nft-mint> <pool-addr> <withdraw-amount-usd>}"
WITHDRAW_AMOUNT="${3:?Usage: withdraw_usdc.sh <nft-mint> <pool-addr> <withdraw-amount-usd>}"

USDC_MINT="EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
USDT_MINT="Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"
MIN_REOPEN=10  # Don't reopen position if remainder < $10

die() { echo "{\"success\": false, \"error\": \"$*\", \"recovered\": false}" >&2; exit 1; }

# --- Step 1: Close the position entirely ---

CLOSE_RESULT=$(byreal-cli positions close --nft-mint "$NFT_MINT" --confirm -o json 2>/dev/null) \
  || die "positions close failed"

CONFIRMED=$(echo "$CLOSE_RESULT" | jq -r '.data.confirmed // false')
[ "$CONFIRMED" = "true" ] || die "close tx not confirmed on-chain"

# Wait for on-chain state propagation
sleep 4

# --- Step 2: Check USDT balance and swap all USDT → USDC ---

BALANCE_RESULT=$(byreal-cli wallet balance -o json 2>/dev/null) \
  || die "wallet balance check failed"

USDT_BALANCE=$(echo "$BALANCE_RESULT" | jq -r \
  ".data.tokens[] | select(.mint == \"$USDT_MINT\") | .uiAmount // 0" 2>/dev/null || echo "0")

# Only swap if we have USDT > 0.01
if [ "$(echo "$USDT_BALANCE > 0.01" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
  SWAP_RESULT=$(byreal-cli swap execute \
    --input-mint "$USDT_MINT" \
    --output-mint "$USDC_MINT" \
    --amount "$USDT_BALANCE" \
    --confirm -o json 2>/dev/null) || die "USDT→USDC swap failed after close"

  SWAP_CONFIRMED=$(echo "$SWAP_RESULT" | jq -r '.data.confirmed // false')
  [ "$SWAP_CONFIRMED" = "true" ] || die "USDT→USDC swap not confirmed"

  sleep 3
fi

# --- Step 3: Check total USDC now available ---

BALANCE_AFTER=$(byreal-cli wallet balance -o json 2>/dev/null) \
  || die "balance check after swap failed"

USDC_TOTAL=$(echo "$BALANCE_AFTER" | jq -r \
  ".data.tokens[] | select(.mint == \"$USDC_MINT\") | .uiAmount // 0" 2>/dev/null || echo "0")

# Sanity check: do we have enough?
if [ "$(echo "$USDC_TOTAL < $WITHDRAW_AMOUNT" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
  # Not enough — return everything we have, don't reopen
  echo "{\"success\": true, \"withdrawn_usdc\": $USDC_TOTAL, \"new_position_id\": null, \"remaining_parked\": 0, \"warning\": \"position had less than requested\"}"
  exit 0
fi

# --- Step 4: Reopen position with remainder ---

REMAINDER=$(echo "$USDC_TOTAL - $WITHDRAW_AMOUNT" | bc -l)

if [ "$(echo "$REMAINDER < $MIN_REOPEN" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
  # Remainder too small to reopen — keep it all in wallet
  echo "{\"success\": true, \"withdrawn_usdc\": $USDC_TOTAL, \"new_position_id\": null, \"remaining_parked\": 0}"
  exit 0
fi

# Need to swap half of remainder to USDT for the stable pool
HALF_REMAINDER=$(echo "$REMAINDER / 2" | bc -l)

SWAP_HALF=$(byreal-cli swap execute \
  --input-mint "$USDC_MINT" \
  --output-mint "$USDT_MINT" \
  --amount "$HALF_REMAINDER" \
  --confirm -o json 2>/dev/null) || {
    # Swap failed — funds stay in wallet, report partial success
    echo "{\"success\": true, \"withdrawn_usdc\": $WITHDRAW_AMOUNT, \"new_position_id\": null, \"remaining_parked\": 0, \"warning\": \"could not reopen position, remainder stays in wallet\"}"
    exit 0
  }

sleep 3

OPEN_RESULT=$(byreal-cli positions open --pool "$POOL_ADDR" \
  --amount-usd "$REMAINDER" \
  --price-lower 0.99 --price-upper 1.01 \
  --confirm -o json 2>/dev/null) || {
    # Open failed — remainder stays in wallet as USDC+USDT
    echo "{\"success\": true, \"withdrawn_usdc\": $WITHDRAW_AMOUNT, \"new_position_id\": null, \"remaining_parked\": 0, \"warning\": \"position reopen failed, remainder in wallet\"}"
    exit 0
  }

OPEN_CONFIRMED=$(echo "$OPEN_RESULT" | jq -r '.data.confirmed // false')
if [ "$OPEN_CONFIRMED" != "true" ]; then
  echo "{\"success\": true, \"withdrawn_usdc\": $WITHDRAW_AMOUNT, \"new_position_id\": null, \"remaining_parked\": 0, \"warning\": \"position reopen tx not confirmed\"}"
  exit 0
fi

NEW_POSITION=$(echo "$OPEN_RESULT" | jq -r '.data.nftMint // .data.address // "unknown"')
REMAINING_PARKED=$(printf "%.2f" "$REMAINDER")
WITHDRAWN=$(printf "%.2f" "$WITHDRAW_AMOUNT")

echo "{\"success\": true, \"withdrawn_usdc\": $WITHDRAWN, \"new_position_id\": \"$NEW_POSITION\", \"remaining_parked\": $REMAINING_PARKED}"
