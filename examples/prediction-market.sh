#!/bin/bash
# Example: Prediction market oracle - "Will BCH reach $500 by end of Q1 2026?"

set -e

API_URL="http://localhost:8080"

echo "=== Prediction Market Oracle Example ==="
echo ""
echo "Question: Will BCH reach $500 by March 31, 2026?"
echo ""

# Create the prediction task
echo "Creating prediction market task..."
TASK_RESPONSE=$(curl -s -X POST "$API_URL/tasks" \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "BCH $500 by Q1 2026",
    "source_url": "https://api.coinbase.com/v2/prices/BCH-USD/spot",
    "prompt": "Current BCH price from Coinbase API:\n{content}\n\nHas BCH reached or exceeded $500 USD? Answer YES or NO only.",
    "parse_rule": "yes_no",
    "interval_seconds": 3600
  }')

TASK_ID=$(echo "$TASK_RESPONSE" | grep -o '"id":[0-9]*' | cut -d':' -f2)
echo "✓ Task created with ID: $TASK_ID"
echo ""

# Deploy contract
echo "Deploying smart contract..."
curl -s -X POST "$API_URL/tasks/$TASK_ID/deploy-contract"
echo ""
sleep 2

# Run immediately
echo "Running initial check..."
curl -s -X POST "$API_URL/tasks/$TASK_ID/run"
echo ""
sleep 5

# Show results
echo ""
echo "Latest result:"
curl -s "$API_URL/tasks/$TASK_ID/results" | python3 -c "
import sys, json
results = json.load(sys.stdin)
if results:
    r = results[0]
    print(f\"  Answer: {r['parsed_value'].upper()}\")
    print(f\"  Time: {r['executed_at']}\")
    print(f\"  Success: {r['success']}\")
"
echo ""

echo "=== Prediction Market Oracle Active ==="
echo ""
echo "This oracle will check every hour and publish YES/NO on-chain."
echo "Smart contract address: See contracts/artifacts/contract-$TASK_ID.json"
echo ""
echo "Use cases:"
echo "  - Betting markets"
echo "  - Conditional payments"
echo "  - Automated settlements"
echo "  - Trustless escrow"
